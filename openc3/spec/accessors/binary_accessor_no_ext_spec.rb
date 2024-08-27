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

ENV['OPENC3_NO_EXT']='TRUE'
require 'spec_helper'
require 'openc3'
require 'openc3/accessors/binary_accessor'
require 'openc3/packets/packet'

module OpenC3
  describe BinaryAccessor, no_ext: true do

    describe "read only" do
      before(:each) do
        @data = "\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
      end

      it "complains about unknown data types" do
        expect { BinaryAccessor.read(0, 32, :BLOB, @data, :BIG_ENDIAN) }.to raise_error(ArgumentError, "data_type BLOB is not recognized")
      end
    end # describe 'read'

  end # describe BinaryAccessor
end
