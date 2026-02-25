# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'benchmark/ips'
require 'openc3'
require 'openc3/packets/binary_accessor'

Benchmark.ips do |x|
  @data = "\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
  @baseline_data = "\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
  x.report('read') do
    OpenC3::BinaryAccessor.read(-16, 16, :BLOCK, @data, :BIG_ENDIAN)
  end
  x.report('write') do
    OpenC3::BinaryAccessor.write(@baseline_data[14..15], -16, 16, :STRING, @data, :BIG_ENDIAN, :ERROR)
  end
end
