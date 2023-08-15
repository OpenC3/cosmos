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

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.top_level import HazardousError
from openc3.utilities.logger import Logger
from openc3.utilities.extract import *

from openc3.packets.packet import Packet


# Format the command like it appears in a script
def _cmd_string(target_name, cmd_name, cmd_params, raw):
    output_string = ""
    if openc3.script.DISCONNECT:
        output_string += "openc3.script.DISCONNECT: "
    if raw:
        output_string += 'cmd_raw("'
    else:
        output_string += 'cmd("'
    output_string += target_name + " " + cmd_name
    if not cmd_params:
        output_string += '")'
    else:
        params = []
        for key, value in cmd_params.items():
            if key in Packet.RESERVED_ITEM_NAMES:
                continue
            if type(value) == str:
                value = convert_to_value(value)
                if len(value) > 256:
                    value = value[:255] + "...'"
                if not value.isascii():
                    value = "BINARY"
                value = value.replace('"', "'")
            elif type(value) == list:
                value = f"[{', '.join(value)}]"
            params.append(f"{key} {value}")
        params = ", ".join(params)
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
        case 2 | 3:
            target_name = args[0]
            cmd_name = args[1]
            if len(args) == 2:
                cmd_params = {}
            else:
                cmd_params = args[2]
        case _:
            # Invalid number of arguments
            raise RuntimeError(
                f"ERROR: Invalid number of arguments ({len(args)}) passed to {cmd}()"
            )

    # Get the command and validate the parameters
    command = openc3.script.API_SERVER.get_command(target_name, cmd_name, scope=scope)
    if cmd_params:
        for param_name in cmd_params.keys():
            found = False
            if "items" in command:
                for item in command["items"]:
                    if item["name"] == param_name:
                        found = item
                        break
            if not found:
                raise RuntimeError(
                    f"Packet item '{target_name} {cmd_name} {param_name}' does not exist"
                )
    _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous)


def _cmd(cmd, cmd_no_hazardous, *args, scope=OPENC3_SCOPE, timeout=None):
    """Send the command and log the results
    # This method signature has to include the keyword params present in cmd_api.py cmd_implementation()
    NOTE: This is a helper method and should not be called directly"""

    raw = "raw" in cmd
    no_range = "no_range" in cmd or "no_checks" in cmd
    no_hazardous = "no_hazardous" in cmd or "no_checks" in cmd

    if openc3.script.DISCONNECT:
        _cmd_disconnect(cmd, raw, no_range, no_hazardous, *args, scope=scope)
    else:
        try:
            target_name, cmd_name, cmd_params = getattr(openc3.script.API_SERVER, cmd)(
                *args, timeout=timeout, scope=scope
            )
            _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous)
        except HazardousError as error:
            # Need to reimport here to pick up changes from running_script
            from openc3.utilities.script_shared import prompt_for_hazardous

            ok_to_proceed = prompt_for_hazardous(
                error.target_name,
                error.cmd_name,
                error.hazardous_description,
            )
            if ok_to_proceed:
                target_name, cmd_name, cmd_params = getattr(
                    openc3.script.API_SERVER, cmd_no_hazardous
                )(*args, scope=scope, timeout=timeout)
                _log_cmd(target_name, cmd_name, cmd_params, raw, no_range, no_hazardous)


def cmd(*args, **kwargs):
    """Send a command to the specified target
    Usage:
      cmd(target_name, cmd_name, cmd_params = {})
    or
      cmd('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd", "cmd_no_hazardous_check", *args, **kwargs)


def cmd_raw(*args, **kwargs):
    """Send a command to the specified target without running conversions
    Usage:
      cmd_raw(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw", "cmd_raw_no_hazardous_check", *args, **kwargs)


def cmd_no_range_check(*args, **kwargs):
    """Send a command to the specified target without range checking parameters
    Usage:
      cmd_no_range_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_no_range_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_no_range_check", "cmd_no_checks", *args, **kwargs)


def cmd_raw_no_range_check(*args, **kwargs):
    """Send a command to the specified target without range checking parameters or running conversions
    Usage:
      cmd_raw_no_range_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw_no_range_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw_no_range_check", "cmd_raw_no_checks", *args, **kwargs)


def cmd_no_hazardous_check(*args, **kwargs):
    """Send a command to the specified target without hazardous checks
    Usage:
      cmd_no_hazardous_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_no_hazardous_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_no_hazardous_check", None, *args, **kwargs)


def cmd_raw_no_hazardous_check(*args, **kwargs):
    """Send a command to the specified target without hazardous checks or running conversions
    Usage:
      cmd_raw_no_hazardous_check(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw_no_hazardous_check('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw_no_hazardous_check", None, *args, **kwargs)


def cmd_no_checks(*args, **kwargs):
    """Send a command to the specified target without range checking or hazardous checks
    Usage:
      cmd_no_checks(target_name, cmd_name, cmd_params = {})
    or
      cmd_no_checks('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_no_checks", None, *args, **kwargs)


def cmd_raw_no_checks(*args, **kwargs):
    """Send a command to the specified target without range checking or hazardous checks or running conversions
    Usage:
      cmd_raw_no_checks(target_name, cmd_name, cmd_params = {})
    or
      cmd_raw_no_checks('target_name cmd_name with cmd_param1 value1, cmd_param2 value2')
    """
    return _cmd("cmd_raw_no_checks", None, *args, **kwargs)


def build_command(*args, **kwargs):
    """Builds a command binary
    Accepts two different calling styles:
    build_command("TGT CMD with PARAM1 val, PARAM2 val")
    build_command('TGT','CMD',{'PARAM1'=>val,'PARAM2'=>val})"""
    extract_string_kwargs_to_args(args, kwargs)
    return getattr(openc3.script.API_SERVER, "build_command")(*args)


def get_cmd_hazardous(*args, **kwargs):
    """Returns whether a command is hazardous (true or false)"""
    extract_string_kwargs_to_args(args, kwargs)
    return getattr(openc3.script.API_SERVER, "get_cmd_hazardous")(*args)


def send_raw_file(interface_name, filename, scope=OPENC3_SCOPE):
    """Sends raw data through an interface from a file"""
    with open(filename, "rb") as file:
        data = file.read()
    return getattr(openc3.script.API_SERVER, "send_raw")(
        interface_name, data, scope=scope
    )


# Returns the time the most recent command was sent
def get_cmd_time(target_name=None, command_name=None, scope=OPENC3_SCOPE):
    results = getattr(openc3.script.API_SERVER, "get_cmd_time")(
        target_name, command_name, scope=scope
    )
    if type(results) == list:
        if results[2] and results[3]:
            pass
            # TODO: Python Time.at equivalent?
            # results[2] = Time.at(results[2], results[3]).sys
        results.pop(3)
    return results
