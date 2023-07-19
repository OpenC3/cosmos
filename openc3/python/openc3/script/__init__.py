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

import time
from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.script.server_proxy import ServerProxy

API_SERVER = ServerProxy()
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


def prompt_for_hazardous(target_name, cmd_name, hazardous_description):
    """ """
    message_list = [
        "Warning: Command {:s} {:s} is Hazardous. ".format(target_name, cmd_name)
    ]
    if hazardous_description:
        message_list.append(" >> {:s}".format(hazardous_description))
    message_list.append("Send? (y/N): ")
    answer = input("\n".join(message_list))
    try:
        return answer.lower()[0] == "y"
    except IndexError:
        return False


def prompt(
    string,
    text_color=None,
    background_color=None,
    font_size=None,
    font_family=None,
    details=None,
):
    if details:
        print(f"Details: #{details}\n")
    return input(f"#{string}: ")


def openc3_script_sleep(sleep_time=None):
    if sleep_time:
        time.sleep(sleep_time)
    else:
        prompt("Press any key to continue...")
    return False


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

from copy import deepcopy

__all__ = []  # For safer * imports


def generate_func(func_name):
    def __dynamic_func(*args, **kwargs):
        return getattr(API_SERVER, func_name)(*args, **kwargs)

    return __dynamic_func


# Loop through, construct function body and add
# it to the global scope of the module.
for __func_name in WHITELIST:
    __func = generate_func(__func_name)
    globals()[__func_name] = deepcopy(__func)
    __all__.append(__func_name)

# Clean up
del __func_name
del __func
__all__ = tuple(__all__)

# def define_whitelist_methods():
#     # module_obj = __import__(__name__)
#     module_obj = sys.modules[__name__]
#     for func in WHITELIST:

#         def _method(*args, **kwargs):
#             getattr(API_SERVER, func)(*args, **kwargs)

#         # add the function to the current module
#         setattr(module_obj, func, _method)


# define_whitelist_methods()
