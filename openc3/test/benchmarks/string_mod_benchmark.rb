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
