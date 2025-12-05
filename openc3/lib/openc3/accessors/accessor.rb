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

module OpenC3
  class Accessor
    attr_accessor :packet

    def initialize(packet = nil)
      @packet = packet
      @args = []
    end

    def read_item(item, buffer)
      if item.parent_item
        # Structure is used to read items with parent, not accessor
        structure_buffer = read_item(item.parent_item, buffer)
        structure = item.parent_item.structure
        structure.read(item.key, :RAW, structure_buffer)
      else
        self.class.read_item(item, buffer)
      end
    end

    def write_item(item, value, buffer)
      if item.parent_item
        # Structure is used to write items with parent, not accessor
        structure_buffer = read_item(item.parent_item, buffer)
        structure = item.parent_item.structure
        structure.write(item.key, value, :RAW, structure_buffer)
        self.class.write_item(item.parent_item, structure_buffer, buffer)
      else
        self.class.write_item(item, value, buffer)
      end
    end

    def read_items(items, buffer)
      result = {}
      items.each do |item|
        result[item.name] = read_item(item, buffer)
      end
      return result
    end

    def write_items(items, values, buffer)
      items.each_with_index do |item, index|
        write_item(item, values[index], buffer)
      end
      return values
    end

    def args
      return @args
    end

    # If this is set it will enforce that buffer data is encoded
    # in a specific encoding
    def enforce_encoding
      return 'ASCII-8BIT'.freeze
    end

    # This affects whether the Packet class enforces the buffer
    # length at all.  Set to false to remove any correlation between
    # buffer length and defined sizes of items in COSMOS
    def enforce_length
      return true
    end

    # This sets the short_buffer_allowed flag in the Packet class
    # which allows packets that have a buffer shorter than the defined size.
    # Note that the buffer is still resized to the defined length
    def enforce_short_buffer_allowed
      return false
    end

    # If this is true it will enforce that COSMOS DERIVED items must have a
    # write_conversion to be written
    def enforce_derived_write_conversion(_item)
      return true
    end

    def self.read_item(_item, _buffer)
      raise "Must be defined by subclass if needed"
    end

    def self.write_item(_item, _value, _buffer)
      raise "Must be defined by subclass if needed"
    end

    def self.read_items(items, buffer)
      result = {}
      items.each do |item|
        result[item.name] = read_item(item, buffer)
      end
      return result
    end

    def self.write_items(items, values, buffer)
      items.each_with_index do |item, index|
        write_item(item, values[index], buffer)
      end
      return values
    end

    def self.convert_to_type(value, item)
      return value if value.nil?
      case item.data_type
      when :OBJECT, :ARRAY
        # Do nothing for complex object types
      when :STRING, :BLOCK
        if item.array_size
          value = JSON.parse(value) if value.is_a? String
          value =  value.map { |v| v.to_s }
        else
          value = value.to_s
        end
      when :UINT, :INT
        if item.array_size
          value = JSON.parse(value) if value.is_a? String
          value = value.map { |v| Integer(v) }
        else
          value = Integer(value)
        end
      when :FLOAT
        if item.array_size
          value = JSON.parse(value) if value.is_a? String
          value = value.map { |v| Float(v) }
        else
          value = Float(value)
        end
      else
        raise(ArgumentError, "data_type #{item.data_type} is not recognized")
      end
      return value
    end
  end
end
