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

$openc3_scope = ARGV[0]

require 'json'
require 'openc3'
require 'openc3/script/suite_runner'
require '../app/models/script'
require 'openc3/utilities/running_script'
require ARGV[1]

puts OpenC3::SuiteRunner.build_suites.as_json().to_json(allow_nan: true)
