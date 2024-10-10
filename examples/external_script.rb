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

ENV['OPENC3_API_SCHEMA'] ||= 'http'
ENV['OPENC3_API_HOSTNAME'] ||= '127.0.0.1'
ENV['OPENC3_API_PORT'] ||= '2900'
ENV['OPENC3_SCRIPT_API_SCHEMA'] ||= 'http'
ENV['OPENC3_SCRIPT_API_HOSTNAME'] ||= '127.0.0.1'
ENV['OPENC3_SCRIPT_API_PORT'] ||= '2900'
ENV['OPENC3_API_PASSWORD'] ||= 'password'
ENV['OPENC3_NO_STORE'] ||= '1'

require 'openc3'
require 'openc3/script'

puts get_target_names()

puts tlm('INST ADCS POSX')

puts cmd("INST ABORT")

INST_TEST_TXT = 'INST/test.txt'
INST_TEST_BIN = 'INST/test.bin'
put_target_file(INST_TEST_TXT, "this is a string test")
file = get_target_file(INST_TEST_TXT)
puts file.read
file.unlink
delete_target_file(INST_TEST_TXT)

save_file = Tempfile.new('test')
save_file.write("this is a Io test")
save_file.rewind
put_target_file(INST_TEST_TXT, save_file)
save_file.unlink
file = get_target_file(INST_TEST_TXT)
puts file.read
file.unlink
delete_target_file(INST_TEST_TXT)

put_target_file(INST_TEST_BIN, "\x00\x01\x02\x03\xFF\xEE\xDD\xCC")
file = get_target_file(INST_TEST_BIN)
puts file.read.formatted
file.unlink
delete_target_file(INST_TEST_BIN)
