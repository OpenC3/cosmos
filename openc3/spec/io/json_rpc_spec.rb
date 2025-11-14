# Copyright 2023 OpenC3, Inc.
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
require 'openc3/io/json_rpc'

module OpenC3
  describe as_json do
    describe "string as_json" do
      it "converts utf8 bytes" do
        bytes = 'ab' # Valid ASCII
        expect(bytes.as_json).to eql("ab")
        bytes = "\xc3\xb1" # Valid 2 Octet Sequence
        expect(bytes.as_json).to eql("ñ")
        bytes = "\xc3\x28" # Invalid 2 Octet Sequence
        expect(bytes.as_json).to eql({"json_class" => "String", "raw" => bytes.unpack("C*")})
        bytes = "\xe2\x28\xa1" # Invalid 3 Octet Sequence
        expect(bytes.as_json).to eql({"json_class" => "String", "raw" => bytes.unpack("C*")})
        bytes = "\xf0\x28\x8c\x28" # Invalid 4 Octet Sequence
        expect(bytes.as_json).to eql({"json_class" => "String", "raw" => bytes.unpack("C*")})
      end

      it "encodes binary data with high bytes as json_class format" do
        # Test binary string with bytes > 127 (even if valid UTF-8)
        # This simulates data from hex_to_byte_string like 0xDEAD
        bytes = "\xDE\xAD\xBE\xEF".b
        result = bytes.as_json
        expect(result).to eql({"json_class" => "String", "raw" => [222, 173, 190, 239]})

        # Verify round-trip encoding/decoding
        json_str = JSON.generate(result, allow_nan: true)
        decoded = JSON.parse(json_str, allow_nan: true, create_additions: true)
        expect(decoded).to eq(bytes)
        expect(decoded.encoding).to eq(Encoding::ASCII_8BIT)
      end

      it "does not encode plain ASCII strings even if ASCII-8BIT encoding" do
        # Plain ASCII text should not be encoded as binary even if marked ASCII-8BIT
        bytes = "NORMAL".force_encoding(Encoding::ASCII_8BIT)
        expect(bytes.as_json).to eql("NORMAL")
      end
    end
  end
end
