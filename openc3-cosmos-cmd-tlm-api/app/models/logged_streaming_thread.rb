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

class QuestDbError < StandardError; end

class LoggedStreamingThread < StreamingThread
  ALLOWABLE_START_TIME_OFFSET_NSEC = 60 * Time::NSEC_PER_SECOND

  def initialize(streaming_api, collection, max_batch_size = 600, scope:, token:)
    super(streaming_api, collection, max_batch_size)
    @thread_mode = :SETUP
    @scope = scope
    @token = token
    @@conn_mutex = Mutex.new
    @@conn = nil unless defined?(@@conn)
    @local_api = OpenC3::LocalApi.new
    @last_tsdb_times = {} # topic => last nanosecond timestamp read from TSDB
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
      # Separate reduced mode objects from regular objects
      reduced_objects_by_topic = {}
      regular_objects_by_topic = {}

      item_objects_by_topic.each do |topic, objs|
        objs.each do |obj|
          if [:REDUCED_MINUTE, :REDUCED_HOUR, :REDUCED_DAY].include?(obj.stream_mode)
            reduced_objects_by_topic[topic] ||= []
            reduced_objects_by_topic[topic] << obj
          else
            regular_objects_by_topic[topic] ||= []
            regular_objects_by_topic[topic] << obj
          end
        end
      end

      # Stream regular items
      unless regular_objects_by_topic.empty?
        done = stream_items(regular_objects_by_topic, topics, offsets)
      end

      # Stream reduced items using SAMPLE BY
      unless reduced_objects_by_topic.empty?
        done = stream_reduced_items(reduced_objects_by_topic)
      end
    end
    unless packet_objects_by_topic.empty?
      done = stream_packets(packet_objects_by_topic, topics, offsets)
    end

    if done # We reached the end time
      OpenC3::Logger.info "Finishing LoggedStreamingThread for #{@collection.length} objects - Reached End Time"
      finish(@collection.objects)
      return
    end

    # Bridge TSDB offsets to Valkey stream offsets before switching modes
    bridge_tsdb_to_stream()

    # Switch to Redis
    @thread_mode = :STREAM
  end

  # Overlap buffer when bridging from TSDB to Valkey stream.
  # The offset interpolation is approximate, so we start reading 2 seconds
  # earlier to guarantee overlap. The redis_thread_body filter deduplicates.
  TSDB_STREAM_OVERLAP_NSEC = 2 * 1_000_000_000

  # SQL: nanosecond-precision packet timestamp for explicit SELECT lists.
  # PG wire protocol truncates timestamp_ns to microseconds; CAST AS LONG preserves full precision.
  TIMESTAMP_SELECT = 'CAST(PACKET_TIMESECONDS AS LONG) as PACKET_TIMESECONDS'

  # SQL: nanosecond-precision timestamps for SELECT * queries (different aliases avoid column name collision).
  TIMESTAMP_EXTRAS = 'CAST(PACKET_TIMESECONDS AS LONG) as "__pkt_time_ns", CAST(RECEIVED_TIMESECONDS AS LONG) as "__rx_time_ns"'

  def bridge_tsdb_to_stream
    return if @last_tsdb_times.empty?

    # Calculate Valkey stream offset per topic
    offset_by_topic = {}
    @last_tsdb_times.each do |topic, last_time|
      oldest_msg_id, oldest_msg_hash = OpenC3::Topic.get_oldest_message(topic)
      if oldest_msg_id
        oldest_time = oldest_msg_hash['time'].to_i
        # Use the same interpolation formula as setup_thread_body
        redis_time = oldest_msg_id.split('-')[0].to_i * 1_000_000
        delta = redis_time - oldest_time
        # Subtract overlap buffer to ensure no gaps from interpolation imprecision
        offset_ms = (last_time - TSDB_STREAM_OVERLAP_NSEC + delta) / 1_000_000
        offset = (offset_ms > 0 ? offset_ms.to_s : '0') + '-0'
        offset_by_topic[topic] = offset
        OpenC3::Logger.info "TSDB->STREAM bridge: topic=#{topic} last_tsdb_time=#{last_time} offset=#{offset}"
      else
        OpenC3::Logger.info "TSDB->STREAM bridge: topic=#{topic} no Valkey messages, using 0-0"
      end
    end

    # Apply per-topic offsets to objects
    @collection.objects.each do |obj|
      offset = offset_by_topic[obj.topic]
      obj.offset = offset if offset
    end
  end

  def redis_thread_body
    if @last_tsdb_times.length > 0
      # Override parent to filter overlap during TSDB→STREAM transition
      topics, offsets, item_objects_by_topic, packet_objects_by_topic = @collection.topics_offsets_and_objects
      results = []
      if topics.length > 0
        xread_result = OpenC3::Topic.read_topics(topics, offsets, 500) do |topic, msg_id, msg_hash, _|
          stored = OpenC3::ConfigParser.handle_true_false(msg_hash["stored"])
          next if stored

          break if @cancel_thread

          # Check per-topic overlap filter
          last_time = @last_tsdb_times[topic]
          if last_time
            time = msg_hash['time'].to_i
            if time <= last_time
              # Skip messages already delivered from TSDB, but advance offsets
              objects = item_objects_by_topic[topic]
              objects.each { |object| object.offset = msg_id } if objects
              objects = packet_objects_by_topic[topic]
              objects.each { |object| object.offset = msg_id } if objects
              next
            end
            # Past the overlap for this topic - clear its filter
            @last_tsdb_times.delete(topic)
          end

          break if @cancel_thread

          objects = item_objects_by_topic[topic]
          break if @cancel_thread
          if objects and objects.length > 0
            objects.each do |object|
              object.offset = msg_id
            end
            result_entry = handle_message(msg_hash, objects)
            results << result_entry if result_entry
          end
          break if @cancel_thread

          if results.length >= @max_batch_size
            @streaming_api.transmit_results(results)
            results.clear
          end

          objects = packet_objects_by_topic[topic]
          if objects
            objects.each do |object|
              object.offset = msg_id
            end
            objects.each do |object|
              break if @cancel_thread
              result_entry = handle_message(msg_hash, [object])
              results << result_entry if result_entry
              if results.length >= @max_batch_size
                @streaming_api.transmit_results(results)
                results.clear
              end
            end
          end

          break if @cancel_thread
        end

        @streaming_api.transmit_results(results)
        results.clear

        check_for_completed_objects() if xread_result and xread_result.length == 0
      else
        @cancel_thread = true
      end
    else
      super
    end
  end

  def stream_items(objects_by_topic, topics, offsets)
    items = []
    # Cache packet definitions to avoid repeated lookups
    packet_cache = {}
    # Stored timestamp items that need conversion from timestamp_ns to float seconds
    stored_timestamp_items = Set.new(['PACKET_TIMESECONDS', 'RECEIVED_TIMESECONDS'])

    start_time, end_time = compute_time_range(objects_by_topic)

    item_cmd_or_tlm = [] # Track CMD/TLM per item for type-aware lookups
    objects_by_topic.each do |topic, objects|
      break if @cancel_thread
      objects.each do |object|
        _type, cmd_tlm, tgt, pkt, item, value_type = object.key.split('__')
        items << "#{tgt}__#{pkt}__#{item}__#{value_type}"
        item_cmd_or_tlm << cmd_tlm
      end
    end

    # Figure out what is actually available - handle CMD and TLM separately
    available = Array.new(items.length)

    # Resolve TLM items using get_tlm_available
    tlm_indices = items.each_index.select { |i| item_cmd_or_tlm[i] == 'TLM' }
    unless tlm_indices.empty?
      tlm_results = @local_api.get_tlm_available(tlm_indices.map { |i| items[i] }, scope: @scope, token: @token)
      tlm_indices.each_with_index do |orig_idx, result_idx|
        available[orig_idx] = tlm_results[result_idx]
      end
    end

    # Resolve CMD items manually (no get_cmd_available API exists)
    items.each_with_index do |item_str, idx|
      next unless item_cmd_or_tlm[idx] == 'CMD'
      target_name, packet_name, item_name, value_type = item_str.split('__')
      begin
        item_def = OpenC3::TargetModel.packet_item(target_name, packet_name, item_name, type: :CMD, scope: @scope)
        if item_def['array_size']
          value_type = 'RAW'
        end
        resolved = case value_type
          when 'FORMATTED', 'WITH_UNITS'
            if item_def['format_string']
              'FORMATTED'
            elsif item_def['states'] || (item_def['read_conversion'] && item_def['data_type'] != 'DERIVED')
              'CONVERTED'
            else
              'RAW'
            end
          when 'CONVERTED'
            if item_def['states'] || (item_def['read_conversion'] && item_def['data_type'] != 'DERIVED')
              'CONVERTED'
            else
              'RAW'
            end
          else
            'RAW'
          end
        available[idx] = [target_name, packet_name, item_name, resolved].join('__')
      rescue RuntimeError
        available[idx] = nil
      end
    end

    # Build per-table metadata: each table gets its own column names, item keys,
    # item types, and timestamp tracking. Tables are queried independently and
    # merged by timestamp using a k-way merge.
    per_table = {} # table_name => { cmd_or_tlm:, names:, item_keys:, ... }

    item_index = 0
    objects_by_topic.each do |topic, objects|
      break if @cancel_thread

      objects.each do |object|
        break if @cancel_thread
        table_name = OpenC3::QuestDBClient.sanitize_table_name(object.target_name, object.packet_name, object.cmd_or_tlm, scope: @scope)

        per_table[table_name] ||= {
          cmd_or_tlm: object.cmd_or_tlm,
          names: [],
          item_keys: [],
          item_types: [],
          stored_timestamp_item_keys: {},
          calculated_positions: {},  # local_index => { source:, format: }
          timestamp_source_columns: {},
          topics: Set.new
        }
        meta = per_table[table_name]
        meta[:topics] << topic

        item = available[item_index]
        tgt, pkt, orig_item_name, value_type = item.split('__')

        # Check if this is a stored timestamp item (PACKET_TIMESECONDS or RECEIVED_TIMESECONDS)
        # These are stored as timestamp_ns columns and need conversion to float seconds on read
        if stored_timestamp_items.include?(orig_item_name)
          meta[:names] << "\"#{orig_item_name}\""
          meta[:item_types] << { 'data_type' => 'TIMESTAMP', 'array_size' => nil }
          meta[:stored_timestamp_item_keys][object.item_key] = { column: orig_item_name }
          meta[:item_keys] << object.item_key
          meta[:timestamp_source_columns][orig_item_name] ||= nil
          item_index += 1
          next
        end

        # Check if this is a calculated timestamp item (PACKET_TIMEFORMATTED or RECEIVED_TIMEFORMATTED)
        # These get a positional slot (NULL in SQL) and are computed in-place during result processing
        if OpenC3::QuestDBClient::TIMESTAMP_ITEMS.key?(orig_item_name)
          calc_info = OpenC3::QuestDBClient::TIMESTAMP_ITEMS[orig_item_name]
          local_idx = meta[:names].length
          meta[:names] << nil  # placeholder - not a SQL column
          meta[:item_keys] << object.item_key
          meta[:item_types] << { 'data_type' => 'CALCULATED_TIMESTAMP', 'array_size' => nil }
          meta[:calculated_positions][local_idx] = { source: calc_info[:source], format: calc_info[:format] }
          meta[:timestamp_source_columns][calc_info[:source]] ||= nil
          item_index += 1
          next
        end

        meta[:item_keys] << object.item_key

        # Look up item type info from packet definition
        pkt_type = (item_cmd_or_tlm[item_index] == 'CMD') ? :CMD : :TLM
        cache_key = [tgt, pkt, pkt_type]
        unless packet_cache.key?(cache_key)
          begin
            packet_cache[cache_key] = OpenC3::TargetModel.packet(tgt, pkt, type: pkt_type, scope: @scope)
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
          meta[:names] << "\"#{safe_item_name}__U\""
          meta[:item_types] << { 'data_type' => 'STRING', 'array_size' => nil }
        when 'FORMATTED'
          meta[:names] << "\"#{safe_item_name}__F\""
          meta[:item_types] << { 'data_type' => 'STRING', 'array_size' => nil }
        when 'CONVERTED'
          meta[:names] << "\"#{safe_item_name}__C\""
          if item_def
            rc = item_def['read_conversion']
            if rc && rc['converted_type']
              meta[:item_types] << { 'data_type' => rc['converted_type'], 'array_size' => item_def['array_size'] }
            elsif item_def['states']
              meta[:item_types] << { 'data_type' => 'STRING', 'array_size' => nil }
            else
              meta[:item_types] << { 'data_type' => item_def['data_type'], 'array_size' => item_def['array_size'] }
            end
          else
            meta[:item_types] << { 'data_type' => nil, 'array_size' => nil }
          end
        else
          meta[:names] << "\"#{safe_item_name}\""
          if item_def
            meta[:item_types] << { 'data_type' => item_def['data_type'], 'array_size' => item_def['array_size'] }
          else
            meta[:item_types] << { 'data_type' => nil, 'array_size' => nil }
          end
        end
        item_index += 1
      end
    end

    # Filter to tables that exist and have data in the queried range
    if per_table.size > 1
      per_table.select! { |table_name, _| tsdb_table_has_data?(table_name, start_time, end_time) }
    end

    # Build per-table queries independently.
    # Each table gets its own simple SELECT with only its columns.
    # Results are merged by timestamp using a k-way merge.
    cursors = []

    per_table.each do |table_name, meta|
      needs_received_ts = meta[:timestamp_source_columns].any? { |k, _| k.include?('RECEIVED_TIMESECONDS') }

      query_names = meta[:names].compact.dup  # compact removes nil (calculated) placeholders
      query_names << "CAST(PACKET_TIMESECONDS AS LONG) as PACKET_TIMESECONDS"
      query_names << "RECEIVED_TIMESECONDS" if needs_received_ts
      query_names << "COSMOS_EXTRA"

      # Pre-compute mapping from SQL column index to local meta index.
      # Calculated positions (names[i] == nil) have no SQL column.
      sql_to_local = []
      meta[:names].each_with_index do |name, i|
        sql_to_local << i unless name.nil?
      end

      query = "SELECT #{query_names.join(', ')} FROM #{table_name}"
      query += tsdb_time_where(start_time, end_time)
      OpenC3::Logger.debug("QuestDB per-table query: #{query}")

      cursors << {
        query: query,
        meta: meta,
        sql_to_local: sql_to_local,
        result: nil,      # current PG::Result page
        row_index: 0,      # position within current page
        offset: 0,         # LIMIT offset for next fetch
        exhausted: false,
        table_name: table_name
      }
    end

    if cursors.empty?
      return past_end_time?(end_time) ? true : false
    end

    # Initialize: fetch first page for each cursor
    cursors.each { |c| tsdb_advance_cursor(c) }

    # K-way merge loop: always pick the cursor with the lowest PACKET_TIMESECONDS
    results = []
    loop do
      break if @cancel_thread

      # Find cursor with lowest timestamp (linear scan — table count is small)
      min_cursor = nil
      min_time = nil
      cursors.each do |c|
        next if c[:exhausted]
        row_time = tsdb_cursor_time(c)
        if row_time && (min_time.nil? || row_time < min_time)
          min_time = row_time
          min_cursor = c
        end
      end

      break unless min_cursor # All cursors exhausted

      # Process this row
      entry = process_tsdb_row(min_cursor)
      if entry
        objects_by_topic.each_key { |t| track_tsdb_time(t, entry['__time']) }
        results << entry
      end

      # Advance cursor
      min_cursor[:row_index] += 1
      if min_cursor[:result].nil? || min_cursor[:row_index] >= min_cursor[:result].ntuples
        tsdb_advance_cursor(min_cursor)
      end

      # Transmit batch when full
      if results.length >= @max_batch_size
        @streaming_api.transmit_results(results)
        results = []
      end
    end

    # Transmit remaining results
    @streaming_api.transmit_results(results) unless results.empty?
    past_end_time?(end_time) ? true : false
  end

  # Returns the PACKET_TIMESECONDS value for the current row of a cursor
  def tsdb_cursor_time(cursor)
    return nil if cursor[:exhausted] || cursor[:result].nil?
    row = cursor[:result][cursor[:row_index]]
    return nil unless row
    # Row may be a Hash (real PG::Result) or array of [col, val] pairs (mock).
    # Iterate to find PACKET_TIMESECONDS reliably in both cases.
    row.each do |tuple|
      return tuple[1].to_i if tuple[0] == 'PACKET_TIMESECONDS'
    end
    nil
  end

  # Fetches the next page for a cursor, or marks it as exhausted
  def tsdb_advance_cursor(cursor)
    return if cursor[:exhausted]
    retry_count = 0
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
        query_offset = "#{cursor[:query]} LIMIT #{cursor[:offset]}, #{cursor[:offset] + @max_batch_size}"
        OpenC3::Logger.debug("QuestDB cursor fetch: #{query_offset}")
        result = @@conn.exec(query_offset)
        cursor[:offset] += @max_batch_size
        if result.nil? || result.ntuples == 0
          cursor[:result] = nil
          cursor[:exhausted] = true
        else
          cursor[:result] = result
          cursor[:row_index] = 0
        end
      end
    rescue IOError, PG::Error => e
      retry_count += 1
      if retry_count > 4
        raise QuestDbError, "Error querying QuestDB (cursor fetch): #{e.message}"
      end
      OpenC3::Logger.warn("QuestDB cursor fetch: retry #{retry_count} - #{e.message}")
      @@conn_mutex.synchronize do
        if @@conn && !@@conn.finished?
          @@conn.finish()
        end
        @@conn = nil
      end
      sleep 0.1
      retry
    end
  end

  # Process one row from a single table's query result into an entry hash.
  # Row iteration uses [col_name, value] tuple pattern compatible with both
  # real PG::Result (Hash#each yields [key,val]) and test mocks (Array of pairs).
  def process_tsdb_row(cursor)
    result = cursor[:result]
    return nil unless result
    row_index = cursor[:row_index]
    return nil if row_index >= result.ntuples

    meta = cursor[:meta]
    sql_to_local = cursor[:sql_to_local]
    num_sql_item_cols = sql_to_local.length

    entry = { "__type" => "ITEMS" }
    timestamp_values = {}
    time_ns = nil
    cosmos_extra = nil

    # Values array indexed by local meta position
    values = Array.new(meta[:item_keys].length)

    # Iterate over the row's columns as [col_name, value] tuples
    row = result[row_index]
    row.each_with_index do |tuple, sql_index|
      col_name = tuple[0]
      value = tuple[1]

      # Fixed columns come after item columns
      if sql_index >= num_sql_item_cols
        case col_name
        when 'PACKET_TIMESECONDS'
          time_ns = value.to_i
          pkt_time = Time.at(time_ns / 1_000_000_000, time_ns % 1_000_000_000, :nsec, in: '+00:00')
          timestamp_values['PACKET_TIMESECONDS'] = pkt_time
        when 'RECEIVED_TIMESECONDS'
          timestamp_values['RECEIVED_TIMESECONDS'] = value if value
        when 'COSMOS_EXTRA'
          cosmos_extra = value
        else
          next # Redundant with outer next but satisfies static analysis
        end
        next # Fixed columns are fully handled above
      end

      # Map SQL column index to local meta index
      local_idx = sql_to_local[sql_index]

      # Track timestamp values from item columns
      if col_name == 'RECEIVED_TIMESECONDS'
        timestamp_values['RECEIVED_TIMESECONDS'] = value
      end

      next if value.nil?

      type_info = meta[:item_types][local_idx] || {}
      if meta[:stored_timestamp_item_keys].key?(meta[:item_keys][local_idx])
        ts_utc = tsdb_coerce_to_utc(value)
        values[local_idx] = OpenC3::QuestDBClient.format_timestamp(ts_utc, :seconds) if ts_utc
      else
        values[local_idx] = OpenC3::QuestDBClient.decode_value(
          value,
          data_type: type_info['data_type'],
          array_size: type_info['array_size']
        )
      end
    end

    # Build ordered entry hash with calculated items in their natural position
    meta[:item_keys].each_with_index do |item_key, local_idx|
      if meta[:calculated_positions].key?(local_idx)
        calc_info = meta[:calculated_positions][local_idx]
        ts_value = timestamp_values[calc_info[:source]]
        next unless ts_value
        ts_utc = tsdb_coerce_to_utc(ts_value)
        calculated_value = OpenC3::QuestDBClient.format_timestamp(ts_utc, calc_info[:format])
        entry[item_key] = calculated_value if calculated_value
      elsif !values[local_idx].nil?
        entry[item_key] = values[local_idx]
      end
    end

    entry['__time'] = time_ns if time_ns
    entry['COSMOS_EXTRA'] = cosmos_extra if cosmos_extra
    entry
  end

  # Stream reduced (aggregated) items using QuestDB SAMPLE BY
  # This generates min, max, avg, stddev aggregations on-the-fly
  def stream_reduced_items(objects_by_topic)
    # Group objects by table and stream_mode for efficient querying
    objects_by_table_and_mode = {}
    start_time, end_time = compute_time_range(objects_by_topic)

    objects_by_topic.each do |topic, objects|
      break if @cancel_thread
      objects.each do |object|
        break if @cancel_thread
        table_name = OpenC3::QuestDBClient.sanitize_table_name(object.target_name, object.packet_name, object.cmd_or_tlm, scope: @scope)
        key = [table_name, object.stream_mode]
        objects_by_table_and_mode[key] ||= []
        objects_by_table_and_mode[key] << object
      end
    end

    return end_time ? true : false if objects_by_table_and_mode.empty?

    done = false

    objects_by_table_and_mode.each do |(table_name, stream_mode), objects|
      break if @cancel_thread

      sample_interval = sample_interval_for(stream_mode)

      # Group objects by item to build efficient query
      # Each object has: target_name, packet_name, item_name, value_type, reduced_type
      items_to_query = {}
      objects.each do |object|
        item_key = object.item_name
        items_to_query[item_key] ||= { objects: [], value_types: Set.new }
        items_to_query[item_key][:objects] << object
        items_to_query[item_key][:value_types] << object.value_type
      end

      # Build the SELECT clause with aggregations
      selects = [TIMESTAMP_SELECT]
      column_mapping = {} # Maps result column name to [item_key, reduced_type, value_type]

      items_to_query.each do |item_name, info|
        safe_item_name = OpenC3::QuestDBClient.sanitize_column_name(item_name)

        info[:value_types].each do |value_type|
          case value_type
          when :RAW
            # RAW aggregations - use base column
            col = safe_item_name
            selects << "min(\"#{col}\") as \"#{safe_item_name}__N\""
            selects << "max(\"#{col}\") as \"#{safe_item_name}__X\""
            selects << "avg(\"#{col}\") as \"#{safe_item_name}__A\""
            selects << "stddev(\"#{col}\") as \"#{safe_item_name}__S\""
            column_mapping["#{safe_item_name}__N"] = [item_name, :MIN, :RAW]
            column_mapping["#{safe_item_name}__X"] = [item_name, :MAX, :RAW]
            column_mapping["#{safe_item_name}__A"] = [item_name, :AVG, :RAW]
            column_mapping["#{safe_item_name}__S"] = [item_name, :STDDEV, :RAW]
          when :CONVERTED
            # CONVERTED aggregations - use __C column
            col = "#{safe_item_name}__C"
            selects << "min(\"#{col}\") as \"#{safe_item_name}__CN\""
            selects << "max(\"#{col}\") as \"#{safe_item_name}__CX\""
            selects << "avg(\"#{col}\") as \"#{safe_item_name}__CA\""
            selects << "stddev(\"#{col}\") as \"#{safe_item_name}__CS\""
            column_mapping["#{safe_item_name}__CN"] = [item_name, :MIN, :CONVERTED]
            column_mapping["#{safe_item_name}__CX"] = [item_name, :MAX, :CONVERTED]
            column_mapping["#{safe_item_name}__CA"] = [item_name, :AVG, :CONVERTED]
            column_mapping["#{safe_item_name}__CS"] = [item_name, :STDDEV, :CONVERTED]
          else
            # Unsupported value_type for reduction
            next
          end
        end
      end

      # Build the full query with SAMPLE BY
      query = "SELECT #{selects.join(', ')} FROM \"#{table_name}\""
      query += tsdb_time_where(start_time, end_time)
      query += " SAMPLE BY #{sample_interval}"
      query += " ALIGN TO CALENDAR"
      query += " ORDER BY PACKET_TIMESECONDS"

      tsdb_query_each_page(query, label: "reduced query") do |result|
        results = []
        result.each do |tuples|
          entry = { "__type" => "ITEMS" }

          tuples.each do |tuple|
            col_name = tuple[0]
            value = tuple[1]

            if col_name == 'PACKET_TIMESECONDS'
              # Use nanosecond integer directly for full precision
              entry['__time'] = value.to_i
              next
            end

            # Map result column to the requesting object's item_key
            mapping = column_mapping[col_name]
            next unless mapping

            item_name, reduced_type, value_type = mapping

            # Find objects that want this specific combination
            objects.each do |object|
              if object.item_name == item_name &&
                 object.reduced_type == reduced_type &&
                 object.value_type == value_type
                # Decode the value (aggregations return floats)
                decoded_value = OpenC3::QuestDBClient.decode_value(value, data_type: 'DOUBLE', array_size: nil)
                entry[object.item_key] = decoded_value
              end
            end
          end

          if entry.keys.length > 2 # Has more than __type and __time
            objects.each { |obj| track_tsdb_time(obj.topic, entry['__time']) }
            results << entry
          end
        end
        @streaming_api.transmit_results(results) unless results.empty?
      end

      done = true if past_end_time?(end_time)
    end

    done
  end

  def stream_packets(objects_by_topic, topics, offsets)
    # Separate RAW packets (stream from files) from DECOM packets (stream from TSDB)
    # and reduced packets (aggregated from TSDB)
    raw_objects_by_topic = {}
    decom_objects_by_topic = {}
    reduced_objects_by_topic = {}

    objects_by_topic.each do |topic, objects|
      objects.each do |object|
        if object.stream_mode == :RAW
          raw_objects_by_topic[topic] ||= []
          raw_objects_by_topic[topic] << object
        elsif [:REDUCED_MINUTE, :REDUCED_HOUR, :REDUCED_DAY].include?(object.stream_mode)
          reduced_objects_by_topic[topic] ||= []
          reduced_objects_by_topic[topic] << object
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

    # Stream reduced packets from TSDB using SAMPLE BY
    unless reduced_objects_by_topic.empty?
      done = stream_reduced_packets_from_tsdb(reduced_objects_by_topic)
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
        # Track the latest timestamp per topic for TSDB→STREAM bridge
        track_tsdb_time(topic, packet.packet_time.to_nsec_from_epoch)

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
    start_time, end_time = compute_time_range(objects_by_topic)
    packet_objects = []

    objects_by_topic.each do |topic, objects|
      break if @cancel_thread
      objects.each do |object|
        break if @cancel_thread
        packet_objects << object
      end
    end

    return end_time ? true : false if packet_objects.empty?

    # Group objects by table (cmd_or_tlm__target__packet) for efficient querying
    objects_by_table = {}
    packet_objects.each do |object|
      # Same sanitization as tsdb_microservice.py create_table()
      table_name = OpenC3::QuestDBClient.sanitize_table_name(object.target_name, object.packet_name, object.cmd_or_tlm, scope: @scope)
      objects_by_table[table_name] ||= []
      objects_by_table[table_name] << object
    end

    done = false

    objects_by_table.each do |table_name, objects|
      break if @cancel_thread

      first_object = objects[0]
      value_type = first_object.value_type

      # Look up packet definition for type info during decoding
      packet_def = nil
      begin
        pkt_type = (first_object.cmd_or_tlm == :CMD) ? :CMD : :TLM
        packet_def = OpenC3::TargetModel.packet(first_object.target_name, first_object.packet_name, type: pkt_type, scope: @scope)
      rescue RuntimeError
        # Packet not found, will use heuristic decoding
      end

      # Build the SQL query - select all columns from the table
      # CAST timestamp_ns columns AS LONG to preserve nanosecond precision;
      # PG wire protocol truncates timestamp_ns to microsecond precision.
      query = "SELECT *, #{TIMESTAMP_EXTRAS} FROM \"#{table_name}\""
      query += tsdb_time_where(start_time, end_time)

      tsdb_query_each_page(query, label: "packet query") do |result|
        results = []
        result.each do |tuples|
          objects.each do |object|
            entry = build_packet_entry(tuples, object, value_type, packet_def)
            if entry
              track_tsdb_time(object.topic, entry['__time'])
              results << entry
            end
          end
        end
        @streaming_api.transmit_results(results) unless results.empty?
      end

      done = true if past_end_time?(end_time)
    end

    done
  end

  # Stream reduced (aggregated) packets using QuestDB SAMPLE BY
  # This generates min, max, avg, stddev aggregations for all numeric columns
  def stream_reduced_packets_from_tsdb(objects_by_topic)
    start_time, end_time = compute_time_range(objects_by_topic)
    packet_objects = []

    objects_by_topic.each do |topic, objects|
      break if @cancel_thread
      objects.each do |object|
        break if @cancel_thread
        packet_objects << object
      end
    end

    return end_time ? true : false if packet_objects.empty?

    # Group objects by table and stream_mode for efficient querying
    objects_by_table_and_mode = {}
    packet_objects.each do |object|
      table_name = OpenC3::QuestDBClient.sanitize_table_name(object.target_name, object.packet_name, object.cmd_or_tlm, scope: @scope)
      key = [table_name, object.stream_mode]
      objects_by_table_and_mode[key] ||= []
      objects_by_table_and_mode[key] << object
    end

    done = false

    objects_by_table_and_mode.each do |(table_name, stream_mode), objects|
      break if @cancel_thread

      first_object = objects[0]
      value_type = first_object.value_type
      sample_interval = sample_interval_for(stream_mode)

      # Look up packet definition to find numeric columns
      packet_def = nil
      begin
        pkt_type = (first_object.cmd_or_tlm == :CMD) ? :CMD : :TLM
        packet_def = OpenC3::TargetModel.packet(first_object.target_name, first_object.packet_name, type: pkt_type, scope: @scope)
      rescue RuntimeError
        # Packet not found
      end

      # Build aggregation query for all numeric items in the packet
      selects = [TIMESTAMP_SELECT]
      numeric_items = []

      if packet_def && packet_def['items']
        packet_def['items'].each do |item|
          # Skip non-numeric types and derived items
          data_type = item['data_type']
          next if data_type.nil?
          next if ['STRING', 'BLOCK', 'DERIVED'].include?(data_type)
          # Skip if it's a derived item (has read_conversion with no data_type or DERIVED type)
          next if item['data_type'] == 'DERIVED'

          item_name = item['name']
          safe_name = OpenC3::QuestDBClient.sanitize_column_name(item_name)
          numeric_items << { name: item_name, safe_name: safe_name }

          # Add aggregations based on value_type
          case value_type
          when :RAW
            selects << "min(\"#{safe_name}\") as \"#{safe_name}__N\""
            selects << "max(\"#{safe_name}\") as \"#{safe_name}__X\""
            selects << "avg(\"#{safe_name}\") as \"#{safe_name}__A\""
            selects << "stddev(\"#{safe_name}\") as \"#{safe_name}__S\""
          when :CONVERTED
            # Try converted column first, with fallback to raw
            selects << "min(\"#{safe_name}__C\") as \"#{safe_name}__CN\""
            selects << "max(\"#{safe_name}__C\") as \"#{safe_name}__CX\""
            selects << "avg(\"#{safe_name}__C\") as \"#{safe_name}__CA\""
            selects << "stddev(\"#{safe_name}__C\") as \"#{safe_name}__CS\""
          else
            # Unsupported value_type for reduction
            next
          end
        end
      end

      # If no numeric items found, skip this table
      if numeric_items.empty?
        OpenC3::Logger.warn("No numeric items found for reduced packet query on #{table_name}")
        next
      end

      # Build the full query with SAMPLE BY
      query = "SELECT #{selects.join(', ')} FROM \"#{table_name}\""
      query += tsdb_time_where(start_time, end_time)
      query += " SAMPLE BY #{sample_interval}"
      query += " ALIGN TO CALENDAR"
      query += " ORDER BY PACKET_TIMESECONDS"

      tsdb_query_each_page(query, label: "reduced packet query") do |result|
        results = []
        result.each do |tuples|
          objects.each do |object|
            entry = {
              "__type" => "PACKET",
              "__packet" => object.key
            }

            tuples.each do |tuple|
              col_name = tuple[0]
              value = tuple[1]

              if col_name == 'PACKET_TIMESECONDS'
                # Use nanosecond integer directly for full precision
                entry['__time'] = value.to_i
                next
              end

              # Decode aggregated value (always numeric)
              decoded_value = OpenC3::QuestDBClient.decode_value(value, data_type: 'DOUBLE', array_size: nil)

              # Map column name back to item name format expected by client
              # e.g., TEMP1__A -> TEMP1 with reduced_type AVG
              entry[col_name] = decoded_value
            end

            track_tsdb_time(object.topic, entry['__time'])
            results << entry
          end
        end
        @streaming_api.transmit_results(results) unless results.empty?
      end

      done = true if past_end_time?(end_time)
    end

    done
  end

  # --- TSDB query helpers (shared across stream_* methods) ---

  # Returns [start_time, end_time] from the min/max of all objects' time bounds.
  def compute_time_range(objects_by_topic)
    start_time = nil
    end_time = nil
    objects_by_topic.each_value do |objects|
      objects.each do |object|
        start_time = object.start_time if object.start_time and (start_time.nil? or object.start_time < start_time)
        end_time = object.end_time if object.end_time and (end_time.nil? or object.end_time > end_time)
      end
    end
    [start_time, end_time]
  end

  # Updates @last_tsdb_times for the given topic if time_ns is newer.
  def track_tsdb_time(topic, time_ns)
    return unless time_ns
    prev = @last_tsdb_times[topic]
    @last_tsdb_times[topic] = time_ns if !prev or time_ns > prev
  end

  # Returns the SAMPLE BY interval string for a given stream_mode symbol.
  def sample_interval_for(stream_mode)
    case stream_mode
    when :REDUCED_MINUTE then '1m'
    when :REDUCED_HOUR then '1h'
    when :REDUCED_DAY then '1d'
    else '1m'
    end
  end

  # Returns true if end_time is set and has been reached.
  def past_end_time?(end_time)
    end_time and end_time <= Time.now.to_nsec_from_epoch
  end

  # Coerce a PG timestamp value (which QuestDB may return as Float, Integer,
  # String, or PG timestamp object) into a Ruby UTC Time.
  def tsdb_coerce_to_utc(value)
    return nil unless value
    case value
    when Time
      value.utc
    when Float
      # Seconds since epoch (with fractional microseconds)
      Time.at(value).utc
    when Integer
      # Nanoseconds since epoch
      Time.at(value / 1_000_000_000, value % 1_000_000_000, :nsec, in: '+00:00').utc
    when String
      Time.parse(value).utc
    else
      # PG timestamp object (responds to year, month, etc.)
      OpenC3::QuestDBClient.pg_timestamp_to_utc(value)
    end
  end

  # Returns true if the given TSDB table exists and has at least one row in the
  # time range. Tables that have never received data don't exist in QuestDB.
  def tsdb_table_has_data?(table_name, start_time, end_time)
    query = "SELECT 1 FROM #{table_name}"
    query += tsdb_time_where(start_time, end_time)
    query += " LIMIT 1"
    result = nil
    @@conn_mutex.synchronize do
      @@conn ||= PG::Connection.new(
        host: ENV['OPENC3_TSDB_HOSTNAME'],
        port: ENV['OPENC3_TSDB_QUERY_PORT'],
        user: ENV['OPENC3_TSDB_USERNAME'],
        password: ENV['OPENC3_TSDB_PASSWORD'],
        dbname: 'qdb'
      )
      result = @@conn.exec(query)
    end
    result && result.ntuples > 0
  rescue IOError, PG::Error
    false
  end

  # Returns a WHERE clause fragment for packet timestamp filtering.
  def tsdb_time_where(start_time, end_time, prefix: '')
    where = " WHERE #{prefix}PACKET_TIMESECONDS >= #{start_time}"
    where += " AND #{prefix}PACKET_TIMESECONDS < #{end_time}" if end_time
    where
  end

  # Executes a paginated TSDB query, yielding each non-empty PG::Result page
  # inside the connection mutex. Handles connection setup, LIMIT pagination,
  # and retry up to 5 times on IOError/PG::Error.
  def tsdb_query_each_page(query, label:)
    min = 0
    max = @max_batch_size
    retry_count = 0
    loop do
      break if @cancel_thread
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
          OpenC3::Logger.debug("QuestDB #{label}: #{query_offset}")
          result = @@conn.exec(query_offset)
          min += @max_batch_size
          max += @max_batch_size
          if result.nil? or result.ntuples == 0
            return # No more pages
          else
            yield result
          end
        end
      rescue IOError, PG::Error => e
        retry_count += 1
        if retry_count > 4
          raise QuestDbError, "Error querying QuestDB (#{label}): #{e.message}"
        end
        OpenC3::Logger.warn("QuestDB #{label}: retry #{retry_count} - #{e.message}")
        OpenC3::Logger.warn("QuestDB #{label}: last query: #{query}")
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

    # Track timestamp values for computing derived items
    cosmos_timestamp_ns = nil
    received_timestamp_ns = nil

    # Second pass: process columns based on value_type
    tuples.each do |tuple|
      column_name = tuple[0]
      raw_value = tuple[1]

      # Use CAST(PACKET_TIMESECONDS AS LONG) for full nanosecond precision;
      # PG wire protocol truncates timestamp_ns columns to microsecond precision.
      if column_name == '__pkt_time_ns'
        cosmos_timestamp_ns = raw_value.to_i
        entry['__time'] = cosmos_timestamp_ns
        next
      end

      # Use CAST(RECEIVED_TIMESECONDS AS LONG) for full nanosecond precision
      if column_name == '__rx_time_ns'
        received_timestamp_ns = raw_value.to_i
        next
      end

      # Skip PG timestamp versions - handled via CAST AS LONG columns above
      next if column_name == 'PACKET_TIMESECONDS'
      next if column_name == 'RECEIVED_TIMESECONDS'

      # Skip metadata columns
      next if column_name == 'COSMOS_DATA_TAG'
      if column_name == 'COSMOS_EXTRA'
        entry['COSMOS_EXTRA'] = raw_value
        next
      end

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

    # Compute PACKET_TIMESECONDS and PACKET_TIMEFORMATTED from packet timestamp nanoseconds
    if cosmos_timestamp_ns
      pkt_time = Time.at(cosmos_timestamp_ns / 1_000_000_000, cosmos_timestamp_ns % 1_000_000_000, :nsec, in: '+00:00')
      entry['PACKET_TIMESECONDS'] = OpenC3::QuestDBClient.format_timestamp(pkt_time, :seconds)
      entry['PACKET_TIMEFORMATTED'] = OpenC3::QuestDBClient.format_timestamp(pkt_time, :formatted)
    end

    # Compute RECEIVED_TIMESECONDS and RECEIVED_TIMEFORMATTED from nanosecond timestamp
    if received_timestamp_ns
      rcv_time = Time.at(received_timestamp_ns / 1_000_000_000, received_timestamp_ns % 1_000_000_000, :nsec, in: '+00:00')
      entry['RECEIVED_TIMESECONDS'] = OpenC3::QuestDBClient.format_timestamp(rcv_time, :seconds)
      entry['RECEIVED_TIMEFORMATTED'] = OpenC3::QuestDBClient.format_timestamp(rcv_time, :formatted)
    end

    entry
  end

  def handle_packet(packet, objects)
    first_object = objects[0]
    if first_object.stream_mode == :RAW
      return handle_raw_packet(packet.buffer(false), objects, packet.packet_time.to_nsec_from_epoch)
    else # @stream_mode == :DECOM
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
