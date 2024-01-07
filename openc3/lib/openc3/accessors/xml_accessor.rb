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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'nokogiri'
require 'openc3/accessors/accessor'

module OpenC3
  class XmlAccessor < Accessor
    def self.read_item(item, buffer)
      return nil if item.data_type == :DERIVED
      doc = buffer_to_doc(buffer)
      return convert_to_type(doc.xpath(item.key).first.to_s, item)
    end

    def self.write_item(item, value, buffer)
      return nil if item.data_type == :DERIVED
      doc = buffer_to_doc(buffer)
      node = doc.xpath(item.key).first
      node.content = value.to_s
      buffer.replace(doc_to_buffer(doc))
      return value
    end

    def self.read_items(items, buffer)
      doc = buffer_to_doc(buffer)
      result = {}
      items.each do |item|
        if item.data_type == :DERIVED
          result[item.name] = nil
        else
          result[item.name] = convert_to_type(doc.xpath(item.key).first.to_s, item)
        end
      end
      return result
    end

    def self.write_items(items, values, buffer)
      doc = buffer_to_doc(buffer)
      items.each_with_index do |item, index|
        next if item.data_type == :DERIVED
        node = doc.xpath(item.key).first
        node.content = values[index].to_s
      end
      buffer.replace(doc_to_buffer(doc))
      return values
    end

    def self.buffer_to_doc(buffer)
      Nokogiri.XML(buffer)
    end

    def self.doc_to_buffer(doc)
      doc.to_xml
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