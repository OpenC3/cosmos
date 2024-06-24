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

require 'openc3/accessors/accessor'

module OpenC3
  class HttpAccessor < Accessor
    def initialize(packet, body_accessor = 'FormAccessor', *body_accessor_args)
      super(packet)
      @args << body_accessor
      body_accessor_args.each do |arg|
        @args << arg
      end
      klass = OpenC3.require_class(body_accessor)
      @body_accessor = klass.new(packet, *body_accessor_args)
    end

    def read_item(item, buffer)
      item_name = item.name
      case item_name
      when 'HTTP_STATUS'
        return nil unless @packet.extra
        return @packet.extra['HTTP_STATUS']
      when 'HTTP_PATH'
        return nil unless @packet.extra
        return @packet.extra['HTTP_PATH']
      when 'HTTP_METHOD'
        return nil unless @packet.extra
        return @packet.extra['HTTP_METHOD']
      when 'HTTP_PACKET'
        return nil unless @packet.extra
        return @packet.extra['HTTP_PACKET']
      when 'HTTP_ERROR_PACKET'
        return nil unless @packet.extra
        return @packet.extra['HTTP_ERROR_PACKET']
      when /^HTTP_QUERY_/
        return nil unless @packet.extra
        if item.key
          query_name = item.key
        else
          query_name = item_name[11..-1]
        end
        queries = @packet.extra['HTTP_QUERIES']
        if queries
          return queries[query_name]
        else
          return nil
        end
      when /^HTTP_HEADER_/
        return nil unless @packet.extra
        if item.key
          header_name = item.key
        else
          header_name = item_name[12..-1]
        end
        headers = @packet.extra['HTTP_HEADERS']
        if headers
          return headers[header_name]
        else
          return nil
        end
      else
        return @body_accessor.read_item(item, buffer)
      end
    end

    def write_item(item, value, buffer)
      item_name = item.name
      case item_name
      when 'HTTP_STATUS'
        @packet.extra ||= {}
        @packet.extra['HTTP_STATUS'] = value.to_i
      when 'HTTP_PATH'
        @packet.extra ||= {}
        @packet.extra['HTTP_PATH'] = value.to_s
      when 'HTTP_METHOD'
        @packet.extra ||= {}
        @packet.extra['HTTP_METHOD'] = value.to_s.downcase
      when 'HTTP_PACKET'
        @packet.extra ||= {}
        @packet.extra['HTTP_PACKET'] = value.to_s.upcase
      when 'HTTP_ERROR_PACKET'
        @packet.extra ||= {}
        @packet.extra['HTTP_ERROR_PACKET'] = value.to_s.upcase
      when /^HTTP_QUERY_/
        @packet.extra ||= {}
        if item.key
          query_name = item.key
        else
          query_name = item_name[11..-1]
        end
        queries = @packet.extra['HTTP_QUERIES'] ||= {}
        queries[query_name] = value.to_s
      when /^HTTP_HEADER_/
        @packet.extra ||= {}
        if item.key
          header_name = item.key
        else
          header_name = item_name[12..-1]
        end
        headers = @packet.extra['HTTP_HEADERS'] ||= {}
        headers[header_name] = value.to_s
      else
        @body_accessor.write_item(item, value, buffer)
      end
      return value
    end

    def read_items(items, buffer)
      result = {}
      body_items = []
      items.each do |item|
        if item.name[0..4] == 'HTTP_'
          result[item.name] = read_item(item, buffer)
        else
          body_items << item
        end
      end
      body_result = @body_accessor.read_items(body_items, buffer)
      result.merge!(body_result) # Merge Body accessor read items with HTTP_ items
      return result
    end

    def write_items(items, values, buffer)
      body_items = []
      items.each_with_index do |item, index|
        if item.name[0..4] == 'HTTP_'
          write_item(item, values[index], buffer)
        else
          body_items << item
        end
      end
      @body_accessor.write_items(body_items, values, buffer)
      return values
    end

    # If this is set it will enforce that buffer data is encoded
    # in a specific encoding
    def enforce_encoding
      return @body_accessor.enforce_encoding
    end

    # This affects whether the Packet class enforces the buffer
    # length at all.  Set to false to remove any correlation between
    # buffer length and defined sizes of items in COSMOS
    def enforce_length
      return @body_accessor.enforce_length
    end

    # This sets the short_buffer_allowed flag in the Packet class
    # which allows packets that have a buffer shorter than the defined size.
    # Note that the buffer is still resized to the defined length
    def enforce_short_buffer_allowed
      return @body_accessor.enforce_short_buffer_allowed
    end

    # If this is true it will enfore that COSMOS DERIVED items must have a
    # write_conversion to be written
    def enforce_derived_write_conversion(item)
      case item.name
      when 'HTTP_STATUS', 'HTTP_PATH', 'HTTP_METHOD', 'HTTP_PACKET', 'HTTP_ERROR_PACKET', /^HTTP_QUERY_/, /^HTTP_HEADER_/
        return false
      else
        return @body_accessor.enforce_derived_write_conversion(item)
      end
    end
  end
end
