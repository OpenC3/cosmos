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

from openc3.script import API_SERVER as API_SERVER
from openc3.script import DISCONNECT


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
