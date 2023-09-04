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
  end
end
