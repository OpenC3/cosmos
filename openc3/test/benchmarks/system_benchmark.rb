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

require 'openc3'
require 'benchmark'
ENV['OPENC3_NO_STORE'] = 'true'

dir = File.expand_path(File.join(__dir__, '..', '..', 'spec', 'install', 'config', 'targets'))
puts dir
targets = ["SYSTEM", "INST", "EMPTY"]
n = 5000000
Benchmark.bm do |x|
  x.report("system") do
    OpenC3::System.class_variable_set(:@@instance, nil)
    OpenC3::System.instance(targets, dir)
  end
end
