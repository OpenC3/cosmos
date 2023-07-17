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

import os
from .connection import CosmosConnection
from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.script.server_proxy import ServerProxy

COSMOS = CosmosConnection()
API_SERVER = ServerProxy()
DISCONNECT = False
OPENC3_IN_CLUSTER = False
if "openc3-cosmos-cmd-tlm-api" in API_SERVER.generate_url():
    OPENC3_IN_CLUSTER = True

# def initialize_connection(hostname: str = None, port: int = None):
#     """Generate the current session with Cosmos

#     Parameters:
#         hostname (str): The hostname to connect to Cosmos v5
#         port (int): The port to connect to Cosmos v5
#     """
#     global COSMOS

#     if COSMOS:
#         COSMOS.shutdown()

#     if hostname and port:
#         COSMOS = CosmosConnection(hostname=hostname, port=port)
#     else:
#         COSMOS = CosmosConnection()


def shutdown_script():
    global COSMOS
    COSMOS.shutdown()
    global API_SERVER
    API_SERVER.shutdown()


def disconnect_script():
    global DISCONNECT
    DISCONNECT = True


from .api_shared import *
from .cosmos_api import *
from .commands import *
from .extract import *
from .internal_api import *
from .limits import *
from .telemetry import *
from .timeline_api import *
from .tools import *

# Define all the WHITELIST methods
module_obj = sys.modules[__name__]
for func in WHITELIST:

    def method(*args, **kwargs):
        getattr(API_SERVER, func)(*args, **kwargs)
        # return COSMOS.json_rpc_request(func, *args, **kwargs)

    # add the function to the current module
    setattr(module_obj, func, method)
