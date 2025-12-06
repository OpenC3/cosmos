# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

      it "leaves FLOAT values unchanged" do
        item = OpenStruct.new
        item.data_type = :FLOAT
        expect(Accessor.convert_to_type(3.14, item)).to eql 3.14
        expect(Accessor.convert_to_type(0.0, item)).to eql 0.0
      end
    end
  end
end
