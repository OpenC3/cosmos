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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

ENV['OPENC3_NO_STORE'] = '1'

require 'benchmark/ips'
require 'openc3'
require 'openc3/interfaces/protocols/burst_protocol'

OpenC3::Logger.stdout = false

#Benchmark.ips do |x|
#  bp = OpenC3::BurstProtocol.new(4, sync_pattern = "1ACFFC1D", true, allow_empty_data = nil)
#
#  bp2 = OpenC3::BurstProtocol.new(0, sync_pattern = nil, false, allow_empty_data = nil)
#  x.report('read_data with sync') do
#    @need_sync_data = "\x00\x00\x00\x00\x1A\xCF\xFC\x1D\x00\x00\x00\x00\x00\x00\x00\x00"
#    bp.read_data(@need_sync_data)
#  end
#  x.report('read_data without sync') do
#    @need_sync_data = "\x00\x00\x00\x00\x1A\xCF\xFC\x1D\x00\x00\x00\x00\x00\x00\x00\x00"
#    bp2.read_data(@need_sync_data)
#  end
#end

if ENV['OPENC3_NO_EXT']
  puts "No C Extension"
else
  puts "With C Extension"
end
out_of_sync_data = "\x00\x00\x00\x00\x1A\xCF\xFC\x1D\x00\x00\x00\x00\x00\x00\x00\x00" * 1000
in_sync_data = "\x1A\xCF\xFC\x1D\x00\x00\x00\x00\x00\x00\x00\x00" * 1000
start_time = Time.now
#bp = OpenC3::BurstProtocol.new(0, sync_pattern = nil, false, allow_empty_data = nil)
bp = OpenC3::BurstProtocol.new(4, sync_pattern = "1ACFFC1D", true, allow_empty_data = nil)
1000000.times do
  bp.read_data(out_of_sync_data)
end
end_time = Time.now
puts "Total time = #{end_time - start_time}"
