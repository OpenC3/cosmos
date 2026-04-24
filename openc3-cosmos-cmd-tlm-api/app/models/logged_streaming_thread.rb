# encoding: utf-8

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

  def initialize(streaming_api, collection, max_batch_size = 600, scope:, token:)
    super(streaming_api, collection, max_batch_size, scope: scope)
    @thread_mode = :SETUP
    @token = token
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
    oldest_msg_id, oldest_msg_hash = OpenC3::Topic.get_oldest_message(first_object.topic, db_shard: first_object.db_shard)

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

  def bridge_tsdb_to_stream
    return if @last_tsdb_times.empty?

    # Calculate Valkey stream offset per topic
    offset_by_topic = {}
    # Build topic-to-db_shard map from objects
    topic_db_shard_map = {}
    @collection.objects.each { |obj| topic_db_shard_map[obj.topic] = obj.db_shard }

    @last_tsdb_times.each do |topic, last_time|
      topic_db_shard = topic_db_shard_map[topic] || 0
      oldest_msg_id, oldest_msg_hash = OpenC3::Topic.get_oldest_message(topic, db_shard: topic_db_shard)
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
        db_shard_groups = build_db_shard_groups(topics, offsets, item_objects_by_topic, packet_objects_by_topic)

        timeout_per_db_shard = [500 / [db_shard_groups.length, 1].max, 100].max
        any_result = false
        db_shard_groups.each do |db_shard, group|
          break if @cancel_thread
          xread_result = OpenC3::Topic.read_topics(group[:topics], group[:offsets], timeout_per_db_shard, db_shard: db_shard) do |topic, msg_id, msg_hash, _|
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
          any_result = true if xread_result and xread_result.length > 0
        end

        @streaming_api.transmit_results(results)
        results.clear

        check_for_completed_objects() unless any_result
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
            if item_def['format_string'] or item_def['units']
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
          topics: Set.new,
          db_shard: OpenC3::QuestDBClient.db_shard_for_target(object.target_name, scope: @scope)
        }
        meta = per_table[table_name]
        meta[:topics] << topic

        item = available[item_index]
        tgt, pkt, orig_item_name, value_type = item.split('__')

        # Check if this is a stored timestamp item (PACKET_TIMESECONDS or RECEIVED_TIMESECONDS)
        # These are stored as timestamp_ns columns and need conversion to float seconds on read
        if OpenC3::QuestDBClient::STORED_TIMESTAMP_ITEMS.include?(orig_item_name)
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
          packet_cache[cache_key] = OpenC3::QuestDBClient.fetch_packet_def(tgt, pkt, type: pkt_type, scope: @scope)
        end

        packet_def = packet_cache[cache_key]
        item_def = OpenC3::QuestDBClient.find_item_def(packet_def, orig_item_name)

        safe_item_name = OpenC3::QuestDBClient.sanitize_column_name(orig_item_name)
        suffix = OpenC3::QuestDBClient.column_suffix_for_value_type(value_type)
        meta[:names] << "\"#{safe_item_name}#{suffix}\""
        meta[:item_types] << OpenC3::QuestDBClient.resolve_item_type(item_def, value_type)
        item_index += 1
      end
    end

    # Filter to tables that exist and have data in the queried range
    if per_table.size > 1
      per_table.select! do |table_name, meta|
        db_shard = meta[:db_shard]
        OpenC3::QuestDBClient.table_has_data?(table_name, start_time, end_time, db_shard: db_shard)
      end
    end

    # Build per-table queries independently.
    # Each table gets its own simple SELECT with only its columns.
    # Results are merged by timestamp using a k-way merge.
    cursors = []

    per_table.each do |table_name, meta|
      needs_received_ts = meta[:timestamp_source_columns].any? { |k, _| k.include?('RECEIVED_TIMESECONDS') }

      query_names = meta[:names].compact.dup  # compact removes nil (calculated) placeholders

      # Pre-compute mapping from SQL column index to local meta index.
      # Calculated positions (names[i] == nil) have no SQL column.
      sql_to_local = []
      meta[:names].each_with_index do |name, i|
        sql_to_local << i unless name.nil?
      end

      query = OpenC3::QuestDBClient.build_item_columns_query(table_name, query_names, start_time, end_time, include_received_ts: needs_received_ts)
      OpenC3::Logger.debug("QuestDB per-table query: #{query}")

      cursors << {
        query: query,
        meta: meta,
        sql_to_local: sql_to_local,
        result: nil,      # current PG::Result page
        row_index: 0,      # position within current page
        offset: 0,         # LIMIT offset for next fetch
        exhausted: false,
        table_name: table_name,
        db_shard: meta[:db_shard]
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
      entry = decode_cursor_row(min_cursor)
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
    query_offset = "#{cursor[:query]} LIMIT #{cursor[:offset]}, #{cursor[:offset] + @max_batch_size}"
    OpenC3::Logger.debug("QuestDB cursor fetch: #{query_offset}")
    result = OpenC3::QuestDBClient.query_with_retry(query_offset, label: "cursor fetch", db_shard: cursor[:db_shard])
    cursor[:offset] += @max_batch_size
    if result.nil? || result.ntuples == 0
      cursor[:result] = nil
      cursor[:exhausted] = true
    else
      cursor[:result] = result
      cursor[:row_index] = 0
    end
  end

  # Decode the current row of a cursor using QuestDBClient
  def decode_cursor_row(cursor)
    result = cursor[:result]
    return nil unless result
    row_index = cursor[:row_index]
    return nil if row_index >= result.ntuples
    OpenC3::QuestDBClient.decode_item_row(result[row_index], cursor[:sql_to_local], cursor[:meta])
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
        objects_by_table_and_mode[key] ||= { objects: [], db_shard: OpenC3::QuestDBClient.db_shard_for_target(object.target_name, scope: @scope) }
        objects_by_table_and_mode[key][:objects] << object
      end
    end

    return end_time ? true : false if objects_by_table_and_mode.empty?

    done = false

    objects_by_table_and_mode.each do |(table_name, stream_mode), group_info|
      break if @cancel_thread
      objects = group_info[:objects]
      db_shard = group_info[:db_shard]

      sample_interval = OpenC3::QuestDBClient.sample_interval_for(stream_mode)

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
      selects = [OpenC3::QuestDBClient::TIMESTAMP_SELECT]
      column_mapping = {} # Maps result column name to [item_key, reduced_type, value_type]

      items_to_query.each do |item_name, info|
        safe_item_name = OpenC3::QuestDBClient.sanitize_column_name(item_name)

        info[:value_types].each do |value_type|
          next unless value_type == :RAW || value_type == :CONVERTED
          agg_selects, agg_mapping = OpenC3::QuestDBClient.build_aggregation_selects(safe_item_name, value_type, item_name: item_name)
          selects.concat(agg_selects)
          column_mapping.merge!(agg_mapping)
        end
      end

      query = OpenC3::QuestDBClient.build_reduced_query(table_name, selects, start_time, end_time, sample_interval)

      OpenC3::QuestDBClient.paginate_query(query, @max_batch_size, label: "reduced query", db_shard: db_shard) do |result|
        break if @cancel_thread
        results = []
        result.each do |tuples|
          decoded = OpenC3::QuestDBClient.decode_reduced_row(tuples)
          entry = { "__type" => "ITEMS" }
          entry['__time'] = decoded['__time']

          decoded.each do |col_name, decoded_value|
            next if col_name == '__time'
            mapping = column_mapping[col_name]
            next unless mapping

            item_name, reduced_type, value_type = mapping

            objects.each do |object|
              if object.item_name == item_name &&
                 object.reduced_type == reduced_type &&
                 object.value_type == value_type
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
      objects_by_table[table_name] ||= { objects: [], db_shard: OpenC3::QuestDBClient.db_shard_for_target(object.target_name, scope: @scope) }
      objects_by_table[table_name][:objects] << object
    end

    done = false

    objects_by_table.each do |table_name, group_info|
      break if @cancel_thread
      objects = group_info[:objects]
      db_shard = group_info[:db_shard]

      first_object = objects[0]
      value_type = first_object.value_type

      pkt_type = (first_object.cmd_or_tlm == :CMD) ? :CMD : :TLM
      packet_def = OpenC3::QuestDBClient.fetch_packet_def(first_object.target_name, first_object.packet_name, type: pkt_type, scope: @scope)

      query = OpenC3::QuestDBClient.build_packet_query(table_name, start_time, end_time)

      OpenC3::QuestDBClient.paginate_query(query, @max_batch_size, label: "packet query", db_shard: db_shard) do |result|
        break if @cancel_thread
        results = []
        result.each do |tuples|
          objects.each do |object|
            decoded = OpenC3::QuestDBClient.decode_packet_row(tuples, value_type, packet_def)
            if decoded
              entry = decoded.merge("__type" => "PACKET", "__packet" => object.key)
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
      objects_by_table_and_mode[key] ||= { objects: [], db_shard: OpenC3::QuestDBClient.db_shard_for_target(object.target_name, scope: @scope) }
      objects_by_table_and_mode[key][:objects] << object
    end

    done = false

    objects_by_table_and_mode.each do |(table_name, stream_mode), group_info|
      break if @cancel_thread
      objects = group_info[:objects]
      db_shard = group_info[:db_shard]

      first_object = objects[0]
      value_type = first_object.value_type
      sample_interval = OpenC3::QuestDBClient.sample_interval_for(stream_mode)

      pkt_type = (first_object.cmd_or_tlm == :CMD) ? :CMD : :TLM
      packet_def = OpenC3::QuestDBClient.fetch_packet_def(first_object.target_name, first_object.packet_name, type: pkt_type, scope: @scope)

      selects, has_items = OpenC3::QuestDBClient.build_packet_reduced_selects(packet_def, value_type)
      unless has_items
        OpenC3::Logger.warn("No numeric items found for reduced packet query on #{table_name}")
        next
      end

      query = OpenC3::QuestDBClient.build_reduced_query(table_name, selects, start_time, end_time, sample_interval)

      OpenC3::QuestDBClient.paginate_query(query, @max_batch_size, label: "reduced packet query", db_shard: db_shard) do |result|
        break if @cancel_thread
        results = []
        result.each do |tuples|
          decoded = OpenC3::QuestDBClient.decode_reduced_row(tuples)
          objects.each do |object|
            entry = decoded.merge("__type" => "PACKET", "__packet" => object.key)
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

  # Returns true if end_time is set and has been reached.
  def past_end_time?(end_time)
    end_time and end_time <= Time.now.to_nsec_from_epoch
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
