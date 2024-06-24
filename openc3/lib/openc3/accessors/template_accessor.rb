# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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

require 'openc3/accessors/accessor'

module OpenC3
  class TemplateAccessor < Accessor
    def initialize(packet, left_char = '<', right_char = '>')
      super(packet)
      @left_char = left_char
      @right_char = right_char
      @configured = false
    end

    def configure
      return if @configured

      escaped_left_char = @left_char
      escaped_left_char = "\\#{@left_char}" if @left_char == '('
      escaped_right_char = @right_char
      escaped_right_char = "\\#{@right_char}" if @right_char == ')'

      # Convert the template into a Regexp for reading each item
      template = @packet.template.dup
      template_items = template.scan(Regexp.new("#{escaped_left_char}.*?#{escaped_right_char}"))
      escaped_read_template = template
      if @left_char != '('
        escaped_read_template = escaped_read_template.gsub('(', '\(')
      end
      if @right_char != ')'
        escaped_read_template = escaped_read_template.gsub(')', '\)')
      end

      @item_keys = []
      template_items.each do |item|
        @item_keys << item[1..-2]
        escaped_read_template.gsub!(item, "(.*)")
      end
      @read_regexp = Regexp.new(escaped_read_template)

      @configured = true
    end

    def read_item(item, buffer)
      return nil if item.data_type == :DERIVED
      configure()

      # Scan the response for all the variables in brackets <VARIABLE>
      values = buffer.scan(@read_regexp)[0]
      if !values || (values.length != @item_keys.length)
        raise "Unexpected number of items found in buffer: #{values ? values.length : 0}, Expected: #{@item_keys.length}"
      else
        values.each_with_index do |value, i|
          item_key = @item_keys[i]
          if item_key == item.key
            return Accessor.convert_to_type(value, item)
          end
        end
      end

      raise "Response does not include key #{item.key}: #{buffer}"
    end

    def read_items(items, buffer)
      result = {}
      configure()

      # Scan the response for all the variables in brackets <VARIABLE>
      values = buffer.scan(@read_regexp)[0]
      if !values || (values.length != @item_keys.length)
        raise "Unexpected number of items found in buffer: #{values ? values.length : 0}, Expected: #{@item_keys.length}"
      else
        items.each do |item|
          if item.data_type == :DERIVED
            result[item.name] = nil
            next
          end
          index = @item_keys.index(item.key)
          if index
            result[item.name] = Accessor.convert_to_type(values[index], item)
          else
            raise "Unknown item with key #{item.key} requested"
          end
        end
      end

      return result
    end

    def write_item(item, value, buffer)
      return nil if item.data_type == :DERIVED
      configure()

      success = buffer.gsub!("#{@left_char}#{item.key}#{@right_char}", value.to_s)
      raise "Key #{item.key} not found in template" unless success
      return value
    end

    def write_items(items, values, buffer)
      configure()
      items.each_with_index do |item, index|
        next if item.data_type == :DERIVED
        success = buffer.gsub!("#{@left_char}#{item.key}#{@right_char}", values[index].to_s)
        raise "Key #{item.key} not found in template" unless success
      end
      return values
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

    # If this is true it will enfore that COSMOS DERIVED items must have a
    # write_conversion to be written
    def enforce_derived_write_conversion(_item)
      return true
    end
  end
end