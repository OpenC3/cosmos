# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'json'
require 'base64'
require 'bigdecimal'

module OpenC3
  # Utility class for QuestDB data encoding and decoding.
  # This provides a common interface for serializing/deserializing COSMOS data types
  # when writing to and reading from QuestDB.
  class QuestDBClient
    # Special timestamp items that are calculated from PACKET_TIMESECONDS/RECEIVED_TIMESECONDS columns
    # rather than stored as separate columns. PACKET_TIMESECONDS and RECEIVED_TIMESECONDS are stored
    # as timestamp_ns columns and need conversion to float seconds on read. The TIMEFORMATTED items
    # are derived from these timestamp columns.
    TIMESTAMP_ITEMS = {
      'PACKET_TIMEFORMATTED' => { source: 'PACKET_TIMESECONDS', format: :formatted },
      'RECEIVED_TIMEFORMATTED' => { source: 'RECEIVED_TIMESECONDS', format: :formatted }
    }.freeze

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
    # @return [String] Sanitized table name
    def self.sanitize_table_name(target_name, packet_name, cmd_or_tlm = "TLM")
      "#{cmd_or_tlm}__#{target_name}__#{packet_name}".gsub(/[?,'"\\\/:\)\(\+\*\%~]/, '_')
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

    # Get the column suffix for a given value type.
    # Used when building SQL queries to select the appropriate column.
    #
    # @param value_type [String] Value type: 'RAW', 'CONVERTED', 'FORMATTED'
    # @return [String, nil] Column suffix ('__C', '__F') or nil for RAW
    def self.column_suffix_for_value_type(value_type)
      case value_type
      when 'FORMATTED'
        '__F'
      when 'CONVERTED'
        '__C'
      else
        nil
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
  end
end
