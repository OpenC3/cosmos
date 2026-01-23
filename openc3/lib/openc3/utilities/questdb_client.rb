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
    # - Binary data (BLOCK) is base64-encoded (requires block_encoded hint)
    #
    # @param value [Object] The value to decode
    # @param block_encoded [Boolean] If true, treat string as base64-encoded binary
    # @return [Object] The decoded value
    def self.decode_value(value, block_encoded: false)
      # Non-strings don't need decoding (already handled by PG type mapping)
      return value unless value.is_a?(String)

      # Empty strings stay as empty strings
      return value if value.empty?

      # Handle base64-encoded binary data (BLOCK type items)
      if block_encoded
        begin
          return Base64.strict_decode64(value)
        rescue ArgumentError
          # Not valid base64, return as-is
          return value
        end
      end

      # Try to decode JSON arrays and objects
      first_char = value[0]
      if first_char == '[' || first_char == '{'
        begin
          return JSON.parse(value, allow_nan: true, create_additions: true)
        rescue JSON::ParserError
          # Not valid JSON, return as-is
          return value
        end
      end

      # Return plain strings as-is
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
    def self.sanitize_column_name(item_name)
      item_name.to_s.gsub(/[?\.,'"\\\/:\)\(\+\-\*\%~;]/, '_')
    end
  end
end
