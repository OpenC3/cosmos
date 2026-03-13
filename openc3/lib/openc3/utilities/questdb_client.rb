# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'json'
require 'base64'
require 'bigdecimal'
require 'set'
require 'pg'
require 'concurrent'

module OpenC3
  # Utility class for QuestDB data encoding and decoding.
  # This provides a common interface for serializing/deserializing COSMOS data types
  # when writing to and reading from QuestDB.
  class QuestDBClient
    # Thread-local PG connection storage using Concurrent::ThreadLocalVar.
    # Each thread gets its own connection to avoid thread-safety issues with PG::Connection.
    # Connections are automatically garbage collected when threads terminate.
    @thread_conn = Concurrent::ThreadLocalVar.new(nil)

    # Get or create a thread-local PG connection with type mapping configured.
    # Returns the thread-local connection — callers should not close it.
    def self.connection
      conn = @thread_conn.value
      if conn.nil? || conn.finished?
        conn = PG::Connection.new(
          host: ENV['OPENC3_TSDB_HOSTNAME'],
          port: ENV['OPENC3_TSDB_QUERY_PORT'],
          user: ENV['OPENC3_TSDB_USERNAME'],
          password: ENV['OPENC3_TSDB_PASSWORD'],
          dbname: 'qdb'
        )
        conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn)
        @thread_conn.value = conn
      end
      conn
    end

    # Reset the connection for the current thread. Used after errors.
    def self.disconnect
      conn = @thread_conn.value
      if conn && !conn.finished?
        conn.finish
      end
      @thread_conn.value = nil
    end

    # Health check — attempt to connect and immediately close.
    # Returns true if successful, raises on failure.
    def self.check_connection
      conn = PG::Connection.new(
        host: ENV['OPENC3_TSDB_HOSTNAME'],
        port: ENV['OPENC3_TSDB_QUERY_PORT'],
        user: ENV['OPENC3_TSDB_USERNAME'],
        password: ENV['OPENC3_TSDB_PASSWORD'],
        dbname: 'qdb'
      )
      conn.close
      true
    end

    # Special timestamp items that are calculated from PACKET_TIMESECONDS/RECEIVED_TIMESECONDS columns
    # rather than stored as separate columns. PACKET_TIMESECONDS and RECEIVED_TIMESECONDS are stored
    # as timestamp_ns columns and need conversion to float seconds on read. The TIMEFORMATTED items
    # are derived from these timestamp columns.
    TIMESTAMP_ITEMS = {
      'PACKET_TIMEFORMATTED' => { source: 'PACKET_TIMESECONDS', format: :formatted },
      'RECEIVED_TIMEFORMATTED' => { source: 'RECEIVED_TIMESECONDS', format: :formatted }
    }.freeze

    # Stored timestamp items that are stored as timestamp_ns columns and need
    # conversion to float seconds on read. Distinguished from calculated items above.
    STORED_TIMESTAMP_ITEMS = Set.new(['PACKET_TIMESECONDS', 'RECEIVED_TIMESECONDS']).freeze

    # Sentinel values for storing float special values (inf, -inf, nan) in QuestDB.
    # QuestDB stores these as NULL, so we use sentinel values near float max instead.

    # 64-bit double sentinels (for FLOAT 64-bit columns)
    FLOAT64_POS_INF_SENTINEL = 1.7976931348623155e308
    FLOAT64_NEG_INF_SENTINEL = -1.7976931348623155e308
    FLOAT64_NAN_SENTINEL = -1.7976931348623153e308

    # 32-bit float sentinels (what we read back after 32-bit storage)
    FLOAT32_POS_INF_STORED = 3.4028232635611926e38
    FLOAT32_NEG_INF_STORED = -3.4028232635611926e38
    FLOAT32_NAN_STORED = -3.4028230607370965e38

    # Decode sentinel values back to float special values (inf, -inf, nan).
    # Checks against both 32-bit and 64-bit sentinel values since we may not
    # know the original column type at read time.
    #
    # @param value [Float] The float value to potentially decode
    # @return [Float] The value with sentinels replaced by special values
    def self.decode_float_special_values(value)
      return value unless value.is_a?(Float)

      # Check 64-bit sentinels
      return Float::INFINITY if value == FLOAT64_POS_INF_SENTINEL
      return -Float::INFINITY if value == FLOAT64_NEG_INF_SENTINEL
      return Float::NAN if value == FLOAT64_NAN_SENTINEL

      # Check 32-bit sentinels (stored values after precision loss)
      return Float::INFINITY if value == FLOAT32_POS_INF_STORED
      return -Float::INFINITY if value == FLOAT32_NEG_INF_STORED
      return Float::NAN if value == FLOAT32_NAN_STORED

      value
    end

    # Decode a value retrieved from QuestDB back to its original Ruby type.
    #
    # QuestDB stores certain COSMOS types as encoded strings:
    # - Arrays are JSON-encoded: "[1, 2, 3]" or '["a", "b"]'
    # - Objects/Hashes are JSON-encoded: '{"key": "value"}'
    # - Binary data (BLOCK) is base64-encoded
    # - Large integers (64-bit) are stored as DECIMAL
    #
    # @param value [Object] The value to decode
    # @param data_type [String] COSMOS data type (INT, UINT, FLOAT, STRING, BLOCK, DERIVED, etc.)
    # @param array_size [Integer, nil] If not nil, indicates this is an array item
    # @return [Object] The decoded value
    def self.decode_value(value, data_type: nil, array_size: nil)
      # Handle BigDecimal values from QuestDB DECIMAL columns (used for 64-bit integers)
      if value.is_a?(BigDecimal)
        return value.to_i if data_type == 'INT' || data_type == 'UINT'
        return value
      end

      # Decode float sentinel values back to inf/nan
      return decode_float_special_values(value) if value.is_a?(Float)

      # Non-strings don't need decoding (already handled by PG type mapping)
      return value unless value.is_a?(String)

      # Empty strings stay as empty strings
      return value if value.empty?

      # Handle based on data type if provided
      if data_type == 'BLOCK'
        begin
          return Base64.strict_decode64(value)
        rescue ArgumentError
          return value
        end
      end

      # Arrays are JSON-encoded
      if array_size
        begin
          return JSON.parse(value, allow_nan: true, create_additions: true)
        rescue JSON::ParserError
          return value
        end
      end

      # Integer values stored as strings (fallback path, normally DECIMAL)
      if data_type == 'INT' || data_type == 'UINT'
        begin
          return Integer(value)
        rescue ArgumentError
          return value
        end
      end

      # DERIVED items with declared converted_type are stored as typed columns
      # (float, int, etc.) and will be returned as non-strings, handled above.
      # DERIVED items without declared type or with complex types (ARRAY, OBJECT, ANY)
      # are stored as VARCHAR and JSON-encoded.
      if data_type == 'DERIVED'
        begin
          return JSON.parse(value, allow_nan: true, create_additions: true)
        rescue JSON::ParserError
          # Could be a plain string from DERIVED with converted_type=STRING
          return value
        end
      end

      # No data_type provided - fall back to heuristic decoding
      if data_type.nil?
        first_char = value[0]
        # Try JSON for arrays/objects
        if first_char == '[' || first_char == '{'
          begin
            return JSON.parse(value, allow_nan: true, create_additions: true)
          rescue JSON::ParserError
            # Not valid JSON
          end
        # Try integer conversion for numeric strings
        elsif value =~ /\A-?\d+\z/
          begin
            return Integer(value)
          rescue ArgumentError
            # Not a valid integer
          end
        end
      end

      # Return as-is (STRING type or unknown)
      value
    end

    # Sanitize a table name for QuestDB.
    # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
    #
    # @param target_name [String] Target name
    # @param packet_name [String] Packet name
    # @param cmd_or_tlm [String, Symbol] "CMD" or "TLM" prefix (default "TLM")
    # @param scope [String] Scope name (default "DEFAULT")
    # @return [String] Sanitized table name
    def self.sanitize_table_name(target_name, packet_name, cmd_or_tlm = "TLM", scope: "DEFAULT")
      "#{scope}__#{cmd_or_tlm}__#{target_name}__#{packet_name}".gsub(/[?,'"\\\/:\)\(\+\*\%~]/, '_')
    end

    # Sanitize a column name for QuestDB.
    # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
    #
    # @param item_name [String] Item name
    # @return [String] Sanitized column name
    # ILP protocol special characters that must be sanitized in column names
    def self.sanitize_column_name(item_name)
      item_name.to_s.gsub(/[?\.,'"\\\/:\)\(\+=\-\*\%~;!@#\$\^&]/, '_')
    end

    # Find an item definition within a packet definition by name.
    #
    # @param packet_def [Hash, nil] Packet definition from TargetModel.packet
    # @param item_name [String] Item name to find
    # @return [Hash, nil] Item definition hash or nil if not found
    def self.find_item_def(packet_def, item_name)
      return nil unless packet_def
      packet_def['items']&.each do |item|
        return item if item['name'] == item_name
      end
      nil
    end

    # Resolve the data_type and array_size for a QuestDB column based on the
    # item definition and requested value type. This encapsulates the common
    # logic for determining how to decode a value read from QuestDB.
    #
    # @param item_def [Hash, nil] Item definition from packet definition
    # @param value_type [String] One of 'RAW', 'CONVERTED', 'FORMATTED', 'WITH_UNITS'
    # @return [Hash] { 'data_type' => String|nil, 'array_size' => Integer|nil }
    def self.resolve_item_type(item_def, value_type)
      case value_type
      when 'FORMATTED', 'WITH_UNITS'
        { 'data_type' => 'STRING', 'array_size' => nil }
      when 'CONVERTED'
        if item_def
          rc = item_def['read_conversion']
          if rc && rc['converted_type']
            { 'data_type' => rc['converted_type'], 'array_size' => item_def['array_size'] }
          elsif item_def['states']
            { 'data_type' => 'STRING', 'array_size' => nil }
          else
            { 'data_type' => item_def['data_type'], 'array_size' => item_def['array_size'] }
          end
        else
          { 'data_type' => nil, 'array_size' => nil }
        end
      else # RAW or default
        if item_def
          { 'data_type' => item_def['data_type'], 'array_size' => item_def['array_size'] }
        else
          { 'data_type' => nil, 'array_size' => nil }
        end
      end
    end

    # Execute a SQL query with automatic retry on connection errors.
    # Handles PG connection management and retries up to max_retries times.
    #
    # @param query [String] SQL query to execute
    # @param params [Array] Query parameters for parameterized queries (uses exec_params)
    # @param max_retries [Integer] Maximum number of retry attempts (default 5)
    # @param label [String, nil] Optional label for log messages
    # @return [PG::Result, nil] Query result
    # @raise [RuntimeError] After exhausting retries
    def self.query_with_retry(query, params: [], max_retries: 5, label: nil)
      retry_count = 0
      begin
        conn = connection
        if params.empty?
          conn.exec(query)
        else
          conn.exec_params(query, params)
        end
      rescue IOError, PG::Error => e
        retry_count += 1
        if retry_count > (max_retries - 1)
          raise "Error querying TSDB#{label ? " (#{label})" : ""}: #{e.message}"
        end
        Logger.warn("TSDB#{label ? " #{label}" : ""}: Retrying due to error: #{e.message}")
        Logger.warn("TSDB#{label ? " #{label}" : ""}: Last query: #{query}")
        disconnect
        sleep 0.1
        retry
      end
    end

    # Convert a nanosecond integer timestamp to a UTC Time object.
    #
    # @param nsec [Integer] Nanoseconds since epoch
    # @return [Time] UTC Time object
    def self.nsec_to_utc_time(nsec)
      return nil unless nsec
      Time.at(nsec / 1_000_000_000, nsec % 1_000_000_000, :nsec, in: '+00:00')
    end

    # Coerce a value from QuestDB (which may be a Time, Float, Integer, String,
    # or PG timestamp object) into a Ruby UTC Time.
    #
    # @param value [Object] Timestamp value in any supported format
    # @return [Time, nil] UTC Time object or nil
    def self.coerce_to_utc(value)
      return nil unless value
      case value
      when Time
        value.utc
      when Float
        Time.at(value).utc
      when Integer
        nsec_to_utc_time(value).utc
      when String
        require 'time'
        Time.parse(value).utc
      else
        # PG timestamp object (responds to year, month, etc.)
        pg_timestamp_to_utc(value)
      end
    end

    # Convert a PG timestamp to UTC.
    # PG driver returns timestamps as naive Time objects that need UTC treatment.
    # QuestDB stores timestamps in UTC, but the PG driver applies local timezone.
    #
    # @param pg_time [Time] Timestamp from PG query result
    # @return [Time] UTC timestamp
    def self.pg_timestamp_to_utc(pg_time)
      return nil unless pg_time
      Time.utc(pg_time.year, pg_time.month, pg_time.day,
               pg_time.hour, pg_time.min, pg_time.sec, pg_time.usec)
    end

    # Format a UTC timestamp according to the specified format.
    #
    # @param utc_time [Time] UTC timestamp
    # @param format [Symbol] :seconds for Unix seconds (float), :formatted for ISO 8601
    # @return [Float, String, nil] Formatted timestamp or nil if utc_time is nil
    def self.format_timestamp(utc_time, format)
      return nil unless utc_time
      case format
      when :seconds
        utc_time.to_f
      when :formatted
        utc_time.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')
      else
        nil
      end
    end

    # Return the QuestDB column suffix for a given value type.
    #
    # @param value_type [String] One of 'RAW', 'CONVERTED', 'FORMATTED', 'WITH_UNITS'
    # @return [String] Column suffix (e.g., '__C', '__F', or '')
    def self.column_suffix_for_value_type(value_type)
      case value_type
      when 'FORMATTED' then '__F'
      when 'WITH_UNITS' then '__F'
      when 'CONVERTED' then '__C'
      else ''
      end
    end

    # Determine the value type from a QuestDB column name's suffix.
    #
    # @param column_name [String] Column name possibly ending in __C, __F, __U, __L
    # @return [String] One of 'FORMATTED', 'WITH_UNITS', 'CONVERTED', 'RAW'
    def self.value_type_for_column_suffix(column_name)
      if column_name.end_with?('__F') then 'FORMATTED'
      elsif column_name.end_with?('__U') then 'WITH_UNITS'
      elsif column_name.end_with?('__C') then 'CONVERTED'
      else 'RAW'
      end
    end

    # Build a SQL WHERE clause for PACKET_TIMESECONDS range filtering.
    #
    # @param start_time [Integer, String] Start timestamp (nanoseconds)
    # @param end_time [Integer, String, nil] End timestamp (nanoseconds), or nil for open-ended
    # @param prefix [String] Table alias prefix (e.g., 'T0.') — default ''
    # @return [String] SQL WHERE clause fragment (includes leading space)
    def self.time_where_clause(start_time, end_time, prefix: '')
      where = " WHERE #{prefix}PACKET_TIMESECONDS >= #{start_time}"
      where += " AND #{prefix}PACKET_TIMESECONDS < #{end_time}" if end_time
      where
    end

    # Fetch a packet definition from TargetModel, returning nil if not found.
    #
    # @param target_name [String] Target name
    # @param packet_name [String] Packet name
    # @param type [Symbol] :CMD or :TLM (default :TLM)
    # @param scope [String] Scope name
    # @return [Hash, nil] Packet definition or nil
    def self.fetch_packet_def(target_name, packet_name, type: :TLM, scope: "DEFAULT")
      require 'openc3/models/target_model'
      TargetModel.packet(target_name, packet_name, type: type, scope: scope)
    rescue RuntimeError
      nil
    end

    # Build a hash mapping sanitized column names to item definitions.
    # Used for type-aware decoding of QuestDB SELECT * results.
    #
    # @param packet_def [Hash, nil] Packet definition from TargetModel.packet
    # @return [Hash] { sanitized_column_name => item_def_hash }
    def self.build_item_defs_map(packet_def)
      map = {}
      return map unless packet_def
      packet_def['items']&.each do |item|
        map[sanitize_column_name(item['name'])] = item
      end
      map
    end

    # Build aggregation SELECT columns (min/max/avg/stddev) for a single item.
    # Returns the SELECT fragments and a column_mapping hash.
    #
    # @param safe_item_name [String] Sanitized column name
    # @param value_type [Symbol] :RAW or :CONVERTED
    # @param item_name [String, nil] Original (unsanitized) item name for mapping values.
    #   Defaults to safe_item_name if not provided.
    # @return [Array<String>, Hash] Two-element array: [select_fragments, column_mapping]
    #   column_mapping maps result column alias to [item_name, reduced_type, value_type]
    def self.build_aggregation_selects(safe_item_name, value_type, item_name: nil)
      item_name ||= safe_item_name
      selects = []
      mapping = {}
      case value_type
      when :RAW
        col = safe_item_name
        { 'N' => :MIN, 'X' => :MAX, 'A' => :AVG, 'S' => :STDDEV }.each do |suffix, reduced_type|
          alias_name = "#{safe_item_name}__#{suffix}"
          selects << "#{reduced_type.to_s.downcase}(\"#{col}\") as \"#{alias_name}\""
          mapping[alias_name] = [item_name, reduced_type, :RAW]
        end
      when :CONVERTED
        col = "#{safe_item_name}__C"
        { 'CN' => :MIN, 'CX' => :MAX, 'CA' => :AVG, 'CS' => :STDDEV }.each do |suffix, reduced_type|
          alias_name = "#{safe_item_name}__#{suffix}"
          selects << "#{reduced_type.to_s.downcase}(\"#{col}\") as \"#{alias_name}\""
          mapping[alias_name] = [item_name, reduced_type, :CONVERTED]
        end
      end
      [selects, mapping]
    end

    # Build aggregation SELECT columns for all numeric items in a packet definition.
    # Filters out STRING, BLOCK, and DERIVED items since they can't be aggregated.
    #
    # @param packet_def [Hash, nil] Packet definition from TargetModel.packet
    # @param value_type [Symbol] :RAW or :CONVERTED
    # @return [Array<String>, Boolean] Two-element array: [select_fragments, has_numeric_items]
    #   select_fragments includes TIMESTAMP_SELECT as the first element.
    def self.build_packet_reduced_selects(packet_def, value_type)
      selects = [TIMESTAMP_SELECT]
      has_items = false
      return [selects, false] unless packet_def && packet_def['items']

      packet_def['items'].each do |item|
        data_type = item['data_type']
        next if data_type.nil?
        next if ['STRING', 'BLOCK', 'DERIVED'].include?(data_type)
        next unless value_type == :RAW || value_type == :CONVERTED

        safe_name = sanitize_column_name(item['name'])
        agg_selects, _ = build_aggregation_selects(safe_name, value_type)
        selects.concat(agg_selects)
        has_items = true
      end

      [selects, has_items]
    end

    # Add TIMESECONDS and TIMEFORMATTED entries to a hash from a nanosecond timestamp.
    # Used when building packet entries from CAST(timestamp AS LONG) columns.
    #
    # @param entry [Hash] Entry hash to populate
    # @param timestamp_ns [Integer] Nanoseconds since epoch
    # @param prefix [String] 'PACKET' or 'RECEIVED'
    def self.add_timestamp_entries!(entry, timestamp_ns, prefix)
      return unless timestamp_ns
      utc_time = nsec_to_utc_time(timestamp_ns)
      entry["#{prefix}_TIMESECONDS"] = format_timestamp(utc_time, :seconds)
      entry["#{prefix}_TIMEFORMATTED"] = format_timestamp(utc_time, :formatted)
    end

    # SQL: nanosecond-precision packet timestamp for explicit SELECT lists.
    # PG wire protocol truncates timestamp_ns to microseconds; CAST AS LONG preserves full precision.
    TIMESTAMP_SELECT = 'CAST(PACKET_TIMESECONDS AS LONG) as PACKET_TIMESECONDS'

    # SQL: nanosecond-precision timestamps for SELECT * queries (different aliases avoid column name collision).
    TIMESTAMP_EXTRAS = 'CAST(PACKET_TIMESECONDS AS LONG) as "__pkt_time_ns", CAST(RECEIVED_TIMESECONDS AS LONG) as "__rx_time_ns"'

    # Returns the SAMPLE BY interval string for a given stream_mode symbol.
    #
    # @param stream_mode [Symbol] :REDUCED_MINUTE, :REDUCED_HOUR, or :REDUCED_DAY
    # @return [String] QuestDB SAMPLE BY interval string
    def self.sample_interval_for(stream_mode)
      case stream_mode
      when :REDUCED_MINUTE then '1m'
      when :REDUCED_HOUR then '1h'
      when :REDUCED_DAY then '1d'
      else '1m'
      end
    end

    # Returns true if the given TSDB table exists and has at least one row in the time range.
    #
    # @param table_name [String] Sanitized table name
    # @param start_time [Integer] Nanosecond start time
    # @param end_time [Integer, nil] Nanosecond end time
    # @return [Boolean]
    def self.table_has_data?(table_name, start_time, end_time)
      query = "SELECT 1 FROM #{table_name}"
      query += time_where_clause(start_time, end_time)
      query += " LIMIT 1"
      result = query_with_retry(query, max_retries: 1, label: "table_has_data")
      result && result.ntuples > 0
    rescue RuntimeError
      false
    end

    # Execute a paginated TSDB query, yielding each non-empty PG::Result page.
    # Handles LIMIT pagination and retry on error.
    #
    # @param query [String] Base SQL query (without LIMIT clause)
    # @param page_size [Integer] Number of rows per page
    # @param label [String] Label for log messages
    # @yield [PG::Result] Each page of results
    def self.paginate_query(query, page_size, label:)
      min = 0
      max = page_size
      loop do
        query_offset = "#{query} LIMIT #{min}, #{max}"
        Logger.debug("QuestDB #{label}: #{query_offset}")
        result = query_with_retry(query_offset, label: label)
        min += page_size
        max += page_size
        if result.nil? or result.ntuples == 0
          return
        else
          yield result
        end
      end
    end

    # Build a SELECT query for specific item columns from a single table.
    #
    # @param table_name [String] Sanitized QuestDB table name
    # @param column_names [Array<String>] Quoted column expressions (e.g., '"TEMP1__C"')
    # @param start_time [Integer] Start timestamp in nanoseconds
    # @param end_time [Integer, nil] End timestamp in nanoseconds
    # @param include_received_ts [Boolean] Whether to include RECEIVED_TIMESECONDS
    # @return [String] Complete SQL query (without LIMIT clause)
    def self.build_item_columns_query(table_name, column_names, start_time, end_time, include_received_ts: false)
      names = column_names.dup
      names << TIMESTAMP_SELECT
      names << "RECEIVED_TIMESECONDS" if include_received_ts
      names << "COSMOS_EXTRA"
      query = "SELECT #{names.join(', ')} FROM #{table_name}"
      query += time_where_clause(start_time, end_time)
      query
    end

    # Build a SELECT * query for full packet data from a single table.
    #
    # @param table_name [String] Sanitized QuestDB table name
    # @param start_time [Integer] Start timestamp in nanoseconds
    # @param end_time [Integer, nil] End timestamp in nanoseconds
    # @return [String] Complete SQL query (without LIMIT clause)
    def self.build_packet_query(table_name, start_time, end_time)
      query = "SELECT *, #{TIMESTAMP_EXTRAS} FROM \"#{table_name}\""
      query += time_where_clause(start_time, end_time)
      query
    end

    # Build a SAMPLE BY aggregation query for reduced data.
    #
    # @param table_name [String] Sanitized QuestDB table name
    # @param select_columns [Array<String>] SELECT column expressions including aggregations
    # @param start_time [Integer] Start timestamp in nanoseconds
    # @param end_time [Integer, nil] End timestamp in nanoseconds
    # @param sample_interval [String] QuestDB SAMPLE BY interval ('1m', '1h', '1d')
    # @return [String] Complete SQL query (without LIMIT clause)
    def self.build_reduced_query(table_name, select_columns, start_time, end_time, sample_interval)
      query = "SELECT #{select_columns.join(', ')} FROM \"#{table_name}\""
      query += time_where_clause(start_time, end_time)
      query += " SAMPLE BY #{sample_interval}"
      query += " ALIGN TO CALENDAR"
      query += " ORDER BY PACKET_TIMESECONDS"
      query
    end

    # Decode a single row from a per-table item columns query into an entry hash.
    # Handles stored timestamps, calculated timestamps, and regular value decoding.
    #
    # @param row [PG::Result row] Single row (iterable as [col_name, value] pairs)
    # @param sql_to_local [Array<Integer>] Mapping from SQL column index to meta position
    # @param meta [Hash] Per-table metadata with keys:
    #   :item_keys [Array<String>] - ordered list of item key identifiers
    #   :item_types [Array<Hash>] - type info per position ({ 'data_type' =>, 'array_size' => })
    #   :stored_timestamp_item_keys [Hash] - { item_key => { column: col_name } }
    #   :calculated_positions [Hash] - { local_idx => { source: col_name, format: :seconds/:formatted } }
    # @return [Hash] Entry hash with __type, item_key => value, __time, COSMOS_EXTRA
    def self.decode_item_row(row, sql_to_local, meta)
      num_sql_item_cols = sql_to_local.length

      entry = { "__type" => "ITEMS" }
      timestamp_values = {}
      time_ns = nil
      cosmos_extra = nil

      values = Array.new(meta[:item_keys].length)

      row.each_with_index do |tuple, sql_index|
        col_name = tuple[0]
        value = tuple[1]

        # Fixed columns come after item columns
        if sql_index >= num_sql_item_cols
          case col_name
          when 'PACKET_TIMESECONDS'
            time_ns = value.to_i
            timestamp_values['PACKET_TIMESECONDS'] = nsec_to_utc_time(time_ns)
          when 'RECEIVED_TIMESECONDS'
            timestamp_values['RECEIVED_TIMESECONDS'] = value if value
          when 'COSMOS_EXTRA'
            cosmos_extra = value
          end
          next
        end

        local_idx = sql_to_local[sql_index]

        # Track timestamp values from item columns
        if col_name == 'RECEIVED_TIMESECONDS'
          timestamp_values['RECEIVED_TIMESECONDS'] = value
        end

        next if value.nil?

        type_info = meta[:item_types][local_idx] || {}
        if meta[:stored_timestamp_item_keys].key?(meta[:item_keys][local_idx])
          ts_utc = coerce_to_utc(value)
          values[local_idx] = format_timestamp(ts_utc, :seconds) if ts_utc
        else
          values[local_idx] = decode_value(
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
          ts_utc = coerce_to_utc(ts_value)
          calculated_value = format_timestamp(ts_utc, calc_info[:format])
          entry[item_key] = calculated_value if calculated_value
        elsif !values[local_idx].nil?
          entry[item_key] = values[local_idx]
        end
      end

      entry['__time'] = time_ns if time_ns
      entry['COSMOS_EXTRA'] = cosmos_extra if cosmos_extra
      entry
    end

    # Decode a single row from a SELECT * packet query into an entry hash.
    # Handles nanosecond timestamp CAST columns, value-type column preference,
    # and type-aware decoding.
    #
    # @param row [PG::Result row] Single row as iterable [col_name, value] pairs
    # @param value_type [Symbol] :RAW, :CONVERTED, :FORMATTED, or :WITH_UNITS
    # @param packet_def [Hash, nil] Packet definition for type-aware decoding
    # @return [Hash] Entry hash with item => value, __time, COSMOS_EXTRA, timestamp entries
    def self.decode_packet_row(row, value_type, packet_def)
      entry = {}
      item_defs = build_item_defs_map(packet_def)

      # First pass: build a hash of all columns for value-type preference lookups
      columns = {}
      row.each do |tuple|
        columns[tuple[0]] = tuple[1]
      end

      cosmos_timestamp_ns = nil
      received_timestamp_ns = nil

      # Second pass: process columns based on value_type
      row.each do |tuple|
        column_name = tuple[0]
        raw_value = tuple[1]

        if column_name == '__pkt_time_ns'
          cosmos_timestamp_ns = raw_value.to_i
          entry['__time'] = cosmos_timestamp_ns
          next
        end

        if column_name == '__rx_time_ns'
          received_timestamp_ns = raw_value.to_i
          next
        end

        # Skip PG timestamp versions - handled via CAST AS LONG columns above
        next if column_name == 'PACKET_TIMESECONDS'
        next if column_name == 'RECEIVED_TIMESECONDS'
        next if column_name == 'COSMOS_DATA_TAG'

        if column_name == 'COSMOS_EXTRA'
          entry['COSMOS_EXTRA'] = raw_value
          next
        end

        base_name = column_name.sub(/(__C|__F|__U)$/, '')
        item_def = item_defs[base_name]

        col_value_type = value_type_for_column_suffix(column_name)
        type_info = resolve_item_type(item_def, col_value_type)
        value = decode_value(raw_value, data_type: type_info['data_type'], array_size: type_info['array_size'])

        case value_type
        when :RAW
          next if column_name.end_with?('__C', '__F', '__U')
          entry[column_name] = value
        when :CONVERTED
          if column_name.end_with?('__C')
            entry[column_name.sub(/__C$/, '')] = value
          elsif !column_name.end_with?('__F', '__U') && !columns.key?("#{column_name}__C")
            entry[column_name] = value
          end
        when :FORMATTED, :WITH_UNITS
          if column_name.end_with?('__F')
            entry[column_name.sub(/__F$/, '')] = value
          elsif column_name.end_with?('__C') && !columns.key?("#{column_name.sub(/__C$/, '')}__F")
            entry[column_name.sub(/__C$/, '')] = value
          elsif !column_name.end_with?('__C', '__F', '__U') && !columns.key?("#{column_name}__F") && !columns.key?("#{column_name}__C")
            entry[column_name] = value
          end
        end
      end

      add_timestamp_entries!(entry, cosmos_timestamp_ns, 'PACKET')
      add_timestamp_entries!(entry, received_timestamp_ns, 'RECEIVED')
      entry
    end

    # Decode a single row from a SAMPLE BY aggregation query.
    # All non-timestamp columns are decoded as DOUBLE (aggregation results are always numeric).
    #
    # @param row [PG::Result row] Single row as iterable [col_name, value] pairs
    # @return [Hash] { col_name => decoded_value, '__time' => ns_integer }
    def self.decode_reduced_row(row)
      entry = {}
      row.each do |tuple|
        col_name = tuple[0]
        value = tuple[1]
        if col_name == 'PACKET_TIMESECONDS'
          entry['__time'] = value.to_i
        else
          entry[col_name] = decode_value(value, data_type: 'DOUBLE', array_size: nil)
        end
      end
      entry
    end

    # Query historical telemetry data from QuestDB for a list of items.
    # Builds the SQL query, executes it, and decodes all results.
    #
    # @param items [Array] Array of [target_name, packet_name, item_name, value_type, limits]
    #   item_name may be nil to indicate a placeholder (non-existent item)
    # @param start_time [String, Numeric] Start timestamp for the query
    # @param end_time [String, Numeric, nil] End timestamp, or nil for "latest single row"
    # @param scope [String] Scope name
    # @return [Array, Hash] Array of [value, limits_state] pairs per row, or {} if no results.
    #   Single-row results return a flat array; multi-row results return array of arrays.
    def self.tsdb_lookup(items, start_time:, end_time: nil, scope: "DEFAULT")
      tables = {}
      names = []
      nil_count = 0
      packet_cache = {}
      item_types = {}
      calculated_items = {}
      needed_timestamps = {}
      current_position = 0

      items.each do |item|
        target_name, packet_name, orig_item_name, value_type, limits = item
        if orig_item_name.nil?
          names << "PACKET_TIMESECONDS as __nil#{nil_count}"
          nil_count += 1
          current_position += 1
          next
        end
        table_name = sanitize_table_name(target_name, packet_name, scope: scope)
        tables[table_name] = 1
        index = tables.find_index {|k,v| k == table_name }

        if STORED_TIMESTAMP_ITEMS.include?(orig_item_name)
          names << "\"T#{index}.#{orig_item_name}\""
          current_position += 1
          next
        end

        if TIMESTAMP_ITEMS.key?(orig_item_name)
          ts_info = TIMESTAMP_ITEMS[orig_item_name]
          calculated_items[current_position] = {
            source: ts_info[:source],
            format: ts_info[:format],
            table_index: index
          }
          needed_timestamps[index] ||= Set.new
          needed_timestamps[index] << ts_info[:source]
          current_position += 1
          next
        end

        safe_item_name = sanitize_column_name(orig_item_name)

        cache_key = [target_name, packet_name]
        unless packet_cache.key?(cache_key)
          packet_cache[cache_key] = fetch_packet_def(target_name, packet_name, scope: scope)
        end

        packet_def = packet_cache[cache_key]
        item_def = find_item_def(packet_def, orig_item_name)

        suffix = column_suffix_for_value_type(value_type)
        col_name = "T#{index}.#{safe_item_name}#{suffix}"
        names << "\"#{col_name}\""
        item_types[col_name] = resolve_item_type(item_def, value_type)
        current_position += 1
        if limits
          names << "\"T#{index}.#{safe_item_name}__L\""
        end
      end

      # Add needed timestamp columns to the SELECT for calculated items
      needed_timestamps.each do |table_index, ts_columns|
        ts_columns.each do |ts_col|
          names << "T#{table_index}.#{ts_col} as T#{table_index}___ts_#{ts_col}"
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
      query_params = []
      if start_time && !end_time
        query += "WHERE T0.PACKET_TIMESECONDS < $1 LIMIT -1"
        query_params << start_time
      elsif start_time && end_time
        query += "WHERE T0.PACKET_TIMESECONDS >= $1 AND T0.PACKET_TIMESECONDS < $2"
        query_params << start_time
        query_params << end_time
      end

      result = query_with_retry(query, params: query_params, label: "tsdb_lookup")
      if result.nil? or result.ntuples == 0
        return {}
      end

      data = []
      result.each_with_index do |tuples, row_num|
        data[row_num] ||= []
        row_index = 0
        row_timestamps = {}
        tuples.each do |tuple|
          col_name = tuple[0]
          col_value = tuple[1]
          if col_name.include?("__L")
            data[row_num][row_index - 1][1] = col_value
          elsif col_name =~ /^__nil/
            data[row_num][row_index] = [nil, nil]
            row_index += 1
          elsif col_name =~ /^T(\d+)___ts_(.+)$/
            table_idx = $1.to_i
            ts_source = $2
            row_timestamps["T#{table_idx}.#{ts_source}"] = col_value
          elsif col_name.end_with?('.PACKET_TIMESECONDS', '.RECEIVED_TIMESECONDS') || col_name == 'PACKET_TIMESECONDS' || col_name == 'RECEIVED_TIMESECONDS'
            ts_utc = coerce_to_utc(col_value)
            seconds_value = format_timestamp(ts_utc, :seconds)
            data[row_num][row_index] = [seconds_value, nil]
            row_index += 1
            if col_name.include?('.')
              row_timestamps[col_name] = col_value
            else
              row_timestamps["T0.#{col_name}"] = col_value
            end
          else
            type_info = item_types[col_name]
            unless type_info
              tables.length.times do |i|
                prefixed_name = "T#{i}.#{col_name}"
                type_info = item_types[prefixed_name]
                break if type_info
              end
              type_info ||= {}
            end
            decoded_value = decode_value(
              col_value,
              data_type: type_info['data_type'],
              array_size: type_info['array_size']
            )
            data[row_num][row_index] = [decoded_value, nil]
            row_index += 1
          end
        end

        calculated_items.keys.sort.each do |position|
          calc_info = calculated_items[position]
          ts_key = "T#{calc_info[:table_index]}.#{calc_info[:source]}"
          ts_value = row_timestamps[ts_key]
          ts_utc = coerce_to_utc(ts_value)
          calculated_value = format_timestamp(ts_utc, calc_info[:format])
          data[row_num].insert(position, [calculated_value, nil])
        end
      end
      if result.ntuples == 1
        data = data[0]
      end
      data
    end
  end
end
