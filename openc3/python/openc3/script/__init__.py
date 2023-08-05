#!/usr/bin/env python3

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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.api import WHITELIST
from openc3.script.server_proxy import ServerProxy
from openc3.utilities.bucket_utilities import BucketUtilities

bucket_load = BucketUtilities.bucket_load

API_SERVER = ServerProxy()
RUNNING_SCRIPT = None
DISCONNECT = False
OPENC3_IN_CLUSTER = False
if "openc3-cosmos-cmd-tlm-api" in API_SERVER.generate_url():
    OPENC3_IN_CLUSTER = True


def shutdown_script():
    global API_SERVER
    API_SERVER.shutdown()


def disconnect_script():
    global DISCONNECT
    DISCONNECT = True


from .api_shared import *
from .cosmos_api import *
from .commands import *
from .internal_api import *
from .limits import *
from .telemetry import *
from .metadata import *
from .screen import *
from .storage import *

# Define all the WHITELIST methods
current_functions = dir()
for func in WHITELIST:
    if func not in current_functions:
        code = f"def {func}(*args, **kwargs):\n    return getattr(API_SERVER, '{func}')(*args, **kwargs)"
        function = compile(code, "<string>", "exec")
        exec(function, globals())
