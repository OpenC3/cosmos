# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3'
require 'openc3/accessors/accessor'

module OpenC3
  describe Accessor do
    describe "convert_to_type" do
      it "returns nil for nil values" do
        item = OpenStruct.new
        item.data_type = :INT
        expect(Accessor.convert_to_type(nil, item)).to be_nil
      end

      it "converts BOOL values from strings" do
        item = OpenStruct.new
        item.data_type = :BOOL
        expect(Accessor.convert_to_type("true", item)).to eql true
        expect(Accessor.convert_to_type("TRUE", item)).to eql true
        expect(Accessor.convert_to_type("false", item)).to eql false
        expect(Accessor.convert_to_type("FALSE", item)).to eql false
        expect(Accessor.convert_to_type(true, item)).to eql true
        expect(Accessor.convert_to_type(false, item)).to eql false
      end

      it "converts ARRAY values from strings" do
        item = OpenStruct.new
        item.data_type = :ARRAY
        expect(Accessor.convert_to_type('[1, 2, 3]', item)).to eql [1, 2, 3]
        expect(Accessor.convert_to_type('["a", "b", "c"]', item)).to eql ["a", "b", "c"]
        expect(Accessor.convert_to_type([1, 2, 3], item)).to eql [1, 2, 3]
      end

      it "converts OBJECT values from strings" do
        item = OpenStruct.new
        item.data_type = :OBJECT
        expect(Accessor.convert_to_type('{"key": "value"}', item)).to eql({"key" => "value"})
        expect(Accessor.convert_to_type('{"num": 123}', item)).to eql({"num" => 123})
        expect(Accessor.convert_to_type({"key" => "value"}, item)).to eql({"key" => "value"})
      end

      it "converts ANY values from strings" do
        item = OpenStruct.new
        item.data_type = :ANY
        expect(Accessor.convert_to_type('"text"', item)).to eql "text"
        expect(Accessor.convert_to_type('123', item)).to eql 123
        expect(Accessor.convert_to_type('[1, 2, 3]', item)).to eql [1, 2, 3]
        expect(Accessor.convert_to_type('{"key": "value"}', item)).to eql({"key" => "value"})
        expect(Accessor.convert_to_type('invalid json', item)).to eql "invalid json"
        expect(Accessor.convert_to_type(123, item)).to eql 123
        expect(Accessor.convert_to_type([1, 2, 3], item)).to eql [1, 2, 3]
      end

      it "converts STRING values with array_size from strings" do
        item = OpenStruct.new
        item.data_type = :STRING
        item.array_size = 10
        expect(Accessor.convert_to_type('["a", "b"]', item)).to eql ["a", "b"]
      end

      it "leaves STRING values without array_size unchanged" do
        item = OpenStruct.new
        item.data_type = :STRING
        item.array_size = nil
        expect(Accessor.convert_to_type('test', item)).to eql "test"
        expect(Accessor.convert_to_type('["a", "b"]', item)).to eql '["a", "b"]'
      end

      it "leaves BLOCK values unchanged" do
        item = OpenStruct.new
        item.data_type = :BLOCK
        item.array_size = nil
        expect(Accessor.convert_to_type("\x01\x02\x03", item)).to eql "\x01\x02\x03"
        expect(Accessor.convert_to_type('test', item)).to eql "test"
      end

      it "leaves INT values unchanged" do
        item = OpenStruct.new
        item.data_type = :INT
        expect(Accessor.convert_to_type(42, item)).to eql 42
        expect(Accessor.convert_to_type(-10, item)).to eql(-10)
      end

      it "leaves UINT values unchanged" do
        item = OpenStruct.new
        item.data_type = :UINT
        expect(Accessor.convert_to_type(42, item)).to eql 42
        expect(Accessor.convert_to_type(0, item)).to eql 0
      end

      # Python's accessor.py matches these cases, keep the two in sync
      it "preserves large INT and UINT values" do
        item = OpenStruct.new
        { INT: [-(2**63), -((2**53) + 1), (2**53) + 1, (2**63) - 1],
          UINT: [(2**53) + 1, (2**63) - 1, (2**64) - 1] }.each do |data_type, values|
          item.data_type = data_type
          values.each do |value|
            item.array_size = nil
            zero_padded = value.negative? ? "-000#{-value}" : "000#{value}"
            [value, value.to_s, "  #{value}\n", zero_padded, BigDecimal(value)].each do |input|
              expect(Accessor.convert_to_type(input, item)).to eql value
            end
            item.array_size = 64
            expect(Accessor.convert_to_type([value.to_s], item)).to eql [value]
            expect(Accessor.convert_to_type("[#{value}]", item)).to eql [value]
          end
        end
      end

      it "truncates non-integer INT and UINT numbers" do
        item = OpenStruct.new
        item.data_type = :INT
        item.array_size = nil
        expect(Accessor.convert_to_type(3.7, item)).to eql 3
        expect(Accessor.convert_to_type(-3.7, item)).to eql(-3)
        expect(Accessor.convert_to_type(BigDecimal("3.7"), item)).to eql 3
        expect(Accessor.convert_to_type(BigDecimal("18446744073709551615.9"), item)).to eql((2**64) - 1)
        expect(Accessor.convert_to_type(Rational(7, 2), item)).to eql 3
        expect { Accessor.convert_to_type(Float::NAN, item) }.to raise_error(FloatDomainError)
        expect { Accessor.convert_to_type(Float::INFINITY, item) }.to raise_error(FloatDomainError)
      end

      it "parses INT and UINT strings as integer literals" do
        item = OpenStruct.new
        cases = { "0" => 0, "-0" => 0, "+10" => 10, " -10\n" => -10, "1_000" => 1000,
                  "0x10" => 16, "-0X1f" => -31, "0x1_F" => 31, "0b101" => 5, "0B1_0" => 2,
                  "0o17" => 15, "010" => 10, "-010" => -10, "0_10" => 10, "08" => 8,
                  "0089" => 89, "-007" => -7, "\n0042\t" => 42, "0x010" => 16, "00" => 0,
                  "0d10" => 10, "0D09" => 9 }
        %i(INT UINT).each do |data_type|
          item.data_type = data_type
          cases.each do |input, expected|
            item.array_size = nil
            expect(Accessor.convert_to_type(input, item)).to eql expected
            item.array_size = 64
            expect(Accessor.convert_to_type([input], item)).to eql [expected]
          end
        end
      end

      it "rejects INT and UINT strings that are not integer literals" do
        item = OpenStruct.new
        cases = ["3.7", "-3.7", "1.0", "1e3", "0o8", "00x10", "0b2", "0xg", "0x", "0x_10", "0__10",
                 "1__000", "_1", "1_", "- 10", "--10", "1 0", "", "   ", "invalid", " 10"]
        %i(INT UINT).each do |data_type|
          item.data_type = data_type
          cases.each do |input|
            item.array_size = nil
            expect { Accessor.convert_to_type(input, item) }.to raise_error(ArgumentError)
            item.array_size = 64
            expect { Accessor.convert_to_type([input], item) }.to raise_error(ArgumentError)
          end
        end
      end

      it "leaves FLOAT values unchanged" do
        item = OpenStruct.new
        item.data_type = :FLOAT
        expect(Accessor.convert_to_type(3.14, item)).to eql 3.14
        expect(Accessor.convert_to_type(0.0, item)).to eql 0.0
      end
    end
  end
end
