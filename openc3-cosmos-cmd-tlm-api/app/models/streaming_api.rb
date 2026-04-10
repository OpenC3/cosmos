# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

require 'openc3'
OpenC3.require_file 'openc3/utilities/authorization'
OpenC3.require_file 'openc3/models/target_model'
require_relative 'logged_streaming_thread'
require_relative 'realtime_streaming_thread'
require_relative 'streaming_key'
require_relative 'streaming_object'
require_relative 'streaming_object_collection'

class StreamingApi
  include OpenC3::Authorization

  def initialize(subscription_key, scope: nil)
    @subscription_key = subscription_key
    @mutex = Mutex.new
    @realtime_thread = nil
    @logged_threads = []
  end

  # Create new StreamingObjects using the data['items'] and add them to the StreamingObjectCollection
  def build_item_collection(collection, data, start_time: nil, end_time: nil, scope: nil, token: nil)
    data["items"].each do |key, item_key|
      item_key = key unless item_key
      # Unwrap LATEST packet into individual items
      parsed = StreamingKey.parse(key, item_key: true)
      if parsed.packet_name == 'LATEST'
        item_map = OpenC3::TargetModel.get_item_to_packet_map(parsed.target_name, scope: scope)
        packet_names = item_map[parsed.item_name]
        raise RuntimeError, "Item '#{parsed.target_name} LATEST #{parsed.item_name}' does not exist for scope: #{scope}" unless packet_names
        packet_names.each do |packet_name|
          new_key = parsed.with(packet_name: packet_name).to_key_string
          collection.add(StreamingObject.new(new_key, start_time, end_time, item_key: item_key, scope: scope, token: token))
        end
      else
        collection.add(StreamingObject.new(key, start_time, end_time, item_key: item_key, scope: scope, token: token))
      end
    end
  end

  # Expand ANY packet key containing COSMOS_ALL into individual packet keys.
  # Supports:
  #   MODE__CMDORTLM__COSMOS_ALL[__VALUETYPE]          - all targets, all packets
  #   MODE__CMDORTLM__TARGET__COSMOS_ALL[__VALUETYPE]  - one target, all packets
  # Unauthorized packets are silently skipped (Option A).
  def expand_all_packets(data, scope:)
    return unless data["packets"]

    expanded = []
    data["packets"].each do |key|
      parsed = StreamingKey.parse(key)

      if parsed.target_name == 'COSMOS_ALL'
        # MODE__CMDORTLM__COSMOS_ALL[__VALUETYPE]
        # When target_name is COSMOS_ALL, the value type occupies the packet_name position
        value_type = parsed.packet_name.empty? ? nil : parsed.packet_name
        type = (parsed.cmd_or_tlm == :CMD) ? :CMD : :TLM
        targets = OpenC3::TargetModel.names(scope: scope)
        targets.each do |target_name|
          next if target_name == 'UNKNOWN' and parsed.stream_mode != :RAW

          begin
            packets = OpenC3::TargetModel.packets(target_name, type: type, scope: scope)
          rescue RuntimeError
            next
          end
          packets.each do |packet|
            pkt_key = "#{parsed.stream_mode}__#{parsed.cmd_or_tlm}__#{target_name}__#{packet['packet_name']}"
            pkt_key += "__#{value_type}" if value_type
            expanded << pkt_key
          end
        end
      elsif parsed.packet_name == 'COSMOS_ALL'
        # MODE__CMDORTLM__TARGET__COSMOS_ALL[__VALUETYPE]
        value_type = (parsed.stream_mode != :RAW) ? parsed.value_type : nil
        type = (parsed.cmd_or_tlm == :CMD) ? :CMD : :TLM
        begin
          packets = OpenC3::TargetModel.packets(parsed.target_name, type: type, scope: scope)
        rescue RuntimeError
          next
        end
        packets.each do |packet|
          pkt_key = "#{parsed.stream_mode}__#{parsed.cmd_or_tlm}__#{parsed.target_name}__#{packet['packet_name']}"
          pkt_key += "__#{value_type}" if value_type
          expanded << pkt_key
        end
      else
        expanded << key
      end
    end
    data["packets"] = expanded
  end

  # Expand glob patterns (*, ?, []) in item keys into concrete item entries.
  # Mutates data["items"] in-place, replacing glob entries with expanded pairs.
  def expand_item_globs(data, scope:)
    return unless data["items"]

    expanded = []
    data["items"].each do |entry|
      key = entry.is_a?(Array) ? entry[0] : entry
      parsed = StreamingKey.parse(key, item_key: true)

      unless parsed.has_glob?
        expanded << entry
        next
      end

      type = (parsed.cmd_or_tlm == :CMD) ? :CMD : :TLM

      if parsed.packet_name == 'LATEST'
        # LATEST + item glob: resolve item names from the item-to-packet map
        item_map = OpenC3::TargetModel.get_item_to_packet_map(parsed.target_name, scope: scope)
        item_map.each_key do |item_name|
          next unless File.fnmatch(parsed.item_name.to_s, item_name, File::FNM_CASEFOLD)
          concrete_key = parsed.with(item_name: item_name).to_key_string
          expanded << [concrete_key, concrete_key]
        end
      else
        # Determine which packets to iterate over
        if parsed.packet_name.match?(/[*?\[]/)
          # Packet name is a glob — match against all packets
          begin
            packets = OpenC3::TargetModel.packets(parsed.target_name, type: type, scope: scope)
          rescue RuntimeError
            next
          end
          matched_packets = packets.select { |pkt| File.fnmatch(parsed.packet_name.to_s, pkt['packet_name'], File::FNM_CASEFOLD) }
        else
          # Concrete packet name — just wrap it so the loop below works uniformly
          matched_packets = [{ 'packet_name' => parsed.packet_name.to_s }]
        end

        packet_glob = parsed.packet_name.match?(/[*?\[]/)
        item_glob = parsed.item_name && parsed.item_name.to_s.match?(/[*?\[]/)

        matched_packets.each do |pkt|
          pkt_name = pkt['packet_name']

          if item_glob || (packet_glob && parsed.item_name)
            # Fetch packet items and filter by item name (glob or exact match)
            begin
              packet_def = OpenC3::TargetModel.packet(parsed.target_name, pkt_name, type: type, scope: scope)
            rescue RuntimeError
              next
            end
            item_pattern = parsed.item_name.to_s
            packet_def['items'].each do |item|
              next unless File.fnmatch(item_pattern, item['name'], File::FNM_CASEFOLD)
              concrete_key = parsed.with(packet_name: pkt_name, item_name: item['name']).to_key_string
              expanded << [concrete_key, concrete_key]
            end
          else
            # Packet glob only, no item name
            concrete_key = parsed.with(packet_name: pkt_name).to_key_string
            expanded << [concrete_key, concrete_key]
          end
        end
      end
    end
    data["items"] = expanded
  end

  # Request to add data to the stream
  #
  # data format:
  # scope: scope name
  # token: authorization token
  # start_time: 64-bit nanoseconds from unix epoch - If not present then realtime
  # end_time: 64-bit nanoseconds from unix epoch - If not present stream forever
  # items: [ [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE, item_key] ]
  #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
  #   CMDORTLM - CMD or TLM
  #   TARGET - Target name
  #   PACKET - Packet name
  #   ITEM - Item Name
  #   VALUETYPE - RAW, CONVERTED, FORMATTED
  #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
  # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
  #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
  #   CMDORTLM - CMD or TLM
  #   TARGET - Target name
  #   PACKET - Packet name
  #   VALUETYPE - RAW, CONVERTED, FORMATTED, or PURE (pure means all types as stored in log)
  #   Use ALL in place of TARGET or PACKET to subscribe to all targets/packets
  #
  def add(data)
    # OpenC3::Logger.debug "start:#{Time.at(data["start_time"].to_i/1_000_000_000.0).formatted}" if data["start_time"]
    # OpenC3::Logger.debug "end:#{Time.at(data["end_time"].to_i/1_000_000_000.0).formatted}" if data["end_time"]
    @mutex.synchronize do
      # Preprocess request fields
      start_time = nil
      start_time = data["start_time"].to_i if data["start_time"]
      end_time = nil
      end_time = data["end_time"].to_i if data["end_time"]
      scope = data["scope"]
      token = data["token"]

      # Expand ALL wildcards in packets before building the collection
      expand_all_packets(data, scope: scope)
      # Expand glob patterns in item keys before building the collection
      expand_item_globs(data, scope: scope)

      # Build the collection of streaming objects for this request
      collection = StreamingObjectCollection.new
      if data["items"]
        build_item_collection(collection, data, start_time: start_time, end_time: end_time, scope: scope, token: token)
      end
      if data["packets"]
        data["packets"].each do |key|
          begin
            collection.add(StreamingObject.new(key, start_time, end_time, scope: scope, token: token))
          rescue OpenC3::AuthError, OpenC3::ForbiddenError
            OpenC3::Logger.info("Skipping unauthorized packet: #{key}")
          end
        end
      end

      if start_time
        # Create a thread that will first try to stream from log files for each topic (packet)
        thread = LoggedStreamingThread.new(self, collection, scope: scope, token: token)
        thread.start
        @logged_threads << thread
      elsif end_time.nil? or end_time > Time.now.to_nsec_from_epoch
        # Create a single realtime streaming thread to use the entire collection
        if @realtime_thread.nil? or not @realtime_thread.alive?
          OpenC3::Logger.info("Creating new realtime thread")
          @realtime_thread = RealtimeStreamingThread.new(self, collection)
          @realtime_thread.start
        else
          OpenC3::Logger.info("Adding to existing realtime thread")
          @realtime_thread.add(collection)
        end
      end
    end
    OpenC3::Logger.info("Added to stream: #{data.except("token")}")
  end

  # Request to remove data from the stream
  #
  # data format:
  # scope: scope name
  # token: authorization token
  # items: [ MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE__REDUCEDTYPE ]
  #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
  #   CMDORTLM - CMD or TLM
  #   TARGET - Target name
  #   PACKET - Packet name
  #   ITEM - Item Name
  #   VALUETYPE - RAW, CONVERTED, FORMATTED
  #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
  # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
  #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
  #   CMDORTLM - CMD or TLM
  #   TARGET - Target name
  #   PACKET - Packet name
  #   VALUETYPE - RAW, CONVERTED, FORMATTED, or PURE (pure means all types as stored in log)
  #
  def remove(data)
    scope = data["scope"]
    token = data["token"]

    # Expand ALL wildcards in packets before building the collection
    expand_all_packets(data, scope: scope)
    # Expand glob patterns in item keys before building the collection
    expand_item_globs(data, scope: scope)

    # Build the collection of streaming objects for this request
    collection = StreamingObjectCollection.new
    if data["items"]
      build_item_collection(collection, data, scope: scope, token: token)
    end
    if data["packets"]
      data["packets"].each do |key|
        begin
          collection.add(StreamingObject.new(key, nil, nil, scope: scope, token: token))
        rescue OpenC3::AuthError, OpenC3::ForbiddenError
          OpenC3::Logger.info("Skipping unauthorized packet: #{key}")
        end
      end
    end

    @mutex.synchronize do
      @realtime_thread.remove(collection) if @realtime_thread
      @logged_threads.each do |thread|
        thread.remove(collection)
      end
    end
    OpenC3::Logger.info("Removed from stream: #{data.except("token")}")
  end

  # Stream closed
  # Need to shutdown all threads
  def kill
    threads = []
    @mutex.synchronize do
      if @realtime_thread
        @realtime_thread.stop
        threads << @realtime_thread
      end
      @logged_threads.each do |thread|
        thread.stop
        threads << thread
      end
      @realtime_thread = nil
      @logged_threads = []
    end
    # Allow the threads a chance to stop before returning (1.1s total)
    i = 0
    threads.each do |thread|
      while thread.alive? or i < 110 do
        sleep 0.01
        i += 1
      end
    end
  end

  def complete_thread(thread)
    @mutex.synchronize do
      if thread == @realtime_thread
        @realtime_thread = nil
      end
      @logged_threads.delete(thread)
      if @logged_threads.length == 0 and not @realtime_thread
        OpenC3::Logger.info "Sending stream complete marker"
        transmit_results([], force: true)
      end
    end
  end

  def transmit_results(results, force: false)
    if results.length > 0 or force
      ActionCable.server.broadcast(@subscription_key, results.as_json())
    end
  end

  # Returns if the calling thread should be canceled or not
  def handoff_to_realtime(collection)
    @mutex.synchronize do
      if @realtime_thread and @realtime_thread.alive?
        @realtime_thread.handoff(collection)
        if collection.empty?
          return true
        else
          return false
        end
      else
        @realtime_thread = RealtimeStreamingThread.new(self, collection)
        @realtime_thread.start
        return true
      end
    end
  end
end
