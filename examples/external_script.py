# Copyright 2024 OpenC3, Inc.
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

import os

os.environ["OPENC3_API_SCHEMA"] = "http"
os.environ["OPENC3_API_HOSTNAME"] = "127.0.0.1"
os.environ["OPENC3_API_PORT"] = "2900"
os.environ["OPENC3_SCRIPT_API_SCHEMA"] = "http"
os.environ["OPENC3_SCRIPT_API_HOSTNAME"] = "127.0.0.1"
os.environ["OPENC3_SCRIPT_API_PORT"] = "2900"
# os.environ["OPENC3_API_USER"] = "admin" # Only set for Enterprise
os.environ["OPENC3_API_PASSWORD"] = "password"
os.environ["OPENC3_NO_STORE"] = "1"
# os.environ["OPENC3_KEYCLOAK_REALM"] = "openc3" # Only set for Enterprise
# os.environ["OPENC3_KEYCLOAK_URL"] = "http://127.0.0.1:2900/auth" # Only set for Enterprise

from openc3.utilities.string import formatted
from openc3.script import *

print(get_target_names())

print(tlm("INST ADCS POSX"))

print(cmd("INST ABORT"))

put_target_file("INST/test.txt", "this is a string test")
file = get_target_file("INST/test.txt")
print(file.read())
file.close()
delete_target_file("INST/test.txt")

with tempfile.NamedTemporaryFile(mode="w+t", suffix=".txt") as save_file:
    save_file.write("this is a Io test")
    save_file.seek(0)
    put_target_file("INST/test.txt", save_file)
file = get_target_file("INST/test.txt")
print(file.read())
file.close()
delete_target_file("INST/test.txt")

put_target_file("INST/test.bin", "\x00\x01\x02\x03\xFF\xEE\xDD\xCC".encode())
file = get_target_file("INST/test.bin")
print(formatted(file.read()))
file.close()
delete_target_file("INST/test.bin")
