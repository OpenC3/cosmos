# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/conversions/unix_time_formatted_conversion'
require 'openc3/packets/packet'

module OpenC3
  describe UnixTimeFormattedConversion do
    describe "initialize" do
      it "initializes converted_type and converted_bit_size" do
        utfc = UnixTimeFormattedConversion.new('TIME')
        expect(utfc.converted_type).to eql :STRING
        expect(utfc.converted_bit_size).to eql 0
      end
    end

    describe "call" do
      it "returns the formatted packet time based on seconds" do
        utfc = UnixTimeFormattedConversion.new('TIME')
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        packet.write("TIME", Time.new(2020, 1, 31, 12, 15, 30).to_f)
        expect(utfc.call(nil, packet, packet.buffer)).to eql "2020/01/31 12:15:30.000"
      end

      it "returns the formatted packet time based on seconds and microseconds" do
        utfc = UnixTimeFormattedConversion.new('TIME', 'TIME_US')
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        packet.write("TIME", Time.new(2020, 1, 31, 12, 15, 30).to_f)
        packet.append_item("TIME_US", 32, :UINT)
        packet.write("TIME_US", 500000)
        expect(utfc.call(nil, packet, packet.buffer)).to eql "2020/01/31 12:15:30.500"
      end

      it "complains if the seconds item doesn't exist" do
        utfc = UnixTimeFormattedConversion.new('TIME')
        packet = Packet.new("TGT", "PKT")
        expect { utfc.call(nil, packet, packet.buffer) }.to raise_error("Packet item 'TGT PKT TIME' does not exist")
      end

      it "complains if the microseconds item doesn't exist" do
        utfc = UnixTimeFormattedConversion.new('TIME', 'TIME_US')
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        expect { utfc.call(nil, packet, packet.buffer) }.to raise_error("Packet item 'TGT PKT TIME_US' does not exist")
      end
    end

    describe "to_s" do
      it "returns the seconds conversion" do
        utfc = UnixTimeFormattedConversion.new('TIME')
        expect(utfc.to_s).to eql "Time.at(packet.read('TIME', :RAW, buffer), 0).sys.formatted"
      end

      it "returns the microseconds conversion" do
        utfc = UnixTimeFormattedConversion.new('TIME', 'TIME_US')
        expect(utfc.to_s).to eql "Time.at(packet.read('TIME', :RAW, buffer), packet.read('TIME_US', :RAW, buffer)).sys.formatted"
      end
    end

    describe "to_json" do
      it "creates a reproducible format" do
        utfc = UnixTimeFormattedConversion.new('TIME', 'TIME_US')
        json = utfc.as_json()
        expect(json['class']).to eql "OpenC3::UnixTimeFormattedConversion"
        expect(json['converted_type']).to eql :STRING
        expect(json['converted_bit_size']).to eql 0
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        packet.write("TIME", Time.new(2020, 1, 31, 12, 15, 30).to_f)
        packet.append_item("TIME_US", 32, :UINT)
        packet.write("TIME_US", 500000)
        new_utfc = OpenC3.const_get(json['class']).new(*json['params'])
        expect(utfc.call(nil, packet, packet.buffer)).to eql new_utfc.call(nil, packet, packet.buffer)
      end
    end
  end
end
