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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'pg'
require_relative 'streaming_thread'
require_relative 'streaming_object_file_reader'

class LoggedStreamingThread < StreamingThread
  ALLOWABLE_START_TIME_OFFSET_NSEC = 60 * Time::NSEC_PER_SECOND

  def initialize(streaming_api, collection, max_batch_size = 100, scope:)
    super(streaming_api, collection, max_batch_size)
    @thread_mode = :SETUP
    @scope = scope
  end

  def thread_body
    objects = @collection.objects
    # Cancel if we don't have any objects ... this can happen as things are processed
    # or if someone calls remove() from the StreamingApi
    @cancel_thread = true unless objects and objects.length > 0
    return if @cancel_thread

    if @thread_mode == :SETUP
      setup_thread_body(objects)
    elsif @thread_mode == :STREAM
      redis_thread_body()
      @cancel_thread = attempt_handoff_to_realtime()
    else # @thread_mode == :TSDB
      tsdb_thread_body(objects)
    end
  end

  def setup_thread_body(objects)
    first_object = objects[0]

    # The goal of this mode is to determine if we are starting with files or from
    # realtime

    # start_time can be at most 1 minute in the future to prevent
    # spinning up threads that just block forever
    if (first_object.start_time - ALLOWABLE_START_TIME_OFFSET_NSEC) > Time.now.to_nsec_from_epoch
      OpenC3::Logger.info "Finishing stream start_time too far in future"
      finish(objects)
      @cancel_thread = true
      return
    end

    # Check the topic to figure out what we have in Redis
    oldest_msg_id, oldest_msg_hash = OpenC3::Topic.get_oldest_message(first_object.topic)

    if oldest_msg_id
      # We have data in Redis
      # Determine oldest timestamp in stream to determine if we need to go to file
      oldest_time = oldest_msg_hash['time'].to_i

      # OpenC3::Logger.debug "first start time:#{first_object.start_time} oldest:#{oldest_time}"
      if first_object.start_time < oldest_time
        # Stream from database
        @thread_mode = :TSDB
      else
        if first_object.end_time and first_object.end_time < oldest_time
          # Bad times - just end
          OpenC3::Logger.info "Finishing stream - start_time after end_time"
          finish(objects)
          @cancel_thread = true
          return
        else
          # Stream from Redis
          # Guesstimate start offset in stream based on first packet time and redis time
          redis_time = oldest_msg_id.split('-')[0].to_i * 1_000_000
          delta = redis_time - oldest_time
          # Start streaming from calculated redis time
          offset = ((first_object.start_time + delta) / 1_000_000).to_s + '-0'
          # OpenC3::Logger.debug "stream from Redis offset:#{offset} redis_time:#{redis_time} delta:#{delta}"
          objects.each {|object| object.offset = offset}
          @thread_mode = :STREAM
        end
      end
    else
      # Might still have data in the database
      @thread_mode = :TSDB
    end
  end

  def tsdb_thread_body(objects)
    topics, offsets, item_objects_by_topic, packet_objects_by_topic = @collection.topics_offsets_and_objects
    done = false
    results = []

    unless item_objects_by_topic.empty?
      done = stream_items(item_objects_by_topic, results, topics, offsets)
    end
    unless packet_objects_by_topic.empty?
      done = stream_packets(packet_objects_by_topic, results, topics, offsets)
    end

    # Transmit less than a batch if we have that
    @streaming_api.transmit_results(results)
    results.clear

    if done # We reached the end time
      OpenC3::Logger.info "Finishing LoggedStreamingThread for #{@collection.length} objects - Reached End Time"
      finish(@collection.objects)
      return
    end

    # Switch to Redis
    @thread_mode = :STREAM
  end

  def stream_items(objects_by_topic, results, topics, offsets)
    tables = {}
    names = []

    start_time = nil
    end_time = nil
    objects_by_topic.each do |topic, objects|
      break if @cancel_thread

      objects.each do |object|
        break if @cancel_thread
        # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
        table_name = "#{object.target_name}__#{object.packet_name}".gsub(/[?,'"\/:\)\(\+\*\%~]/, '_')
        tables[table_name] = 1

        if object.start_time
          if start_time.nil? or object.start_time < start_time
            start_time = object.start_time
          end
        end
        if object.end_time
          if end_time.nil? or object.end_time > end_time
            end_time = object.end_time
          end
        end

        if object.item_key.nil?
          names << "*"
        else
          index = tables.find_index {|k,v| k == table_name }
          type, cmd_tlm, tgt, pkt, item_name, value_type = object.item_key.split('__')
          # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
          # NOTE: Semicolon added as it appears invalid
          item_name = item_name.gsub(/[?\.,'"\\\/:\)\(\+\-\*\%~;]/, '_')
          case value_type
          when 'WITH_UNITS'
            names << "\"T#{index}.#{item_name}__U\""
          when 'FORMATTED'
            names << "\"T#{index}.#{item_name}__F\""
          when 'CONVERTED'
            names << "\"T#{index}.#{item_name}__C\""
          else
            names << "\"T#{index}.#{item_name}\""
          end
        end
      end
    end

    # Build the SQL query
    query = "SELECT #{names.join(", ")} FROM "
    tables.each_with_index do |(table_name, _), index|
      if index == 0
        query += "#{table_name} as T#{index} "
      else
        query += "ASOF JOIN #{table_name} as T#{index} "
      end
    end
    if start_time && !end_time
      query += "WHERE T0.timestamp < '#{start_time}' LIMIT -1"
    elsif start_time && end_time
      query += "WHERE T0.timestamp >= '#{start_time}' AND T0.timestamp < '#{end_time}'"
    end

    # retry_count = 0
    # begin
    #   @@conn_mutex.synchronize do
    #     @@conn ||= PG::Connection.new(host: ENV['OPENC3_TSDB_HOSTNAME'],
    #                                   port: ENV['OPENC3_TSDB_QUERY_PORT'],
    #                                   user: ENV['OPENC3_TSDB_USERNAME'],
    #                                   password: ENV['OPENC3_TSDB_PASSWORD'],
    #                                   dbname: 'qdb')
    #     # Default connection is all strings but we want to map to the correct types
    #     if @@conn.type_map_for_results.is_a? PG::TypeMapAllStrings
    #       # TODO: This doesn't seem to be round tripping UINT64 correctly
    #       # Try playback with P_2.2,2 and P(:6;): from the DEMO
    #       @@conn.type_map_for_results = PG::BasicTypeMapForResults.new @@conn
    #     end

    #     result = @@conn.exec(query)
    #     if result.nil? or result.ntuples == 0
    #       return {}
    #     else
    #       data = []
    #       # Build up a results set that is an array of arrays
    #       # Each nested array is a set of 2 items: [value, limits state]
    #       # If the item does not have limits the limits state is nil
    #       result.each_with_index do |tuples, index|
    #         data[index] ||= []
    #         row_index = 0
    #         tuples.each do |tuple|
    #           if tuple[0].include?("__L")
    #             data[index][row_index - 1][1] = tuple[1]
    #           elsif tuple[0] =~ /^__nil/
    #             data[index][row_index] = [nil, nil]
    #             row_index += 1
    #           else
    #             data[index][row_index] = [tuple[1], nil]
    #             row_index += 1
    #           end
    #         end
    #       end
    #       # If we only have one row then we return a single array
    #       if result.ntuples == 1
    #         data = data[0]
    #       end
    #       # return data
    #       topic = "#{scope}__#{type}__{#{target_name}}__#{packet.packet_name}"
    #       return packet, topic
    #     end
    #   end
    # rescue IOError, PG::Error => e
    #   # Retry the query because various errors can occur that are recoverable
    #   retry_count += 1
    #   if retry_count > 4
    #     # After the 5th retry just raise the error
    #     raise "Error querying QuestDB: #{e.message}"
    #   end
    #   Logger.warn("QuestDB: Retrying due to error: #{e.message}")
    #   Logger.warn("QuestDB: Last query: #{query}") # Log the last query for debugging
    #   @@conn_mutex.synchronize do
    #     if @@conn and !@@conn.finished?
    #       @@conn.finish()
    #     end
    #     @@conn = nil # Force the new connection
    #   end
    #   sleep 0.1
    #   retry
    # end

    # # This will read out packets until nothing is left
    # file_reader = StreamingObjectTsdbReader.new(@collection, scope: @scope)
    # done = file_reader.each do |packet, topic|
    #   break if @cancel_thread

    #   # Get the item objects that need this topic
    #   objects = item_objects_by_topic[topic]

    #   break if @cancel_thread
    #   if objects and objects.length > 0
    #     result_entry = handle_packet(packet, objects)
    #     results << result_entry if result_entry
    #   end
    #   break if @cancel_thread

    #   # Transmit if we have a full batch or more
    #   if results.length >= @max_batch_size
    #     @streaming_api.transmit_results(results)
    #     results.clear
    #   end

    #   # Get the packet objects that need this topic
    #   objects = packet_objects_by_topic[topic]

    #   if objects
    #     objects.each do |object|
    #       break if @cancel_thread
    #       result_entry = handle_packet(packet, [object])
    #       results << result_entry if result_entry
    #       # Transmit if we have a full batch or more
    #       if results.length >= @max_batch_size
    #         @streaming_api.transmit_results(results)
    #         results.clear
    #       end
    #     end
    #   end

    #   break if @cancel_thread
    # end
    # return if @cancel_thread
  end

  # Transfers item to realtime thread when complete (if continued)
  # Needs to mutex transfer
  #   checks if equal offset if packet already exists in realtime
  #   if doesn't exist adds with item offset
  #   if does exist and equal - transfer
  #   if does exist and less than - add item with less offset
  #   if does exist and greater than - catch up and try again
  def attempt_handoff_to_realtime
    if @collection.includes_realtime
      return @streaming_api.handoff_to_realtime(@collection)
    end
    return false
  end
end
