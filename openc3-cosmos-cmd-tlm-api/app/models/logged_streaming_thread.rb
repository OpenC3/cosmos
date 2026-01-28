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
OpenC3.require_file 'openc3/utilities/questdb_client'

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
    @@conn = nil unless defined?(@@conn)
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
    # Cache packet definitions to avoid repeated lookups
    packet_cache = {}
    # Map column index to item type info for decoding
    item_types = []
    # Track calculated timestamp items: { item_key => { source:, format:, table_index: } }
    calculated_timestamp_items = {}
    # Track which source timestamp columns we need to add (column name => index in names array)
    timestamp_source_columns = {}
    # Stored timestamp items that need conversion from timestamp_ns to float seconds
    stored_timestamp_items = Set.new(['PACKET_TIMESECONDS', 'RECEIVED_TIMESECONDS'])
    # Track stored timestamp items: { item_key => { column:, table_index: } }
    stored_timestamp_item_keys = {}

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
        table_name = OpenC3::QuestDBClient.sanitize_table_name(object.target_name, object.packet_name)
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
        item = available[item_index]
        tgt, pkt, orig_item_name, value_type = item.split('__')

        # Check if this is a stored timestamp item (PACKET_TIMESECONDS or RECEIVED_TIMESECONDS)
        # These are stored as timestamp_ns columns and need conversion to float seconds on read
        if stored_timestamp_items.include?(orig_item_name)
          col_name = "T#{table_index}.#{orig_item_name}"
          names << "\"#{col_name}\""
          item_types << { 'data_type' => 'TIMESTAMP', 'array_size' => nil }
          stored_timestamp_item_keys[object.item_key] = { column: col_name, table_index: table_index }
          item_keys << object.item_key
          # Also store for calculated items (TIMEFORMATTED) that may need this
          timestamp_source_columns[col_name] ||= nil
          item_index += 1
          next
        end

        # Check if this is a calculated timestamp item (PACKET_TIMEFORMATTED or RECEIVED_TIMEFORMATTED)
        if OpenC3::QuestDBClient::TIMESTAMP_ITEMS.key?(orig_item_name)
          # Track this as a calculated item - store the item_key separately
          calc_info = OpenC3::QuestDBClient::TIMESTAMP_ITEMS[orig_item_name]
          calculated_timestamp_items[object.item_key] = {
            source: calc_info[:source],
            format: calc_info[:format],
            table_index: table_index
          }
          # Track that we need this source column
          source_col = "T#{table_index}.#{calc_info[:source]}"
          timestamp_source_columns[source_col] ||= nil  # Will be set to actual index later
          item_index += 1
          next
        end

        item_keys << object.item_key

        # Look up item type info from packet definition
        cache_key = [tgt, pkt]
        unless packet_cache.key?(cache_key)
          begin
            packet_cache[cache_key] = OpenC3::TargetModel.packet(tgt, pkt, scope: @scope)
          rescue RuntimeError
            packet_cache[cache_key] = nil
          end
        end

        packet_def = packet_cache[cache_key]
        item_def = nil
        if packet_def
          packet_def['items']&.each do |pkt_item|
            if pkt_item['name'] == orig_item_name
              item_def = pkt_item
              break
            end
          end
        end

        safe_item_name = OpenC3::QuestDBClient.sanitize_column_name(orig_item_name)
        case value_type
        when 'WITH_UNITS'
          names << "\"T#{table_index}.#{safe_item_name}__U\""
          item_types << { 'data_type' => 'STRING', 'array_size' => nil }
        when 'FORMATTED'
          names << "\"T#{table_index}.#{safe_item_name}__F\""
          item_types << { 'data_type' => 'STRING', 'array_size' => nil }
        when 'CONVERTED'
          names << "\"T#{table_index}.#{safe_item_name}__C\""
          if item_def
            rc = item_def['read_conversion']
            if rc && rc['converted_type']
              item_types << { 'data_type' => rc['converted_type'], 'array_size' => item_def['array_size'] }
            elsif item_def['states']
              item_types << { 'data_type' => 'STRING', 'array_size' => nil }
            else
              item_types << { 'data_type' => item_def['data_type'], 'array_size' => item_def['array_size'] }
            end
          else
            item_types << { 'data_type' => nil, 'array_size' => nil }
          end
        else
          names << "\"T#{table_index}.#{safe_item_name}\""
          if item_def
            item_types << { 'data_type' => item_def['data_type'], 'array_size' => item_def['array_size'] }
          else
            item_types << { 'data_type' => nil, 'array_size' => nil }
          end
        end
        item_index += 1
      end
    end
    names << "T0.PACKET_TIMESECONDS"

    # Add any additional timestamp source columns needed for calculated items (RECEIVED_TIMESECONDS if needed)
    timestamp_source_columns.each_key do |source_col|
      # T0.PACKET_TIMESECONDS is already added above, but RECEIVED_TIMESECONDS needs to be added explicitly
      if source_col.include?('RECEIVED_TIMESECONDS')
        timestamp_source_columns[source_col] = names.length
        names << source_col
      else
        # T0.PACKET_TIMESECONDS was already added
        timestamp_source_columns[source_col] = names.length - 1  # PACKET_TIMESECONDS is always the last item before this loop
      end
    end

    # Update calculated_timestamp_items with actual source column indices
    calculated_timestamp_items.each do |item_key, info|
      source_col = "T#{info[:table_index]}.#{info[:source]}"
      info[:source_column_index] = timestamp_source_columns[source_col]
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
    query += "WHERE T0.PACKET_TIMESECONDS >= #{start_time}"
    if end_time
      query += " AND T0.PACKET_TIMESECONDS < #{end_time}"
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
              timestamp_values = {}  # Store timestamp column values for calculation
              tuples.each_with_index do |tuple, index|
                col_name = tuple[0]
                if col_name == 'PACKET_TIMESECONDS' || col_name.end_with?('.PACKET_TIMESECONDS')
                  # tuple[1] is a Ruby time object which we convert to nanoseconds
                  entry['__time'] = (tuple[1].to_f * 1_000_000_000).to_i
                  timestamp_values['PACKET_TIMESECONDS'] = tuple[1]
                  # Also store with table prefix for calculated items
                  timestamp_values[col_name] = tuple[1] if col_name.include?('.')
                  # If this was explicitly requested as an item, add converted value to entry
                  if index < item_keys.length && stored_timestamp_item_keys.key?(item_keys[index])
                    ts_utc = OpenC3::QuestDBClient.pg_timestamp_to_utc(tuple[1])
                    entry[item_keys[index]] = OpenC3::QuestDBClient.format_timestamp(ts_utc, :seconds)
                  end
                elsif col_name == 'RECEIVED_TIMESECONDS' || col_name.end_with?('.RECEIVED_TIMESECONDS')
                  # Store for calculated items
                  timestamp_values['RECEIVED_TIMESECONDS'] = tuple[1]
                  timestamp_values[col_name] = tuple[1] if col_name.include?('.')
                  # If this was explicitly requested as an item, add converted value to entry
                  if index < item_keys.length && stored_timestamp_item_keys.key?(item_keys[index])
                    ts_utc = OpenC3::QuestDBClient.pg_timestamp_to_utc(tuple[1])
                    entry[item_keys[index]] = OpenC3::QuestDBClient.format_timestamp(ts_utc, :seconds)
                  end
                elsif index < item_keys.length
                  # Decode value using item type info
                  type_info = item_types[index] || {}
                  # Check if this is a stored timestamp item that needs conversion
                  if stored_timestamp_item_keys.key?(item_keys[index])
                    ts_utc = OpenC3::QuestDBClient.pg_timestamp_to_utc(tuple[1])
                    entry[item_keys[index]] = OpenC3::QuestDBClient.format_timestamp(ts_utc, :seconds)
                  else
                    entry[item_keys[index]] = OpenC3::QuestDBClient.decode_value(
                      tuple[1],
                      data_type: type_info['data_type'],
                      array_size: type_info['array_size']
                    )
                  end
                end
              end

              # Calculate timestamp items (TIMEFORMATTED)
              calculated_timestamp_items.each do |item_key, info|
                ts_value = timestamp_values[info[:source]]
                ts_utc = OpenC3::QuestDBClient.pg_timestamp_to_utc(ts_value)
                calculated_value = OpenC3::QuestDBClient.format_timestamp(ts_utc, info[:format])
                entry[item_key] = calculated_value if calculated_value
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
    # Separate RAW packets (stream from files) from DECOM packets (stream from TSDB)
    raw_objects_by_topic = {}
    decom_objects_by_topic = {}

    objects_by_topic.each do |topic, objects|
      objects.each do |object|
        if object.stream_mode == :RAW
          raw_objects_by_topic[topic] ||= []
          raw_objects_by_topic[topic] << object
        else
          decom_objects_by_topic[topic] ||= []
          decom_objects_by_topic[topic] << object
        end
      end
    end

    done = false

    # Stream RAW packets from files
    unless raw_objects_by_topic.empty?
      done = stream_raw_packets_from_files(raw_objects_by_topic)
    end

    # Stream DECOM packets from TSDB
    unless decom_objects_by_topic.empty?
      done = stream_decom_packets_from_tsdb(decom_objects_by_topic)
    end

    done
  end

  def stream_raw_packets_from_files(objects_by_topic)
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

    done
  end

  def stream_decom_packets_from_tsdb(objects_by_topic)
    start_time = nil
    end_time = nil
    packet_objects = []

    objects_by_topic.each do |topic, objects|
      break if @cancel_thread
      objects.each do |object|
        break if @cancel_thread

        packet_objects << object

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
      end
    end

    return end_time ? true : false if packet_objects.empty?

    # Group objects by table (target__packet) for efficient querying
    objects_by_table = {}
    packet_objects.each do |object|
      # Same sanitization as tsdb_microservice.py create_table()
      table_name = "#{object.target_name}__#{object.packet_name}".gsub(/[?,'"\\\/:\)\(\+\*\%~]/, '_')
      objects_by_table[table_name] ||= []
      objects_by_table[table_name] << object
    end

    done = false
    retry_count = 0

    objects_by_table.each do |table_name, objects|
      break if @cancel_thread

      first_object = objects[0]
      value_type = first_object.value_type

      # Look up packet definition for type info during decoding
      packet_def = nil
      begin
        packet_def = OpenC3::TargetModel.packet(first_object.target_name, first_object.packet_name, scope: @scope)
      rescue RuntimeError
        # Packet not found, will use heuristic decoding
      end

      # Build the SQL query - select all columns from the table
      query = "SELECT * FROM \"#{table_name}\""
      query += " WHERE PACKET_TIMESECONDS >= #{start_time}"
      if end_time
        query += " AND PACKET_TIMESECONDS < #{end_time}"
      end

      min = 0
      max = @max_batch_size
      table_done = false

      while !table_done and !@cancel_thread
        begin
          @@conn_mutex.synchronize do
            @@conn ||= PG::Connection.new(host: ENV['OPENC3_TSDB_HOSTNAME'],
                                          port: ENV['OPENC3_TSDB_QUERY_PORT'],
                                          user: ENV['OPENC3_TSDB_USERNAME'],
                                          password: ENV['OPENC3_TSDB_PASSWORD'],
                                          dbname: 'qdb')
            if @@conn.type_map_for_results.is_a? PG::TypeMapAllStrings
              @@conn.type_map_for_results = PG::BasicTypeMapForResults.new @@conn
            end

            query_offset = "#{query} LIMIT #{min}, #{max}"
            puts "QuestDB packet query: #{query_offset}"
            OpenC3::Logger.debug("QuestDB packet query: #{query_offset}")
            results = []
            result = @@conn.exec(query_offset)
            min += @max_batch_size
            max += @max_batch_size

            if result.nil? or result.ntuples == 0
              table_done = true
            else
              result.each do |tuples|
                objects.each do |object|
                  entry = build_packet_entry(tuples, object, value_type, packet_def)
                  results << entry if entry
                end
              end
              @streaming_api.transmit_results(results) unless results.empty?
              results.clear
            end
          end
        rescue IOError, PG::Error => e
          retry_count += 1
          if retry_count > 4
            raise "Error querying QuestDB for packets: #{e.message}"
          end
          OpenC3::Logger.warn("QuestDB: Retrying packet query due to error: #{e.message}")
          @@conn_mutex.synchronize do
            if @@conn and !@@conn.finished?
              @@conn.finish()
            end
            @@conn = nil
          end
          sleep 0.1
          retry
        end
      end

      done = true if end_time
    end

    done
  end

  def build_packet_entry(tuples, object, value_type, packet_def = nil)
    entry = {
      "__type" => "PACKET",
      "__packet" => object.key
    }

    # Build mapping from column name to item definition for type-aware decoding
    item_defs = {}
    if packet_def
      packet_def['items']&.each do |item|
        # Sanitize item name same way as TSDB storage
        safe_name = item['name'].gsub(/[?\.,'"\\\/:\)\(\+=\-\*\%~;!@#\$\^&]/, '_')
        item_defs[safe_name] = item
      end
    end

    # First pass: build a hash of all columns for lookup
    columns = {}
    tuples.each do |tuple|
      column_name = tuple[0]
      value = tuple[1]
      columns[column_name] = value
    end

    # Second pass: process columns based on value_type
    tuples.each do |tuple|
      column_name = tuple[0]
      raw_value = tuple[1]

      # Handle PACKET_TIMESECONDS specially - this is the designated timestamp column
      if column_name == 'PACKET_TIMESECONDS'
        # Convert Ruby time to nanoseconds
        entry['__time'] = (raw_value.to_f * 1_000_000_000).to_i
        next
      end

      # Skip metadata columns
      next if column_name == 'tag'

      # Determine the base item name (remove __C, __F, __U suffixes)
      base_name = column_name.sub(/(__C|__F|__U)$/, '')
      item_def = item_defs[base_name]

      # Determine data_type and array_size based on column suffix and item definition
      if column_name.end_with?('__F', '__U')
        # Formatted values are always strings
        data_type = 'STRING'
        array_size = nil
      elsif column_name.end_with?('__C') && item_def
        # Converted values - check read_conversion
        rc = item_def['read_conversion']
        if rc && rc['converted_type']
          data_type = rc['converted_type']
          array_size = item_def['array_size']
        elsif item_def['states']
          data_type = 'STRING'
          array_size = nil
        else
          data_type = item_def['data_type']
          array_size = item_def['array_size']
        end
      elsif item_def
        data_type = item_def['data_type']
        array_size = item_def['array_size']
      else
        data_type = nil
        array_size = nil
      end

      # Decode value using type info
      value = OpenC3::QuestDBClient.decode_value(raw_value, data_type: data_type, array_size: array_size)

      # Map column names based on value_type
      # TSDB columns: item (RAW), item__C (CONVERTED), item__F (FORMATTED)
      case value_type
      when :RAW
        # Only include base columns (no suffix)
        next if column_name.end_with?('__C', '__F', '__U')
        entry[column_name] = value
      when :CONVERTED
        # Prefer __C columns, fall back to base
        if column_name.end_with?('__C')
          base_name = column_name.sub(/__C$/, '')
          entry[base_name] = value
        elsif !column_name.end_with?('__F', '__U') && !columns.key?("#{column_name}__C")
          entry[column_name] = value
        end
      when :FORMATTED, :WITH_UNITS
        # Prefer __F columns, fall back to __C, then base
        if column_name.end_with?('__F')
          base_name = column_name.sub(/__F$/, '')
          entry[base_name] = value
        elsif column_name.end_with?('__C') && !columns.key?("#{column_name.sub(/__C$/, '')}__F")
          base_name = column_name.sub(/__C$/, '')
          entry[base_name] = value
        elsif !column_name.end_with?('__C', '__F', '__U') && !columns.key?("#{column_name}__F") && !columns.key?("#{column_name}__C")
          entry[column_name] = value
        end
      end
    end

    entry
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
