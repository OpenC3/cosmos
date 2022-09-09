# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'json'
require 'jsonpath'
require 'openc3/accessors/accessor'

module OpenC3
  class JsonAccessor < Accessor
    def self.read_item(item, buffer)
      return nil if item.data_type == :DERIVED
      return JsonPath.on(buffer, item.key).first
    end

    def self.write_item(item, value, buffer)
      return nil if item.data_type == :DERIVED
      # Start with an empty object if no buffer
      buffer.replace("{}") if buffer.length == 0 or buffer[0] == "\x00"

      # Convert to ruby objects
      decoded = JSON.parse(buffer, :allow_nan => true)

      # Write the value
      write_item_internal(item, value, decoded)

      # Update buffer
      buffer.replace(JSON.generate(decoded, :allow_nan => true))

      return buffer
    end

    def self.read_items(items, buffer)
      # Prevent JsonPath from decoding every call
      decoded = JSON.parse(buffer)
      super(items, decoded)
    end

    def self.write_items(items, values, buffer)
      # Start with an empty object if no buffer
      buffer.replace("{}") if buffer.length == 0 or buffer[0] == "\x00"

      # Convert to ruby objects
      decoded = JSON.parse(buffer, :allow_nan => true)

      items.each_with_index do |item, index|
        write_item_internal(item, values[index], decoded)
      end

      # Update buffer
      buffer.replace(JSON.generate(decoded, :allow_nan => true))

      return buffer
    end

    def self.write_item_internal(item, value, decoded)
      return nil if item.data_type == :DERIVED

      # Save traversal state
      parent_node = nil
      parent_key = nil
      node = decoded

      # Parse the JsonPath
      json_path = JsonPath.new(item.key)

      # Handle each token
      json_path.path.each do |token|
        case token
        when '$'
          # Ignore start - it is implied
          next
        when /\[.*\]/
          # Array or Hash Index
          if token.index("'") # Hash index
            key = token[2..-3]
            if not (Hash === node)
              node = {}
              parent_node[parent_key] = node
            end
            parent_node = node
            parent_key = key
            node = node[key]
          else # Array index
            key = token[1..-2].to_i
            if not (Array === node)
              node = []
              parent_node[parent_key] = node
            end
            parent_node = node
            parent_key = key
            node = node[key]
          end
        else
          raise "Unsupported key/token: #{item.key} - #{token}"
        end
      end
      if parent_node
        parent_node[parent_key] = value
      else
        decoded.replace(value)
      end
      return decoded
    end
  end
end