# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963


import os
from contextlib import contextmanager
from openc3.api import WHITELIST
from openc3.api.interface_api import get_interface
from openc3.top_level import DisabledError
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.utilities.string import simple_formatted
from openc3.models.target_model import TargetModel
from openc3.utilities.extract import *
from openc3.topics.topic import Topic
from openc3.topics.command_topic import CommandTopic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from openc3.topics.command_decom_topic import CommandDecomTopic
from openc3.packets.packet import Packet

WHITELIST.extend(
    [
        "cmd",
        "cmd_no_range_check",
        "cmd_no_hazardous_check",
        "cmd_no_checks",
        "cmd_raw",
        "cmd_raw_no_range_check",
        "cmd_raw_no_hazardous_check",
        "cmd_raw_no_checks",
        "build_cmd",
        "build_command",  # DEPRECATED
        "enable_cmd",
        "disable_cmd",
        "send_raw",
        "get_all_cmds",
        "get_all_commands",  # DEPRECATED
        "get_all_cmd_names",
        "get_all_command_names",  # DEPRECATED
        "get_cmd",
        "get_command",  # DEPRECATED
        "get_param",
        "get_parameter",  # DEPRECATED
        "get_cmd_buffer",
        "get_cmd_hazardous",
        "get_cmd_value",
        "get_cmd_time",
        "get_cmd_cnt",
        "get_cmd_cnts",
    ]
)


# The following methods sends a command packet to a target. The 'raw' version of the equivalent
# command methods do not perform command parameter conversions.
#
# Accepts two different calling styles:
#   cmd("TGT CMD with PARAM1 val, PARAM2 val")
#   cmd('TGT','CMD',{'PARAM1':val,'PARAM2':val})
#
# Favor the first syntax where possible as it is more succinct.
def cmd(*args, **kwargs):
    return _cmd_implementation("cmd", *args, range_check=True, hazardous_check=True, raw=False, manual=False, **kwargs)


def cmd_raw(*args, **kwargs):
    return _cmd_implementation(
        "cmd_raw", *args, range_check=True, hazardous_check=True, raw=True, manual=False, **kwargs
    )


# S a command packet to a target without performing any value range
# checks on the parameters. Useful for testing to allow sing command
# parameters outside the allowable range as defined in the configuration.
def cmd_no_range_check(*args, **kwargs):
    return _cmd_implementation(
        "cmd_no_range_check",
        *args,
        range_check=False,
        hazardous_check=True,
        raw=False,
        manual=False,
        **kwargs,
    )


def cmd_raw_no_range_check(*args, **kwargs):
    return _cmd_implementation(
        "cmd_raw_no_range_check",
        *args,
        range_check=False,
        hazardous_check=True,
        raw=True,
        manual=False,
        **kwargs,
    )


# S a command packet to a target without performing any hazardous checks
# both on the command itself and its parameters. Useful in scripts to
# prevent popping up warnings to the user.
def cmd_no_hazardous_check(*args, **kwargs):
    return _cmd_implementation(
        "cmd_no_hazardous_check",
        *args,
        range_check=True,
        hazardous_check=False,
        raw=False,
        manual=False,
        **kwargs,
    )


def cmd_raw_no_hazardous_check(*args, **kwargs):
    return _cmd_implementation(
        "cmd_raw_no_hazardous_check",
        *args,
        range_check=True,
        hazardous_check=False,
        raw=True,
        manual=False,
        **kwargs,
    )


# S a command packet to a target without performing any value range
# checks or hazardous checks both on the command itself and its parameters.
def cmd_no_checks(*args, **kwargs):
    return _cmd_implementation(
        "cmd_no_checks",
        *args,
        range_check=False,
        hazardous_check=False,
        raw=False,
        manual=False,
        **kwargs,
    )


def cmd_raw_no_checks(*args, **kwargs):
    return _cmd_implementation(
        "cmd_raw_no_checks",
        *args,
        range_check=False,
        hazardous_check=False,
        raw=True,
        manual=False,
        **kwargs,
    )


# Build a command binary
def build_cmd(*args, range_check=True, raw=False, timeout=5, scope=OPENC3_SCOPE, manual=False):
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
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to build_command()")
    target_name = target_name.upper()
    cmd_name = cmd_name.upper()
    cmd_params = {k.upper(): v for k, v in cmd_params.items()}
    authorize(permission="cmd_info", target_name=target_name, scope=scope, manual=manual)
    return DecomInterfaceTopic.build_cmd(target_name, cmd_name, cmd_params, range_check, raw, timeout, scope)


# build_command is DEPRECATED
build_command = build_cmd


# Helper method for disable_cmd / enable_cmd
@contextmanager
def _get_and_set_cmd(method, *args, scope=OPENC3_SCOPE, manual=False):
    target_name, command_name = _extract_target_command_names(method, *args)
    authorize(
        permission="admin",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    command = TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    yield command
    TargetModel.set_packet(target_name, command_name, command, type="CMD", scope=scope)


# @since 5.15.1
def enable_cmd(*args, scope=OPENC3_SCOPE, manual=False):
    with _get_and_set_cmd("enable_cmd", *args, scope=scope, manual=manual) as command:
        command.pop("disabled", None)


# @since 5.15.1
def disable_cmd(*args, scope=OPENC3_SCOPE, manual=False):
    with _get_and_set_cmd("disable_cmd", *args, scope=scope, manual=manual) as command:
        command["disabled"] = True


# Send a raw binary string to the specified interface.
#
# @param interface_name [String] The interface to s the raw binary
# @param data [String] The raw binary data
def send_raw(interface_name, data, scope=OPENC3_SCOPE, manual=False):
    interface_name = interface_name.upper()
    authorize(permission="cmd_raw", interface_name=interface_name, scope=scope, manual=manual)
    get_interface(interface_name, scope=scope)  # Check to make sure the interface exists
    InterfaceTopic.write_raw(interface_name, data, scope=scope)


# Returns the raw buffer from the most recent specified command packet.
#
# @param target_name [String] Target name of the command
# @param command_name [String] Packet name of the command
# @return [Hash] command hash with last command buffer
def get_cmd_buffer(*args, scope=OPENC3_SCOPE, manual=False):
    target_name, command_name = _extract_target_command_names("get_cmd_buffer", *args)
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    topic = f"{scope}__COMMAND__{{{target_name}}}__{command_name}"
    msg_id, message = Topic.get_newest_message(topic)
    if msg_id:
        # Decode the keys for user convenience
        return {k.decode(): v for (k, v) in message.items()}
    return None


# Returns an array of all the commands as a hash
# @param target_name [String] Name of the target
# @return [Array<Hash>] Array of all commands as a hash
def get_all_cmds(target_name, scope=OPENC3_SCOPE, manual=False):
    target_name = target_name.upper()
    authorize(permission="cmd_info", target_name=target_name, scope=scope, manual=manual)
    return TargetModel.packets(target_name, type="CMD", scope=scope)


# get_all_commands is DEPRECATED
get_all_commands = get_all_cmds


# Returns an array of all the command packet names
# @param target_name [String] Name of the target
# @return [Array<String>] Array of all command packet names
def get_all_cmd_names(target_name, hidden=False, scope=OPENC3_SCOPE, manual=False):
    try:
        packets = get_all_cmds(target_name, scope=scope, manual=manual)
    except RuntimeError:
        packets = []
    names = []
    for packet in packets:
        if hidden:
            names.append(packet["packet_name"])
        else:
            if "hidden" not in packet:
                names.append(packet["packet_name"])
    return names


# get_all_command_names is DEPRECATED
get_all_command_names = get_all_cmd_names


# Returns a hash of the given command
def get_cmd(*args, scope=OPENC3_SCOPE, manual=False):
    target_name, command_name = _extract_target_command_names("get_cmd", *args)
    authorize(permission="cmd_info", target_name=target_name, scope=scope, manual=manual)
    return TargetModel.packet(target_name, command_name, type="CMD", scope=scope)


# get_command is DEPRECATED
get_command = get_cmd


# Returns a hash of the given command parameter
# @param target_name [String] Name of the target
# @param command_name [String] Name of the packet
# @param parameter_name [String] Name of the parameter
# @return [Hash] Command parameter as a hash
def get_param(*args, scope=OPENC3_SCOPE, manual=False):
    target_name, command_name, parameter_name = _extract_target_command_parameter_names("get_param", *args)
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    return TargetModel.packet_item(target_name, command_name, parameter_name, type="CMD", scope=scope)


# get_parameter is DEPRECATED
get_parameter = get_param


# Returns whether the specified command is hazardous
#
# Accepts two different calling styles:
#   get_cmd_hazardous("TGT CMD with PARAM1 val, PARAM2 val")
#   get_cmd_hazardous('TGT','CMD',{'PARAM1'=>val,'PARAM2'=>val})
#
# @param args [String|Array<String>] See the description for calling style
# @return [Boolean] Whether the command is hazardous
def get_cmd_hazardous(*args, scope=OPENC3_SCOPE, manual=False):
    match len(args):
        case 1:
            target_name, command_name, parameters = extract_fields_from_cmd_text(args[0])
            target_name = target_name.upper()
            command_name = command_name.upper()
            parameters = {k.upper(): v for k, v in parameters.items()}
        case 2 | 3:
            target_name = args[0].upper()
            command_name = args[1].upper()
            if len(args) == 2:
                parameters = {}
            else:
                parameters = args[2]

        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to get_cmd_hazardous()")

    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    packet = TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    if packet.get("hazardous") is not None:
        return True

    for item in packet["items"]:
        if item["name"] not in parameters and "states" not in item:
            continue

        # States are an array of the name followed by a dict of 'value' and sometimes 'hazardous'
        for name, items in item["states"].items():
            parameter_name = parameters[item["name"]]
            # Remove quotes from string parameters
            if isinstance(parameter_name, str):
                parameter_name = parameter_name.replace('"', "").replace("'", "")
            # To be hazardous the state must be marked hazardous
            # Check if either the state name or value matches the param passed
            if items.get("hazardous") is not None and (name == parameter_name or items["value"] == parameter_name):
                return True
    return False


# Returns a value from the specified command
def get_cmd_value(
    *args,
    type="CONVERTED",
    scope=OPENC3_SCOPE,
    manual=False,
):
    target_name = None
    command_name = None
    parameter_name = None
    match len(args):
        case 1:
            try:
                target_name, command_name, parameter_name = args[0].upper().split()
            except ValueError:
                # Do nothing because we catch it below
                pass
        case 3:
            target_name = args[0].upper()
            command_name = args[1].upper()
            parameter_name = args[2].upper()
        case 4:
            target_name = args[0].upper()
            command_name = args[1].upper()
            parameter_name = args[2].upper()
            type = args[3].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to get_cmd_value()")
    if target_name is None or command_name is None:
        raise RuntimeError(
            f'ERROR: Target name, command name and parameter name required. Usage: get_cmd_value("TGT CMD PARAM") or {method_name}("TGT", "CMD", "PARAM")'
        )

    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    return CommandDecomTopic.get_cmd_item(target_name, command_name, parameter_name, type=type, scope=scope)


# Returns the time the most recent command was sent
#
# @param target_name [String] Target name of the command. If not given then
#    the most recent time from all commands will be returned
# @param command_name [String] Packet name of the command. If not given then
#    then most recent time from the given target will be returned.
# @return [Array<Target Name, Command Name, Time Seconds, Time Microseconds>]
def get_cmd_time(target_name=None, command_name=None, scope=OPENC3_SCOPE, manual=False):
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    if target_name and command_name:
        target_name = target_name.upper()
        command_name = command_name.upper()
        time = CommandDecomTopic.get_cmd_item(
            target_name,
            command_name,
            "RECEIVED_TIMESECONDS",
            type="CONVERTED",
            scope=scope,
        )
        if time is None:
            time = 0
        return (
            target_name,
            command_name,
            int(time),
            int((time - int(time)) * 1_000_000),
        )
    else:
        if not target_name:
            targets = TargetModel.names(scope=scope)
        else:
            targets = [target_name.upper()]

        time = 0
        command_name = None
        for target_name in targets:
            for packet in TargetModel.packets(target_name, type="CMD", scope=scope):
                cur_time = CommandDecomTopic.get_cmd_item(
                    target_name,
                    packet["packet_name"],
                    "RECEIVED_TIMESECONDS",
                    type="CONVERTED",
                    scope=scope,
                )
                if not cur_time:
                    continue

                if cur_time > time:
                    time = cur_time
                    command_name = packet["packet_name"]

        if not command_name:
            target_name = None
        return (
            target_name,
            command_name,
            int(time),
            int((time - int(time)) * 1_000_000),
        )


# Get the transmit count for a command packet
#
# @param target_name [String] Target name of the command
# @param command_name [String] Packet name of the command
# @return [Numeric] Transmit count for the command
def get_cmd_cnt(*args, scope=OPENC3_SCOPE, manual=False):
    target_name, command_name = _extract_target_command_names("get_cmd_cnt", *args)
    authorize(
        permission="system",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    return TargetModel.get_command_count(target_name, command_name, scope=scope)


# Get the transmit counts for command packets
#
# @param target_commands [Array<Array<String, String>>] Array of arrays containing target_name, packet_name
# @return [Numeric] Transmit count for the command
def get_cmd_cnts(target_commands, scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    if isinstance(target_commands, list) and isinstance(target_commands[0], list):
        return TargetModel.get_command_counts(target_commands, scope=scope)
    else:
        raise RuntimeError(
            "get_cmd_cnts takes a dict of dicts containing target, packet_name, e.g. [['INST', 'COLLECT'], ['INST', 'ABORT']]"
        )


def _extract_target_command_names(method_name, *args):
    target_name = None
    command_name = None
    match len(args):
        case 1:
            try:
                target_name, command_name = args[0].upper().split()
            except ValueError:
                # Do nothing because we catch it below
                pass
        case 2:
            target_name = args[0].upper()
            command_name = args[1].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or command_name is None:
        raise RuntimeError(
            f'ERROR: Target name and command name required. Usage: {method_name}("TGT CMD") or {method_name}("TGT", "CMD")'
        )
    return (target_name, command_name)


def _extract_target_command_parameter_names(method_name, *args):
    target_name = None
    command_name = None
    parameter_name = None
    match len(args):
        case 1:
            try:
                target_name, command_name, parameter_name = args[0].upper().split()
            except ValueError:
                # Do nothing because we catch it below
                pass
        case 3:
            target_name = args[0].upper()
            command_name = args[1].upper()
            parameter_name = args[2].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or command_name is None:
        raise RuntimeError(
            f'ERROR: Target name, command name and parameter name required. Usage: {method_name}("TGT CMD PARAM") or {method_name}("TGT", "CMD", "PARAM")'
        )
    return (target_name, command_name, parameter_name)


def _cmd_implementation(
    method_name,
    *args,
    range_check,
    hazardous_check,
    raw,
    manual=False,
    **kwargs,
):
    scope = OPENC3_SCOPE
    if kwargs.get("scope"):
        scope = kwargs["scope"]

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
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")

    target_name = target_name.upper()
    cmd_name = cmd_name.upper()
    cmd_params = {k.upper(): v for k, v in cmd_params.items()}
    user = authorize(permission="cmd", target_name=target_name, packet_name=cmd_name, scope=scope, manual=manual)
    if not user:
        user = {}
        user["username"] = os.environ.get("OPENC3_MICROSERVICE_NAME")

        # Get the caller stack trace to determine the point in the code where the command was called
        # This code works but ultimately we didn't want to overload 'username' and take a performance hit
        # stack_trace = traceback.extract_stack()
        # for frame in stack_trace:
        #     # Look for the following line in the stack trace which indicates custom code
        #     # File "/tmp/tmpp96e6j83/targets/INST2/lib/example_limits_response.py", line 25, in call"
        #     if f"/targets/{target_name}" in frame.filename:
        #         user = {}
        #         # username is the name of the custom code file
        #         user["username"] = frame.filename.split("/targets/")[-1].split('"')[0]
        #         break

    packet = TargetModel.packet(target_name, cmd_name, type="CMD", scope=scope)
    if packet.get("disabled", False):
        error = DisabledError()
        error.target_name = target_name
        error.cmd_name = cmd_name
        raise error

    timeout = None
    if kwargs.get("timeout") is not None:
        try:
            timeout = float(kwargs["timeout"])
        except ValueError:
            raise RuntimeError(f"Invalid timeout parameter: {timeout}. Must be numeric.")

    # Determine if we should log this command
    log_message = True  # Default is True
    # If the packet has the DISABLE_MESSAGES keyword then no messages
    if packet.get("messages_disabled"):
        log_message = False
    else:
        # Check if any of the parameters have DISABLE_MESSAGES
        for key, value in cmd_params.items():
            found = None
            for item in packet["items"]:
                if item["name"] == key:
                    found = item
                    break
            if (
                found
                and "states" in found
                and value in found["states"]
                and found["states"][value].get("messages_disabled")
            ):
                log_message = False
    # If they explicitly set the log_message kwarg then that overrides the above
    if kwargs.get("log_message") is not None:
        if kwargs["log_message"] not in [True, False]:
            raise RuntimeError(f"Invalid log_message parameter: {kwargs['log_message']}. Must be True or False.")
        log_message = kwargs["log_message"]
    cmd_string = _cmd_log_string(method_name, target_name, cmd_name, cmd_params, packet)

    # Check for the validate kwarg
    validate = True
    if kwargs.get("validate") is not None:
        if kwargs["validate"] not in [True, False]:
            raise RuntimeError(f"Invalid validate parameter: {kwargs['validate']}. Must be True or False.")
        validate = kwargs["validate"]

    username = user["username"] if user and user["username"] else "anonymous"
    command = {
        "target_name": target_name,
        "cmd_name": cmd_name,
        "cmd_params": cmd_params,
        "range_check": str(range_check),
        "hazardous_check": str(hazardous_check),
        "raw": str(raw),
        "cmd_string": cmd_string,
        "username": username,
        "validate": str(validate),
        "manual": str(manual),
        "log_message": str(log_message),
    }
    return CommandTopic.send_command(command, timeout, scope)


def _cmd_log_string(method_name, target_name, cmd_name, cmd_params, packet):
    output_string = f'{method_name}("'
    output_string += target_name + " " + cmd_name
    if not cmd_params:
        output_string += '")'
    else:
        params = []
        for key, value in cmd_params.items():
            if key in Packet.RESERVED_ITEM_NAMES:
                continue

            found = False
            for item in packet["items"]:
                if item["name"] == key:
                    found = item
                    break
            if found and "data_type" in found:
                item_type = found["data_type"]
            else:
                item_type = None

            if isinstance(value, str):
                if item_type == "BLOCK" or item_type == "STRING":
                    if not value.isascii():
                        value = "0x" + simple_formatted(value)
                    else:
                        value = f"'{str(value)}'"
                else:
                    value = convert_to_value(value)
                if len(value) > 256:
                    value = value[:256] + "...'"
                value = value.replace('"', "'")
            elif isinstance(value, list):
                value = f"[{', '.join(str(i) for i in value)}]"
            params.append(f"{key} {value}")
        output_string += " with " + ", ".join(params) + '")'
    return output_string
