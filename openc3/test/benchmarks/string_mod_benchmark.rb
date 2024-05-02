# encoding: ascii-8bit

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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'securerandom'
require 'benchmark'

Benchmark.bm do |x|
  data = SecureRandom.random_bytes(1024)
  x.report("slice!") do
    1000.times.each { data.slice!(0, 1) }
  end
  data = SecureRandom.random_bytes(1024)
  x.report("assign") do
    1000.times.each { data = data[1..-1] }
  end
  data = SecureRandom.random_bytes(1024)
  x.report("replace") do
    1000.times.each { data.replace(data[1..-1]) }
  end
end

Benchmark.bm do |x|
  data = SecureRandom.random_bytes(1024*1024)
  x.report("slice!") do
    1000.times.each { data.slice!(0, 1) }
  end
  data = SecureRandom.random_bytes(1024*1024)
  x.report("assign") do
    1000.times.each { data = data[1..-1] }
  end
  data = SecureRandom.random_bytes(1024*1024)
  x.report("replace") do
    1000.times.each { data.replace(data[1..-1]) }
  end
end
