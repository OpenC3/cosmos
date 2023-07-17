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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import sys

from openc3.script import COSMOS, DISCONNECT
from openc3.__version__ import __title__
from .exceptions import CosmosResponseError
from .extract import *
from openc3.environment import OPENC3_SCOPE
from openc3.top_level import HazardousError
from openc3.utilities.logger import Logger
from openc3.packets.packet import Packet


# Format the command like it appears in a script
def _cmd_string(target_name, cmd_name, cmd_params, raw):
    output_string = ""
    if DISCONNECT:
        output_string += "DISCONNECT: "
    if raw:
        output_string += 'cmd_raw("'
    else:
        output_string += 'cmd("'
    output_string += target_name + " " + cmd_name
    if not cmd_params:
        output_string << '")'
    else:
        params = []
        for key, value in cmd_params:
            if key in Packet.RESERVED_ITEM_NAMES:
                continue
            if type(value) == str:
                value = value.convert_to_value.to_s
                if value.length > 256:
                    value = value[:255] + "...'"
                if not value.isascii():
                    value = "BINARY"
                value = value.replace('"', "'")
            elif type(value) == list:
                value = f"[{value.join(', ')}]"
            params << f"{key} {value}"
        params = params.join(", ")
        output_string += " with " + params + '")'
    return output_string


def _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous):
    """Log any warnings about disabling checks and log the command itself
    NOTE: This is a helper method and should not be called directly"""
    if no_range:
        Logger.warn(
            f"Command {target_name} {cmd_name} being sent ignoring range checks"
        )
    if no_hazardous:
        Logger.warn(
            f"Command {target_name} {cmd_name} being sent ignoring hazardous warnings"
        )
    Logger.info(_cmd_string(target_name, cmd_name, cmd_params, raw))


def _cmd_disconnect(cmd, raw, no_range, no_hazardous, *args, scope):
    match len(args):
        case 1:
            target_name, cmd_name, cmd_params = extract_fields_from_cmd_text(args[0])
        case 2, 3:
            target_name = args[0]
            cmd_name = args[1]
            if len(args) == 2:
                cmd_params = {}
            else:
                cmd_params = args[2]
        case _:
            # Invalid number of arguments
            raise f"ERROR: Invalid number of arguments ({len(args)}) passed to {cmd}()"

    # Get the command and validate the parameters
    command = COSMOS.get_command(target_name, cmd_name, scope)
    for param_name, param_value in cmd_params:
        found = False
        for item in command["items"]:
            if item["name"] == param_name:
                found = item
                break
        if not found:
            raise f"Packet item '{target_name} {cmd_name} {param_name}' does not exist"
    _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous)


def _cmd(cmd, cmd_no_hazardous, *args, scope=OPENC3_SCOPE, timeout=None):
    """Send the command and log the results
    # This method signature has to include the keyword params present in cmd_api.py cmd_implementation()
    NOTE: This is a helper method and should not be called directly"""

    raw = "raw" in cmd
    no_range = "no_range" in cmd or "no_checks" in cmd
    no_hazardous = no_hazardous in cmd or "no_checks" in cmd

    if DISCONNECT:
        _cmd_disconnect(cmd, raw, no_range, no_hazardous, *args, scope)
    else:
        try:
            target_name, cmd_name, cmd_params = COSMOS.json_rpc_request(
                cmd, *args, scope=scope
            )
            _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous)
        except HazardousError:
            print(f"{cmd} is HAZARDOUS!!!")
            pass
        except CosmosResponseError as error:
            resp_error = error.response.error().data()["instance_variables"]
            ok_to_proceed = prompt_for_hazardous(
                resp_error["@target_name"],
                resp_error["@cmd_name"],
                resp_error["@hazardous_description"],
            )
            if ok_to_proceed:
                target_name, cmd_name, cmd_params = COSMOS.json_rpc_request(
                    cmd_no_hazardous, *args
                )
                _log_cmd(cmd_no_hazardous, target_name, cmd_name, cmd_params)
            else:
                prompt_for_script_abort()


def cmd(*args):
    """Send a command to the specified target
    Usage:
      cmd(target_name, cmd_name, cmd_params = {})
    or
      cmd('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd", "cmd_no_hazardous_check", *args)


def cmd_no_range_check(*args):
    """Send a command to the specified target without range checking parameters
    Usage:
      cmd_no_range_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_no_range_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_no_range_check", *args)


def cmd_no_hazardous_check(*args):
    """Send a command to the specified target without hazardous checks
    Usage:
      cmd_no_hazardous_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_no_hazardous_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_no_hazardous_check", *args)


def cmd_no_checks(*args):
    """Send a command to the specified target without range checking or hazardous checks
    Usage:
      cmd_no_checks(target_name, cmd_name, cmd_params = {})
    or
      cmd_no_checks('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_no_checks", *args)


def cmd_raw(*args):
    """Send a command to the specified target without running conversions
    Usage:
      cmd_raw(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw", *args)


def cmd_raw_no_range_check(*args):
    """Send a command to the specified target without range checking parameters or running conversions
    Usage:
      cmd_raw_no_range_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw_no_range_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw_no_range_check", *args)


def cmd_raw_no_hazardous_check(*args):
    """Send a command to the specified target without hazardous checks or running conversions
    Usage:
      cmd_raw_no_hazardous_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw_no_hazardous_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw_no_hazardous_check", None, *args)


def cmd_raw_no_checks(*args):
    """Send a command to the specified target without range checking or hazardous checks or running conversions
    Usage:
      cmd_raw_no_checks(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw_no_checks('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw_no_checks", None, *args)


def send_raw(interface_name, data):
    """Sends raw data through an interface"""
    return COSMOS.json_rpc_request("send_raw", interface_name, data)


def send_raw_file(interface_name, filename):
    """Sends raw data through an interface from a file"""
    with open(filename, "rb") as file:
        data = file.read()
    return COSMOS.json_rpc_request("send_raw", interface_name, data)


def get_cmd_list(target_name):
    """Returns all the target commands as an array of arrays listing the command name and description."""
    return COSMOS.json_rpc_request("get_cmd_list", target_name)


def get_cmd_param_list(target_name, cmd_name):
    """Returns all the parameters for given command as an array of arrays
    containing the parameter name, default value, states, description, units
    full name, units abbreviation, and whether it is required."""
    return COSMOS.json_rpc_request("get_cmd_param_list", target_name, cmd_name)


def get_cmd_hazardous(target_name, cmd_name, cmd_params=None):
    """Returns whether a command is hazardous (true or false)"""
    if cmd_params is None:
        cmd_params = {}
    return COSMOS.json_rpc_request(
        "get_cmd_hazardous", target_name, cmd_name, cmd_params
    )


def get_cmd_value(target_name, command_name, parameter_name, value_type="CONVERTED"):
    """Returns a value from the specified command"""
    return COSMOS.json_rpc_request(
        "get_cmd_value", target_name, command_name, parameter_name, value_type
    )


def get_cmd_time(target_name=None, command_name=None):
    """Returns the time the most recent command was sent"""
    return COSMOS.json_rpc_request("get_cmd_time", target_name, command_name)


def get_cmd_buffer(target_name, command_name):
    """Returns the buffer from the most recent specified command"""
    return COSMOS.json_rpc_request("get_cmd_buffer", target_name, command_name)


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


def prompt_for_script_abort():
    """ """
    answer = input("Stop running script? (y/N): ")
    try:
        if answer.lower()[0] == "y":
            sys.exit(66)  # execute order 66
    except IndexError:
        return False
