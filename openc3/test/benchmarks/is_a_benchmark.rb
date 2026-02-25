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

require 'benchmark'

iterations = 10_000_000

value = "hi"

Benchmark.bm(30) do |x|
  x.report("value.is_a?") { iterations.times { if value.is_a?(Integer); end } }
  x.report("value.respond_to?") { iterations.times { if value.respond_to?(:abs); end } }
  x.report("type === value") { iterations.times { if Integer === value; end } }
  x.report("case when") do
    iterations.times do
      case value
      when Integer
      end
    end
  end
  x.report("if x2") do
    iterations.times do
      if value.is_a?(Integer)
      elsif value.is_a?(String)
      end
    end
  end
  x.report("case when x2") do
    iterations.times do
      case value
      when Integer
      when String
      end
    end
  end
end
