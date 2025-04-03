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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.script.server_proxy import ApiServerProxy, ScriptServerProxy
from openc3.utilities.authentication import OpenC3KeycloakAuthentication
from openc3.utilities.extract import convert_to_value
from openc3.environment import OPENC3_KEYCLOAK_URL
import threading

API_SERVER = ApiServerProxy()
SCRIPT_RUNNER_API_SERVER = ScriptServerProxy()
RUNNING_SCRIPT = None
DISCONNECT = False
OPENC3_IN_CLUSTER = False
if "openc3-cosmos-cmd-tlm-api" in API_SERVER.generate_url():
    OPENC3_IN_CLUSTER = True


def shutdown_script():
    global API_SERVER
    API_SERVER.shutdown()
    global SCRIPT_RUNNER_API_SERVER
    SCRIPT_RUNNER_API_SERVER.shutdown()


def prompt_for_hazardous(target_name, cmd_name, hazardous_description):
    """ """
    message_list = [f"Warning: Command {target_name} {cmd_name} is Hazardous. "]
    if hazardous_description:
        message_list.append(hazardous_description)
    message_list.append("Send? (y/N): ")
    answer = input("\n".join(message_list))
    try:
        return answer.lower()[0] == "y"
    except IndexError:
        return False


def _file_dialog(title, message, filter=None):
    answer = ""
    while len(answer) == 0:
        print(f"{title}\n{message}\n<Type file name>:")
        answer = input()
    return answer


###########################################################################
# START PUBLIC API
###########################################################################


def disconnect_script():
    global DISCONNECT
    DISCONNECT = True


def ask_string(question, blank_or_default=False, password=False):
    answer = ""
    default = None
    if blank_or_default is not True and blank_or_default is not False:
        question += f" (default = {blank_or_default})"
        default = str(blank_or_default)
        allow_blank = True
    else:
        allow_blank = blank_or_default
    while len(answer) == 0:
        print(question + " ")
        answer = input()
        if allow_blank:
            break
    if len(answer) == 0 and default:
        answer = default
    return answer


def ask(question, blank_or_default=False, password=False):
    string = ask_string(question, blank_or_default, password)
    value = convert_to_value(string)
    return value


def message_box(string, *buttons, **options):
    print(f"{string} ({', '.join(buttons)}): ")
    if "details" in options:
        print(f"Details: {options['details']}\n")
    return input()


def vertical_message_box(string, *buttons, **options):
    return message_box(string, *buttons, **options)


def combo_box(string, *buttons, **options):
    return message_box(string, *buttons, **options)


def open_file_dialog(title, message="Open File", filter=None):
    _file_dialog(title, message, filter)


def open_files_dialog(title, message="Open File", filter=None):
    _file_dialog(title, message, filter)


def prompt(
    string,
    text_color=None,
    background_color=None,
    font_size=None,
    font_family=None,
    details=None,
):
    print(f"{string}: ")
    if details:
        print(f"Details: {details}\n")
    return input()


def step_mode():
    # running_script.py implements the real functionality
    pass


def run_mode():
    # running_script.py implements the real functionality
    pass

from .api_shared import *
from .commands import *
from .cosmos_calendar import *
from .critical_cmd import *
from .exceptions import *
from .limits import *
from .metadata import *
from .packages import *
from .plugins import *
from .screen import *
from .script_runner import *
from .storage import *
from .tables import *
from .telemetry import *
from openc3.api import WHITELIST

# Note: Enterprise Only - Use this for first time setup of an offline access token
# so that users can run scripts.  Not necessary if accessing APIs via the web
# frontend as it handles it automatically.
#
# Example:
# initialize_offline_access()
# script_run("INST/procedures/collect.rb")
#
def initialize_offline_access():
    auth = OpenC3KeycloakAuthentication(OPENC3_KEYCLOAK_URL)
    auth.token(include_bearer=True, openid_scope='openid%20offline_access')
    set_offline_access(auth.refresh_token)

###########################################################################
# END PUBLIC API
###########################################################################


def prompt_for_critical_cmd(uuid, _username, _target_name, _cmd_name, _cmd_params, cmd_string):
    print("Waiting for critical command approval:")
    print(f"  {cmd_string}")
    print(f"  UUID: {uuid}")
    while True:
        status = critical_cmd_status(uuid)
        if status == "APPROVED":
            return
        elif status == "REJECTED":
            raise RuntimeError("Critical command rejected")
        threading.sleep(0.1)


# Define all the WHITELIST methods
current_functions = dir()
for func in WHITELIST:
    if func not in current_functions:
        code = f"def {func}(*args, **kwargs):\n    return getattr(API_SERVER, '{func}')(*args, **kwargs)"
        function = compile(code, "<string>", "exec")
        exec(function, globals())
