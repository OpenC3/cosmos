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
    end

    def self.buffer_to_doc(buffer)
      Nokogiri.XML(buffer)
    end

    def self.doc_to_buffer(doc)
      doc.to_xml
    end

  end
end