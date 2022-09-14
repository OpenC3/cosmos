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

require 'spec_helper'
require 'openc3'
require 'openc3/accessors/html_accessor'

module OpenC3
  describe HtmlAccessor do
    before(:each) do
      @data1 = '<!DOCTYPE html><html lang="en"><head><title>My Title</title><script src="test.js"></script></head><body><noscript>No Script Detected</noscript><img src="test.jpg" alt="An Image"/><p>Paragraph</p><ul><li>1</li><li>3.14</li></ul></body></html>'
    end

    describe "read_item" do

      it "should handle various keys" do
        item = OpenStruct.new
        item.key = '/html/head/script/@src'
        item.data_type = :STRING
        expect(HtmlAccessor.read_item(item, @data1)).to eq "test.js"

        item = OpenStruct.new
        item.key = '/html/body/noscript/text()'
        item.data_type = :STRING
        expect(HtmlAccessor.read_item(item, @data1)).to eq "No Script Detected"

        item = OpenStruct.new
        item.key = '/html/body/img/@src'
        item.data_type = :STRING
        expect(HtmlAccessor.read_item(item, @data1)).to eq "test.jpg"

        item = OpenStruct.new
        item.key = '/html/body/ul/li[1]/text()'
        item.data_type = :UINT
        expect(HtmlAccessor.read_item(item, @data1)).to eq 1

        item = OpenStruct.new
        item.key = '/html/body/ul/li[2]/text()'
        item.data_type = :FLOAT
        expect(HtmlAccessor.read_item(item, @data1)).to eq 3.14
      end
    end

    describe "read_items" do
      it "should read a collection of items" do
        item1 = OpenStruct.new
        item1.name = 'ITEM1'
        item1.key = '/html/head/script/@src'
        item1.data_type = :STRING
        item2 = OpenStruct.new
        item2.name = 'ITEM2'
        item2.key = '/html/body/noscript/text()'
        item2.data_type = :STRING
        item3 = OpenStruct.new
        item3.name = 'ITEM3'
        item3.key = '/html/body/img/@src'
        item3.data_type = :STRING
        item4 = OpenStruct.new
        item4.name = 'ITEM4'
        item4.key = '/html/body/ul/li[1]/text()'
        item4.data_type = :UINT
        item5 = OpenStruct.new
        item5.name = 'ITEM5'
        item5.key = '/html/body/ul/li[2]/text()'
        item5.data_type = :FLOAT

        items = [item1, item2, item3, item4, item5]

        results = HtmlAccessor.read_items(items, @data1)
        expect(results['ITEM1']).to eq "test.js"
        expect(results['ITEM2']).to eq "No Script Detected"
        expect(results['ITEM3']).to eq "test.jpg"
        expect(results['ITEM4']).to eq 1
        expect(results['ITEM5']).to eq 3.14
      end
    end

    describe "write_item" do
      it "should write different types" do
        item = OpenStruct.new
        item.key = '/html/head/script/@src'
        item.data_type = :STRING
        HtmlAccessor.write_item(item, "different.js", @data1)
        expect(HtmlAccessor.read_item(item, @data1)).to eq "different.js"

        item = OpenStruct.new
        item.key = '/html/body/noscript/text()'
        item.data_type = :STRING
        HtmlAccessor.write_item(item, "Nothing Here", @data1)
        expect(HtmlAccessor.read_item(item, @data1)).to eq "Nothing Here"

        item = OpenStruct.new
        item.key = '/html/body/img/@src'
        item.data_type = :STRING
        HtmlAccessor.write_item(item, "other.png", @data1)
        expect(HtmlAccessor.read_item(item, @data1)).to eq "other.png"

        item = OpenStruct.new
        item.key = '/html/body/ul/li[1]/text()'
        item.data_type = :UINT
        HtmlAccessor.write_item(item, 15, @data1)
        expect(HtmlAccessor.read_item(item, @data1)).to eq 15

        item = OpenStruct.new
        item.key = '/html/body/ul/li[2]/text()'
        item.data_type = :FLOAT
        HtmlAccessor.write_item(item, 1.234, @data1)
        expect(HtmlAccessor.read_item(item, @data1)).to eq 1.234
      end
    end

    describe "write_items" do
      it "should write multiple items" do
        item1 = OpenStruct.new
        item1.key = '/html/head/script/@src'
        item1.data_type = :STRING
        item2 = OpenStruct.new
        item2.key = '/html/body/noscript/text()'
        item2.data_type = :STRING
        item3 = OpenStruct.new
        item3.key = '/html/body/img/@src'
        item3.data_type = :STRING
        item4 = OpenStruct.new
        item4.key = '/html/body/ul/li[1]/text()'
        item4.data_type = :UINT
        item5 = OpenStruct.new
        item5.key = '/html/body/ul/li[2]/text()'
        item5.data_type = :FLOAT

        items = [item1, item2, item3, item4, item5]
        values = ["different.js", "Nothing Here", "other.png", 15, 1.234]
        HtmlAccessor.write_items(items, values, @data1)

        expect(HtmlAccessor.read_item(item1, @data1)).to eq "different.js"
        expect(HtmlAccessor.read_item(item2, @data1)).to eq "Nothing Here"
        expect(HtmlAccessor.read_item(item3, @data1)).to eq "other.png"
        expect(HtmlAccessor.read_item(item4, @data1)).to eq 15
        expect(HtmlAccessor.read_item(item5, @data1)).to eq 1.234
      end
    end
  end
end
