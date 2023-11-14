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

from openc3.script import DISCONNECT
from openc3.script import API_SERVER as API_SERVER

LIMITS_METHODS = [
    "enable_limits",
    "disable_limits",
    "set_limits",
    "enable_limits_group",
    "disable_limits_group",
    "set_limits_set",
]

# Define all the modification methods such that we can disconnect them
for method in LIMITS_METHODS:
    code = [f"def {method}(*args, **kwargs):"]
    if DISCONNECT:
        code.append(f"        print('DISCONNECT: {method}(args) ignored')")
    else:
        code.append(f"        return getattr(API_SERVER, '{method}')(*args, **kwargs)")
    function = compile("\n".join(code), "<string>", "exec")
    exec(function, globals())
