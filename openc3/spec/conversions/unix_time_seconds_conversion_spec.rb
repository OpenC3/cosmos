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
require 'openc3/conversions/unix_time_seconds_conversion'
require 'openc3/packets/packet'

module OpenC3
  describe UnixTimeSecondsConversion do
    describe "initialize" do
      it "initializes converted_type and converted_bit_size" do
        utsc = UnixTimeSecondsConversion.new('TIME')
        expect(utsc.converted_type).to eql :FLOAT
        expect(utsc.converted_bit_size).to eql 64
      end
    end

    describe "call" do
      it "returns the formatted packet time based on seconds" do
        utsc = UnixTimeSecondsConversion.new('TIME')
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        time = Time.new(2020, 1, 31, 12, 15, 30).to_f
        packet.write("TIME", time)
        expect(utsc.call(nil, packet, packet.buffer)).to eql time
      end

      it "returns the formatted packet time based on seconds and microseconds" do
        utsc = UnixTimeSecondsConversion.new('TIME', 'TIME_US')
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        time = Time.new(2020, 1, 31, 12, 15, 30).to_f
        packet.write("TIME", time)
        packet.append_item("TIME_US", 32, :UINT)
        packet.write("TIME_US", 500000)
        expect(utsc.call(nil, packet, packet.buffer)).to eql time + 0.5
      end

      it "complains if the seconds item doesn't exist" do
        utsc = UnixTimeSecondsConversion.new('TIME')
        packet = Packet.new("TGT", "PKT")
        expect { utsc.call(nil, packet, packet.buffer) }.to raise_error("Packet item 'TGT PKT TIME' does not exist")
      end

      it "complains if the microseconds item doesn't exist" do
        utsc = UnixTimeSecondsConversion.new('TIME', 'TIME_US')
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        expect { utsc.call(nil, packet, packet.buffer) }.to raise_error("Packet item 'TGT PKT TIME_US' does not exist")
      end
    end

    describe "to_s" do
      it "returns the seconds conversion" do
        utsc = UnixTimeSecondsConversion.new('TIME')
        expect(utsc.to_s).to eql "Time.at(packet.read('TIME', :RAW, buffer), 0).sys.to_f"
      end

      it "returns the microseconds conversion" do
        utsc = UnixTimeSecondsConversion.new('TIME', 'TIME_US')
        expect(utsc.to_s).to eql "Time.at(packet.read('TIME', :RAW, buffer), packet.read('TIME_US', :RAW, buffer)).sys.to_f"
      end
    end

    describe "to_json" do
      it "creates a reproducible format" do
        utsc = UnixTimeSecondsConversion.new('TIME', 'TIME_US')
        json = utsc.as_json()
        expect(json['class']).to eql "OpenC3::UnixTimeSecondsConversion"
        expect(json['converted_type']).to eql :FLOAT
        expect(json['converted_bit_size']).to eql 64
        packet = Packet.new("TGT", "PKT")
        packet.append_item("TIME", 32, :UINT)
        time = Time.new(2020, 1, 31, 12, 15, 30).to_f
        packet.write("TIME", time)
        packet.append_item("TIME_US", 32, :UINT)
        packet.write("TIME_US", 500000)
        new_utsc = OpenC3.const_get(json['class']).new(*json['params'])
        expect(utsc.call(nil, packet, packet.buffer)).to eql new_utsc.call(nil, packet, packet.buffer)
      end
    end
  end
end
