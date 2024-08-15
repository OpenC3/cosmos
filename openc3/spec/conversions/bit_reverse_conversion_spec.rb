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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/conversions/bit_reverse_conversion'

module OpenC3
  describe BitReverseConversion do
    describe "initialize" do
      it "takes converted_type and converted_bit_size" do
        brc = BitReverseConversion.new(:UINT, 8)
        expect(brc.converted_type).to eql :UINT
        expect(brc.converted_bit_size).to eql 8
      end

      it "complains about invalid converted_type" do
        expect { BitReverseConversion.new(:FLOAT, 8) }.to raise_error("Float Bit Reverse Not Yet Supported")
      end
    end

    describe "call" do
      it "reverses the bits" do
        brc = BitReverseConversion.new(:UINT, 8)
        expect(brc.call(0x11, nil, nil)).to eql 0x88

        brc = BitReverseConversion.new(:UINT, 16)
        expect(brc.call(0x1234, nil, nil)).to eql 0x2C48

        brc = BitReverseConversion.new(:UINT, 32)
        expect(brc.call(0x87654321, nil, nil)).to eql 0x84C2A6E1
      end
    end

    describe "to_s" do
      it "returns the conversion string" do
        expect(BitReverseConversion.new(:UINT, 8).to_s).to eql "BitReverseConversion.new(:UINT, 8)"
      end
    end

    describe "to_config" do
      it "returns a read config snippet" do
        brc = BitReverseConversion.new(:UINT, 8).to_config("READ").strip()
        expect(brc).to eql "READ_CONVERSION bit_reverse_conversion.rb UINT 8"
      end
    end

    describe "as_json" do
      it "creates a reproducable format" do
        brc = BitReverseConversion.new(:UINT, 8)
        json = brc.as_json(:allow_nan => true)
        expect(json['class']).to eql "OpenC3::BitReverseConversion"
        expect(json['converted_type']).to eql :UINT
        expect(json['converted_bit_size']).to eql 8
        expect(json['converted_array_size']).to eql nil
        new_brc = OpenC3::const_get(json['class']).new(json['converted_type'], json['converted_bit_size'])
        expect(brc.converted_type).to eql(new_brc.converted_type)
        expect(brc.converted_bit_size).to eql(new_brc.converted_bit_size)
        expect(brc.converted_array_size).to eql(new_brc.converted_array_size)
        expect(brc.call(0x11, 0, 0)).to eql 0x88
        expect(new_brc.call(0x11, 0, 0)).to eql 0x88
      end
    end
  end
end
