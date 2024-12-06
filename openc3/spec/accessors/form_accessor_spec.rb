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
require 'openc3/accessors/form_accessor'

module OpenC3
  describe FormAccessor do
    describe "read_item" do
      it "reads the correct item from the buffer" do
        item = double("item", key: "test_key")
        buffer = "test_key=test_value&other_key=other_value"
        expect(FormAccessor.read_item(item, buffer)).to eq("test_value")
      end

      it "returns nil if the item is not found in the buffer" do
        item = double("item", key: "missing_key")
        buffer = "test_key=test_value&other_key=other_value"
        expect(FormAccessor.read_item(item, buffer)).to be_nil
      end

      it "handles empty buffer correctly" do
        item = double("item", key: "test_key")
        buffer = ""
        expect(FormAccessor.read_item(item, buffer)).to be_nil
      end

      it "handles buffer with multiple values for the same key" do
        item = double("item", key: "test_key")
        buffer = "test_key=value1&test_key=value2"
        expect(FormAccessor.read_item(item, buffer)).to eq(["value1", "value2"])
        buffer = "test_key=value1&test_key=value2&test_key=value3"
        expect(FormAccessor.read_item(item, buffer)).to eq(["value1", "value2", "value3"])
      end
    end

    describe "write_item" do
      it "writes a single value to the buffer" do
        item = double("item", key: "test_key")
        buffer = "other_key=other_value"
        FormAccessor.write_item(item, "test_value", buffer)
        expect(buffer).to eq("other_key=other_value&test_key=test_value")
      end

      it "writes multiple values to the buffer" do
        item = double("item", key: "test_key")
        buffer = "other_key=other_value"
        FormAccessor.write_item(item, ["value1", "value2"], buffer)
        expect(buffer).to eq("other_key=other_value&test_key=value1&test_key=value2")
        FormAccessor.write_item(item, ["value1", "value2", "value3"], buffer)
        expect(buffer).to eq("other_key=other_value&test_key=value1&test_key=value2&test_key=value3")
      end

      it "replaces existing item in the buffer" do
        item = double("item", key: "test_key")
        buffer = "test_key=old_value&other_key=other_value"
        FormAccessor.write_item(item, "new_value", buffer)
        expect(buffer).to eq("other_key=other_value&test_key=new_value")
      end

      it "removes bad keys from the buffer" do
        item = double("item", key: "test_key")
        buffer = "test_key=old_value&\u0000bad_key=bad_value&other_key=other_value"
        FormAccessor.write_item(item, "new_value", buffer)
        expect(buffer).to eq("other_key=other_value&test_key=new_value")
      end

      it "handles empty buffer correctly" do
        item = double("item", key: "test_key")
        buffer = ""
        FormAccessor.write_item(item, "test_value", buffer)
        expect(buffer).to eq("test_key=test_value")
      end
    end
  end
end
