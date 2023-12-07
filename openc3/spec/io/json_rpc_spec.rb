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
    end
  end
end
