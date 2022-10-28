# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved

require 'openc3'
OpenC3.require_file 'openc3/utilities/authorization'
require_relative 'logged_streaming_thread'
require_relative 'realtime_streaming_thread'
require_relative 'streaming_object'
require_relative 'streaming_object_collection'

class StreamingApi
  include OpenC3::Authorization

  def initialize(uuid, channel, scope: nil, token: nil)
    authorize(permission: 'system', scope: scope, token: token)
    @uuid = uuid
    @channel = channel
    @mutex = Mutex.new
    @realtime_thread = nil
    @logged_threads = []
    # OpenC3::Logger.level = OpenC3::Logger::DEBUG
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
  #   VALUETYPE - RAW, CONVERTED, FORMATTED, or WITH_UNITS
  #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
  # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
  #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
  #   CMDORTLM - CMD or TLM
  #   TARGET - Target name
  #   PACKET - Packet name
  #   VALUETYPE - RAW, CONVERTED, FORMATTED, WITH_UNITS, or PURE (pure means all types as stored in log)
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

      # Build the collection of streaming objects for this request
      collection = StreamingObjectCollection.new
      if data["items"]
        data["items"].each do |key, item_key|
          collection.add(StreamingObject.new(key, start_time, end_time, item_key: item_key, scope: scope, token: token))
        end
      end
      if data["packets"]
        data["packets"].each do |key|
          collection.add(StreamingObject.new(key, start_time, end_time, scope: scope, token: token))
        end
      end

      if start_time
        # Create a thread that will first try to stream from log files for each topic (packet)
        thread = LoggedStreamingThread.new(self, collection, scope: scope)
        thread.start
        @logged_threads << thread
      elsif end_time.nil? or end_time > Time.now.to_nsec_from_epoch
        # Create a single realtime streaming thread to use the entire collection
        if @realtime_thread.nil? or not @realtime_thread.alive?
          @realtime_thread = RealtimeStreamingThread.new(self, collection)
          @realtime_thread.start
        else
          @realtime_thread.add(collection)
        end
      end
    end
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
  #   VALUETYPE - RAW, CONVERTED, FORMATTED, or WITH_UNITS
  #   REDUCEDTYPE - MIN, MAX, AVG, STDDEV (only for reduced modes)
  # packets: [ MODE__CMDORTLM__TARGET__PACKET__VALUETYPE ]
  #   MODE - RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY
  #   CMDORTLM - CMD or TLM
  #   TARGET - Target name
  #   PACKET - Packet name
  #   VALUETYPE - RAW, CONVERTED, FORMATTED, WITH_UNITS, or PURE (pure means all types as stored in log)
  #
  def remove(data)
    scope = data["scope"]
    token = data["token"]

    # Build the collection of streaming objects for this request
    collection = StreamingObjectCollection.new
    if data["items"]
      data["items"].each do |key, item_key|
        collection.add(StreamingObject.new(key, start_time, end_time, item_key: item_key, scope: scope, token: token))
      end
    end
    if data["packets"]
      data["packets"].each do |key|
        collection.add(StreamingObject.new(key, start_time, end_time, scope: scope, token: token))
      end
    end

    @mutex.synchronize do
      @realtime_thread.remove(collection) if @realtime_thread
      @logged_threads.each do |thread|
        thread.remove(collection)
      end
    end
  end

  # Stream closed
  # Need to shutdown all threads
  def kill
    @mutex.synchronize do
      threads = []
      if @realtime_thread
        @realtime_thread.stop
        threads << @realtime_thread
      end
      @logged_threads.each do |thread|
        thread.stop
        threads << thread
      end
      # Allow the threads a chance to stop (1.1s total)
      i = 0
      threads.each do |thread|
        while thread.alive? or i < 110 do
          sleep 0.01
          i += 1
        end
      end

      # Ok we tried, now initialize everything
      @realtime_thread = nil
      @logged_threads = []
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
        thread.transmit_results([], force: true)
      end
    end
  end

  def transmit_results(results, force: false)
    if results.length > 0 or force
      # Fortify: This send is intentionally bypassing access control to get to the
      # private transmit method
      @channel.send(:transmit, JSON.generate(results.as_json(:allow_nan => true)))
    end
  end
end
