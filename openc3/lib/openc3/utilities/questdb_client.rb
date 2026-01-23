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

      # DERIVED items are JSON-encoded (could be any type)
      if data_type == 'DERIVED'
        begin
          return JSON.parse(value, allow_nan: true, create_additions: true)
        rescue JSON::ParserError
          # Could be a plain string from DERIVED
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
        elsif first_char == '-' || first_char =~ /\d/
          if value =~ /\A-?\d+\z/
            begin
              return Integer(value)
            rescue ArgumentError
              # Not a valid integer
            end
          end
        end
      end

      # Return as-is (STRING type or unknown)
      value
    end

    # Decode all values in a hash retrieved from QuestDB.
    #
    # @param hash [Hash] Hash of column_name => value
    # @param block_columns [Array<String>] List of column names that contain base64-encoded data
    # @return [Hash] Hash with decoded values
    def self.decode_hash(hash, block_columns: [])
      return hash unless hash.is_a?(Hash)

      decoded = {}
      hash.each do |key, value|
        block_encoded = block_columns.include?(key.to_s)
        decoded[key] = decode_value(value, block_encoded: block_encoded)
      end
      decoded
    end

    # Sanitize a table name for QuestDB.
    # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
    #
    # @param target_name [String] Target name
    # @param packet_name [String] Packet name
    # @return [String] Sanitized table name
    def self.sanitize_table_name(target_name, packet_name)
      "#{target_name}__#{packet_name}".gsub(/[?,'"\\\/:\)\(\+\*\%~]/, '_')
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
  end
end
