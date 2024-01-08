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

require 'spec_helper'
require 'openc3'
require 'openc3/accessors/template_accessor'
require 'openc3/packets/packet'

module OpenC3
  describe TemplateAccessor do
    before(:each) do
      @packet = Packet.new
      @packet.template = 'MEAS:VOLT (@<CHANNEL>); SOMETHING ELSE <MYVALUE>;'
      @data = 'MEAS:VOLT (@2); SOMETHING ELSE 5.67;'

      @packet2 = Packet.new
      @packet2.template = 'MEAS:VOLT <@(CHANNEL)>; SOMETHING ELSE (MYVALUE);'
      @data2 = 'MEAS:VOLT <@2>; SOMETHING ELSE 5.67;'
    end

    describe "read_item and read_items" do
      it "should read values" do
        accessor = TemplateAccessor.new(@packet)
        @packet.buffer = @data

        item1 = OpenStruct.new
        item1.name = 'CHANNEL'
        item1.key = 'CHANNEL'
        item1.data_type = :UINT
        value = accessor.read_item(item1, @packet.buffer(false))
        expect(value).to eq 2

        item2 = OpenStruct.new
        item2.name = 'MYVALUE'
        item2.key = 'MYVALUE'
        item2.data_type = :FLOAT
        value = accessor.read_item(item2, @packet.buffer(false))
        expect(value).to be_within(0.01).of(5.67)

        values = accessor.read_items([item1, item2], @packet.buffer(false))
        expect(values['CHANNEL']).to eq 2
        expect(values['MYVALUE']).to be_within(0.01).of(5.67)

        accessor = TemplateAccessor.new(@packet2, '(', ')')
        @packet2.buffer = @data2

        value = accessor.read_item(item1, @packet2.buffer(false))
        expect(value).to eq 2

        value = accessor.read_item(item2, @packet2.buffer(false))
        expect(value).to be_within(0.01).of(5.67)

        values = accessor.read_items([item1, item2], @packet2.buffer(false))
        expect(values['CHANNEL']).to eq 2
        expect(values['MYVALUE']).to be_within(0.01).of(5.67)
      end
    end

    describe "write_item and write_items" do
      it "should write values" do
        accessor = TemplateAccessor.new(@packet)
        @packet.restore_defaults

        item1 = OpenStruct.new
        item1.name = 'CHANNEL'
        item1.key = 'CHANNEL'
        item1.data_type = :UINT
        value = accessor.write_item(item1, 3, @packet.buffer(false))
        expect(value).to eq 3
        expect(@packet.buffer).to eq 'MEAS:VOLT (@3); SOMETHING ELSE <MYVALUE>;'

        item2 = OpenStruct.new
        item2.name = 'MYVALUE'
        item2.key = 'MYVALUE'
        item2.data_type = :FLOAT
        value = accessor.write_item(item2, 1.234, @packet.buffer(false))
        expect(value).to be_within(0.01).of(1.234)
        expect(@packet.buffer).to eq 'MEAS:VOLT (@3); SOMETHING ELSE 1.234;'

        @packet.restore_defaults
        accessor.write_items([item1, item2], [4, 2.345], @packet.buffer(false))
        values = accessor.read_items([item1, item2], @packet.buffer(false))
        expect(values['CHANNEL']).to eq 4
        expect(values['MYVALUE']).to be_within(0.01).of(2.345)

        accessor = TemplateAccessor.new(@packet2, '(', ')')
        @packet2.restore_defaults

        value = accessor.write_item(item1, 3, @packet2.buffer(false))
        expect(value).to eq 3
        expect(@packet2.buffer).to eq 'MEAS:VOLT <@3>; SOMETHING ELSE (MYVALUE);'

        value = accessor.write_item(item2, 1.234, @packet2.buffer(false))
        expect(value).to be_within(0.01).of(1.234)
        expect(@packet2.buffer).to eq 'MEAS:VOLT <@3>; SOMETHING ELSE 1.234;'

        @packet2.restore_defaults
        accessor.write_items([item1, item2], [4, 2.345], @packet2.buffer(false))
        values = accessor.read_items([item1, item2], @packet2.buffer(false))
        expect(values['CHANNEL']).to eq 4
        expect(values['MYVALUE']).to be_within(0.01).of(2.345)
      end
    end
  end
end
