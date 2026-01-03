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
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'pg'
require_relative 'streaming_thread'
require_relative 'streaming_object_file_reader'
OpenC3.require_file 'openc3/api/api'
OpenC3.require_file 'openc3/utilities/bucket_file_cache'

module OpenC3
  class LocalApi
    include Api
  end
end

class LoggedStreamingThread < StreamingThread
  ALLOWABLE_START_TIME_OFFSET_NSEC = 60 * Time::NSEC_PER_SECOND

  def initialize(streaming_api, collection, max_batch_size = 3600, scope:, token:)
    super(streaming_api, collection, max_batch_size)
    @thread_mode = :SETUP
    @scope = scope
    @token = token
    @@conn_mutex = Mutex.new
    @local_api = OpenC3::LocalApi.new
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

    unless item_objects_by_topic.empty?
      done = stream_items(item_objects_by_topic, topics, offsets)
    end
    unless packet_objects_by_topic.empty?
      done = stream_packets(packet_objects_by_topic, topics, offsets)
    end

    if done # We reached the end time
      OpenC3::Logger.info "Finishing LoggedStreamingThread for #{@collection.length} objects - Reached End Time"
      finish(@collection.objects)
      return
    end

    # Switch to Redis
    @thread_mode = :STREAM
  end

  def stream_items(objects_by_topic, topics, offsets)
    tables = {}
    names = []
    item_keys = []
    items = []

    start_time = nil
    end_time = nil

    objects_by_topic.each do |topic, objects|
      break if @cancel_thread
      objects.each do |object|
        _type, _cmd_tlm, tgt, pkt, item, value_type = object.key.split('__')
        items << "#{tgt}__#{pkt}__#{item}__#{value_type}"
      end
    end

    # Figure out what is actually available
    available = @local_api.get_tlm_available(items, scope: @scope, token: @token)

    item_index = 0
    objects_by_topic.each do |topic, objects|
      break if @cancel_thread

      objects.each do |object|
        break if @cancel_thread
        # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
        # Must match pattern in tsdb_microservice.py create_table() and read_topics()
        table_name = "#{object.target_name}__#{object.packet_name}".gsub(/[?,'"\\\/:\)\(\+\*\%~]/, '_')
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

        table_index = tables.find_index {|k,v| k == table_name }
        item_keys << object.item_key
        item = available[item_index]
        tgt, pkt, item_name, value_type = item.split('__')
        # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
        # Must match pattern in tsdb_microservice.py read_topics()
        item_name = item_name.gsub(/[?\.,'"\\\/:\)\(\+\-\*\%~;]/, '_')
        case value_type
        when 'WITH_UNITS'
          names << "\"T#{table_index}.#{item_name}__U\""
        when 'FORMATTED'
          names << "\"T#{table_index}.#{item_name}__F\""
        when 'CONVERTED'
          names << "\"T#{table_index}.#{item_name}__C\""
        else
          names << "\"T#{table_index}.#{item_name}\""
        end
        item_index += 1
      end
    end
    names << "T0.timestamp"

    # Build the SQL query
    query = "SELECT #{names.join(", ")} FROM "
    tables.each_with_index do |(table_name, _), index|
      if index == 0
        query += "#{table_name} as T#{index} "
      else
        query += "ASOF JOIN #{table_name} as T#{index} "
      end
    end
    query += "WHERE T0.timestamp >= #{(start_time / 1000.0).to_i}"
    if end_time
      query += " AND T0.timestamp < #{(end_time / 1000.0).to_i}"
    end

    done = false
    min = 0
    max = @max_batch_size
    retry_count = 0
    while !done and !@cancel_thread
      begin
        @@conn_mutex.synchronize do
          @@conn ||= PG::Connection.new(host: ENV['OPENC3_TSDB_HOSTNAME'],
                                        port: ENV['OPENC3_TSDB_QUERY_PORT'],
                                        user: ENV['OPENC3_TSDB_USERNAME'],
                                        password: ENV['OPENC3_TSDB_PASSWORD'],
                                        dbname: 'qdb')
          # Default connection is all strings but we want to map to the correct types
          if @@conn.type_map_for_results.is_a? PG::TypeMapAllStrings
            # Note: QuestDB uses signed int64 (long), so extreme values are clamped during storage:
            # - MIN_INT64 (-2^63) is treated as NULL by QuestDB, clamped to -(2^63)+1
            # - MAX_UINT64 (2^64-1) exceeds int64 max, clamped to 2^63-1
            # Test with DEMO items P_2.2,2 (MIN_INT64) and P(:6;) (MAX_UINT64)
            @@conn.type_map_for_results = PG::BasicTypeMapForResults.new @@conn
          end
          # QuestDB only uses the LIMIT keyword as a range
          # See https://questdb.com/docs/reference/sql/limit/
          query_offset = "#{query} LIMIT #{min}, #{max}"
          puts "QuestDB query:#{query_offset}"
          OpenC3::Logger.debug("QuestDB query: #{query_offset}")
          results = []
          result = @@conn.exec(query_offset)
          min += @max_batch_size
          max += @max_batch_size
          if result.nil? or result.ntuples == 0
            done = true
          else
            result.each do |tuples|
              entry = { "__type" => "items" }
              tuples.each_with_index do |tuple, index|
                if tuple[0] == 'timestamp'
                  # tuple[1] is a Ruby time object which we convert to nanoseconds
                  entry['__time'] = (tuple[1].to_f * 1_000_000_000).to_i
                else
                  entry[item_keys[index]] = tuple[1]
                end
              end
              results << entry
            end
            @streaming_api.transmit_results(results)
          end
        end
      rescue IOError, PG::Error => e
        # Retry the query because various errors can occur that are recoverable
        retry_count += 1
        if retry_count > 4
          # After the 5th retry just raise the error
          raise "Error querying QuestDB: #{e.message}"
        end
        OpenC3::Logger.warn("QuestDB: Retrying due to error: #{e.message}")
        OpenC3::Logger.warn("QuestDB: Last query: #{query}") # Log the last query for debugging
        @@conn_mutex.synchronize do
          if @@conn and !@@conn.finished?
            @@conn.finish()
          end
          @@conn = nil # Force the new connection
        end
        sleep 0.1
        retry
      end
    end
    if end_time
      return true
    else
      return false
    end
  end

  def stream_packets(objects_by_topic, topics, offsets)
    results = []

    # This will read out packets until nothing is left
    file_reader = StreamingObjectFileReader.new(@collection, scope: @scope)
    done = file_reader.each do |packet, topic|
      break if @cancel_thread

      # Get the packet objects that need this topic
      objects = objects_by_topic[topic]

      if objects
        objects.each do |object|
          break if @cancel_thread
          result_entry = handle_packet(packet, [object])
          results << result_entry if result_entry
          # Transmit if we have a full batch or more
          if results.length >= @max_batch_size
            @streaming_api.transmit_results(results)
            results.clear
          end
        end
      end

      break if @cancel_thread
    end
    return false if @cancel_thread

    # Transmit less than a batch if we have that
    @streaming_api.transmit_results(results)
    results.clear

    return done
  end

  def handle_packet(packet, objects)
    first_object = objects[0]
    if first_object.stream_mode == :RAW
      return handle_raw_packet(packet.buffer(false), objects, packet.packet_time.to_nsec_from_epoch)
    else # @stream_mode == :DECOM or :REDUCED_X
      return handle_json_packet(packet, objects)
    end
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
