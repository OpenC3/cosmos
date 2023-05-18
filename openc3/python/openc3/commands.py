#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
commands.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import logging
import sys

import cosmosc2
from cosmosc2.__version__ import __title__
from cosmosc2.exceptions import CosmosResponseError
from cosmosc2.extract import convert_to_value

LOGGER = logging.getLogger(__title__)


# This is in System.commands in Ruby
def build_cmd_output_string(target_name, cmd_name, cmd_params, raw=False):
    if raw:
        output_string = 'cmd_raw("'
    else:
        output_string = 'cmd("'
    output_string += target_name + " " + cmd_name
    if cmd_params is None or len(cmd_params) == 0:
        output_string += '")'
    else:
        params = []
        for key, value in cmd_params.items():
            if isinstance(value, str):
                if isinstance(convert_to_value(value), str):
                    value = repr(value)
                    if len(value) > 256:
                        value = value[0:256] + "...'"
                    value = value.replace('"', "'")
            params.append("{:s} {:s}".format(key, str(value)))
        params = ", ".join(params)
        output_string += " with " + params + '")'
    return output_string


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


def _log_cmd(cmd_, target_name, cmd_name, cmd_params):
    """Log any warnings about disabling checks and log the command itself
    NOTE: This is a helper method and should not be called directly"""
    cmd_str = build_cmd_output_string(target_name, cmd_name, cmd_params, "raw" in cmd_)
    if "no_range" in cmd_ or "no_checks" in cmd_:
        LOGGER.warning(f"{cmd_str} being sent ignoring range checks")
    if "no_hazardous" in cmd_ or "no_checks" in cmd_:
        LOGGER.warning(f"{cmd_str} being sent ignoring hazardous warnings")


def _cmd(cmd_, cmd_no_hazardous, *args):
    """Send the command and log the results
    NOTE: This is a helper method and should not be called directly"""
    try:
        target_name, cmd_name, cmd_params = cosmosc2.COSMOS.json_rpc_request(
            cmd_, *args
        )
        _log_cmd(cmd_, target_name, cmd_name, cmd_params)
    except CosmosResponseError as error:
        resp_error = error.response.error().data()["instance_variables"]
        ok_to_proceed = prompt_for_hazardous(
            resp_error["@target_name"],
            resp_error["@cmd_name"],
            resp_error["@hazardous_description"],
        )
        if ok_to_proceed:
            target_name, cmd_name, cmd_params = cosmosc2.COSMOS.json_rpc_request(
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
    return _cmd("cmd", *args)


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
    return cosmosc2.COSMOS.json_rpc_request("send_raw", interface_name, data)


def send_raw_file(interface_name, filename):
    """Sends raw data through an interface from a file"""
    with open(filename, "rb") as file:
        data = file.read()
    return cosmosc2.COSMOS.json_rpc_request("send_raw", interface_name, data)


def get_cmd_list(target_name):
    """Returns all the target commands as an array of arrays listing the command name and description."""
    return cosmosc2.COSMOS.json_rpc_request("get_cmd_list", target_name)


def get_cmd_param_list(target_name, cmd_name):
    """Returns all the parameters for given command as an array of arrays
    containing the parameter name, default value, states, description, units
    full name, units abbreviation, and whether it is required."""
    return cosmosc2.COSMOS.json_rpc_request("get_cmd_param_list", target_name, cmd_name)


def get_cmd_hazardous(target_name, cmd_name, cmd_params=None):
    """Returns whether a command is hazardous (true or false)"""
    if cmd_params is None:
        cmd_params = {}
    return cosmosc2.COSMOS.json_rpc_request(
        "get_cmd_hazardous", target_name, cmd_name, cmd_params
    )


def get_cmd_value(target_name, command_name, parameter_name, value_type="CONVERTED"):
    """Returns a value from the specified command"""
    return cosmosc2.COSMOS.json_rpc_request(
        "get_cmd_value", target_name, command_name, parameter_name, value_type
    )


def get_cmd_time(target_name=None, command_name=None):
    """Returns the time the most recent command was sent"""
    return cosmosc2.COSMOS.json_rpc_request("get_cmd_time", target_name, command_name)


def get_cmd_buffer(target_name, command_name):
    """Returns the buffer from the most recent specified command"""
    return cosmosc2.COSMOS.json_rpc_request("get_cmd_buffer", target_name, command_name)
