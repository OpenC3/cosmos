# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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
require 'jsonpath'
require 'openc3/io/json_rpc'
require 'openc3/accessors/accessor'

# Monkey patch JsonPath to enable create_additions and allow_nan to support binary strings, and NaN, Infinity, -Infinity
OpenC3.disable_warnings do
  class JsonPath
    def self.process_object(obj_or_str, opts = {})
      obj_or_str.is_a?(String) ? MultiJson.decode(obj_or_str, max_nesting: opts[:max_nesting], create_additions: true, allow_nan: true) : obj_or_str
    end
  end
end

module OpenC3
  class JsonAccessor < Accessor
    def self.read_item(item, buffer)
      return nil if item.data_type == :DERIVED
      value = JsonPath.on(buffer, item.key).first
      return convert_to_type(value, item)
    end

    def self.write_item(item, value, buffer)
      return nil if item.data_type == :DERIVED

      # Convert to ruby objects
      if String === buffer
        decoded = JSON.parse(buffer, :allow_nan => true, :create_additions => true)
      else
        decoded = buffer
      end

      # Write the value
      write_item_internal(item, value, decoded)

      # Update buffer
      if String === buffer
        buffer.replace(JSON.generate(decoded.as_json, :allow_nan => true))
      end

      return value
    end

    def self.read_items(items, buffer)
      # Prevent JsonPath from decoding every call
      if String === buffer
        decoded = JSON.parse(buffer, :allow_nan => true, :create_additions => true)
      else
        decoded = buffer
      end
      super(items, decoded)
    end

    def self.write_items(items, values, buffer)
      # Start with an empty object if no buffer
      buffer.replace("{}") if buffer.length == 0 or buffer[0] == "\x00"

      # Convert to ruby objects
      if String === buffer
        decoded = JSON.parse(buffer, :allow_nan => true)
      else
        decoded = buffer
      end

      items.each_with_index do |item, index|
        write_item_internal(item, values[index], decoded)
      end

      # Update buffer
      if String === buffer
        buffer.replace(JSON.generate(decoded, :allow_nan => true))
      end

      return values
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
      value = convert_to_type(value, item)
      if parent_node
        parent_node[parent_key] = value
      else
        decoded.replace(value)
      end
      return decoded
    end

    # If this is set it will enforce that buffer data is encoded
    # in a specific encoding
    def enforce_encoding
      return nil
    end

    # This affects whether the Packet class enforces the buffer
    # length at all.  Set to false to remove any correlation between
    # buffer length and defined sizes of items in COSMOS
    def enforce_length
      return false
    end

    # This sets the short_buffer_allowed flag in the Packet class
    # which allows packets that have a buffer shorter than the defined size.
    # Note that the buffer is still resized to the defined length
    def enforce_short_buffer_allowed
      return true
    end

    # If this is true it will enforce that COSMOS DERIVED items must have a
    # write_conversion to be written
    def enforce_derived_write_conversion(_item)
      return true
    end
  end
end