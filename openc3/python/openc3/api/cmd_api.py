#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
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

from openc3.api import WHITELIST
from openc3.api.interface_api import get_interface
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.utilities.logger import Logger
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
        "build_command",
        "send_raw",
        "get_all_commands",
        "get_all_command_names",
        "get_command",
        "get_parameter",
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
    return cmd_implementation(
        "cmd", *args, range_check=True, hazardous_check=True, raw=False, **kwargs
    )


def cmd_raw(*args, **kwargs):
    return cmd_implementation(
        "cmd_raw", *args, range_check=True, hazardous_check=True, raw=True, **kwargs
    )


# S a command packet to a target without performing any value range
# checks on the parameters. Useful for testing to allow sing command
# parameters outside the allowable range as defined in the configuration.
def cmd_no_range_check(*args, **kwargs):
    return cmd_implementation(
        "cmd_no_range_check",
        *args,
        range_check=False,
        hazardous_check=True,
        raw=False,
        **kwargs,
    )


def cmd_raw_no_range_check(*args, **kwargs):
    return cmd_implementation(
        "cmd_raw_no_range_check",
        *args,
        range_check=False,
        hazardous_check=True,
        raw=True,
        **kwargs,
    )


# S a command packet to a target without performing any hazardous checks
# both on the command itself and its parameters. Useful in scripts to
# prevent popping up warnings to the user.
def cmd_no_hazardous_check(*args, **kwargs):
    return cmd_implementation(
        "cmd_no_hazardous_check",
        *args,
        range_check=True,
        hazardous_check=False,
        raw=False,
        **kwargs,
    )


def cmd_raw_no_hazardous_check(*args, **kwargs):
    return cmd_implementation(
        "cmd_raw_no_hazardous_check",
        *args,
        range_check=True,
        hazardous_check=False,
        raw=True,
        **kwargs,
    )


# S a command packet to a target without performing any value range
# checks or hazardous checks both on the command itself and its parameters.
def cmd_no_checks(*args, **kwargs):
    return cmd_implementation(
        "cmd_no_checks",
        *args,
        range_check=False,
        hazardous_check=False,
        raw=False,
        **kwargs,
    )


def cmd_raw_no_checks(*args, **kwargs):
    return cmd_implementation(
        "cmd_raw_no_checks",
        *args,
        range_check=False,
        hazardous_check=False,
        raw=True,
        **kwargs,
    )


# Build a command binary
def build_command(
    self, *args, range_check=True, raw=False, scope=OPENC3_SCOPE, **kwargs
):
    self.extract_string_kwargs_to_args(args, kwargs)
    match len(args):
        case 1:
            target_name, cmd_name, cmd_params = self.extract_fields_from_cmd_text(
                args[0]
            )
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
                f"ERROR: Invalid number of arguments ({len(args)}) passed to build_command()"
            )
    target_name = target_name.upper()
    cmd_name = cmd_name.upper()
    cmd_params = {k.upper(): v for k, v in cmd_params.items()}
    authorize(permission="cmd_info", target_name=target_name, scope=scope)
    DecomInterfaceTopic.build_cmd(
        target_name, cmd_name, cmd_params, range_check, raw, scope
    )


# Send a raw binary string to the specified interface.
#
# @param interface_name [String] The interface to s the raw binary
# @param data [String] The raw binary data
def send_raw(interface_name, data, scope=OPENC3_SCOPE):
    interface_name = interface_name.upper()
    authorize(permission="cmd_raw", interface_name=interface_name, scope=scope)
    get_interface(
        interface_name, scope=scope
    )  # Check to make sure the interface exists
    InterfaceTopic.write_raw(interface_name, data, scope=scope)


# Returns the raw buffer from the most recent specified command packet.
#
# @param target_name [String] Target name of the command
# @param command_name [String] Packet name of the command
# @return [Hash] command hash with last command buffer
def get_cmd_buffer(target_name, command_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    command_name = command_name.upper()
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
    )
    TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    topic = f"{scope}__COMMAND__{{{target_name}}}__{command_name}"
    msg_id, msg_hash = Topic.get_newest_message(topic)
    if msg_id:
        # TODO: Python equivalent of .b?
        # msg_hash["buffer"] = msg_hash["buffer"].b
        return msg_hash
    return None


# Returns an array of all the commands as a hash
# @param target_name [String] Name of the target
# @return [Array<Hash>] Array of all commands as a hash
def get_all_commands(target_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    authorize(permission="cmd_info", target_name=target_name, scope=scope)
    TargetModel.packets(target_name, type="CMD", scope=scope)


# Returns an array of all the command packet names
# @param target_name [String] Name of the target
# @return [Array<String>] Array of all command packet names
def get_all_command_names(target_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    authorize(permission="cmd_info", target_name=target_name, scope=scope)
    TargetModel.packet_names(target_name, type="CMD", scope=scope)


# Returns a hash of the given command
# @param target_name [String] Name of the target
# @param command_name [String] Name of the packet
# @return [Hash] Command as a hash
def get_command(target_name, command_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    command_name = command_name.upper()
    authorize(permission="cmd_info", target_name=target_name, scope=scope)
    TargetModel.packet(target_name, command_name, type="CMD", scope=scope)


# Returns a hash of the given command parameter
# @param target_name [String] Name of the target
# @param command_name [String] Name of the packet
# @param parameter_name [String] Name of the parameter
# @return [Hash] Command parameter as a hash
def get_parameter(target_name, command_name, parameter_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    command_name = command_name.upper()
    parameter_name = parameter_name.upper()
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
    )
    TargetModel.packet_item(
        target_name, command_name, parameter_name, type="CMD", scope=scope
    )


# Returns whether the specified command is hazardous
#
# Accepts two different calling styles:
#   get_cmd_hazardous("TGT CMD with PARAM1 val, PARAM2 val")
#   get_cmd_hazardous('TGT','CMD',{'PARAM1'=>val,'PARAM2'=>val})
#
# @param args [String|Array<String>] See the description for calling style
# @return [Boolean] Whether the command is hazardous
def get_cmd_hazardous(self, *args, scope=OPENC3_SCOPE, **kwargs):
    self.extract_string_kwargs_to_args(args, kwargs)
    match len(args):
        case 1:
            target_name, command_name, parameters = extract_fields_from_cmd_text(
                args[0]
            )
        case 2 | 3:
            target_name = args[0]
            command_name = args[1]
            if len(args) == 2:
                parameters = {}
            else:
                parameters = args[2]

        case _:
            # Invalid number of arguments
            raise RuntimeError(
                f"ERROR: Invalid number of arguments ({len(args)}) passed to get_cmd_hazardous()"
            )

    target_name = target_name.upper()
    command_name = command_name.upper()
    parameters = {k.upper(): v for k, v in parameters.items()}

    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
    )
    packet = TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    if packet["hazardous"]:
        return True

    for item in packet["items"]:
        if item["name"] not in parameters and "states" not in item:
            continue

        # States are an array of the name followed by a hash of 'value' and sometimes 'hazardous'
        for name, hash in item["states"]:
            parameter_name = parameters[item["name"]]
            # Remove quotes from string parameters
            if type(parameter_name) == str:
                parameter_name = parameter_name.gsub('"', "").gsub("'", "")
            # To be hazardous the state must be marked hazardous
            # Check if either the state name or value matches the param passed
            if hash["hazardous"] and (
                name == parameter_name or hash["value"] == parameter_name
            ):
                return True
    return False


# Returns a value from the specified command
#
# @param target_name [String] Target name of the command
# @param command_name [String] Packet name of the command
# @param parameter_name [String] Parameter name in the command
# @param value_type [Symbol] How the values should be converted. Must be
#   one of {Packet::VALUE_TYPES}
# @return [Varies] value
def get_cmd_value(
    target_name,
    command_name,
    parameter_name,
    value_type="CONVERTED",
    scope=OPENC3_SCOPE,
):
    target_name = target_name.upper()
    command_name = command_name.upper()
    parameter_name = parameter_name.upper()
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
    )
    CommandDecomTopic.get_cmd_item(
        target_name, command_name, parameter_name, type=value_type, scope=scope
    )


# Returns the time the most recent command was sent
#
# @param target_name [String] Target name of the command. If not given then
#    the most recent time from all commands will be returned
# @param command_name [String] Packet name of the command. If not given then
#    then most recent time from the given target will be returned.
# @return [Array<Target Name, Command Name, Time Seconds, Time Microseconds>]
def get_cmd_time(target_name=None, command_name=None, scope=OPENC3_SCOPE):
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
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
        return [target_name, command_name, int(time), (time - int(time)) * 1_000_000]
    else:
        if not target_name:
            targets = TargetModel.names(scope=scope)
        else:
            targets = [target_name.upper()]

        for target_name in targets:
            time = 0
            command_name = None
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
            return [
                target_name,
                command_name,
                int(time),
                (time.to_f - int(time)) * 1_000_000,
            ]


# Get the transmit count for a command packet
#
# @param target_name [String] Target name of the command
# @param command_name [String] Packet name of the command
# @return [Numeric] Transmit count for the command
def get_cmd_cnt(target_name, command_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    command_name = command_name.upper()
    authorize(
        permission="system",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
    )
    TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    Topic.get_cnt(f"{scope}__COMMAND__{{{target_name}}}__{command_name}")


# Get the transmit counts for command packets
#
# @param target_commands [Array<Array<String, String>>] Array of arrays containing target_name, packet_name
# @return [Numeric] Transmit count for the command
def get_cmd_cnts(target_commands, scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    counts = []
    for target_name, command_name in target_commands:
        target_name = target_name.upper()
        command_name = command_name.upper()
        counts << Topic.get_cnt(f"{scope}__COMMAND__{{{target_name}}}__{command_name}")
    return counts


###########################################################################
# PRIVATE implementation details
###########################################################################


def cmd_implementation(
    method_name,
    *args,
    range_check,
    hazardous_check,
    raw,
    timeout=None,
    log_message=None,
    scope=OPENC3_SCOPE,
    **kwargs,
):
    # extract_string_kwargs_to_args(args, kwargs)
    if log_message not in [None, True, False]:
        raise RuntimeError(
            f"Invalid log_message parameter: {log_message}. Must be True or False."
        )
    if timeout is not None:
        try:
            float(timeout)
        except ValueError:
            raise RuntimeError(
                f"Invalid timeout parameter: {timeout}. Must be numeric."
            )

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
                f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()"
            )

    target_name = target_name.upper()
    cmd_name = cmd_name.upper()
    cmd_params = {k.upper(): v for k, v in cmd_params.items()}
    authorize(
        permission="cmd", target_name=target_name, packet_name=cmd_name, scope=scope
    )
    packet = TargetModel.packet(target_name, cmd_name, type="CMD", scope=scope)

    command = {
        "target_name": target_name,
        "cmd_name": cmd_name,
        "cmd_params": cmd_params,
        "range_check": str(range_check),
        "hazardous_check": str(hazardous_check),
        "raw": str(raw),
    }
    if log_message is None:  # This means the default was used, no argument was passed
        log_message = True  # Default is True
        # If the packet has the DISABLE_MESSAGES keyword then no messages by default
        if packet.get("messages_disabled"):
            log_message = False
        # Check if any of the parameters have DISABLE_MESSAGES
        for key, value in cmd_params.items():
            found = None
            for item in packet["items"]:
                if item["name"] == key:
                    found = item
                    break
            if (
                found
                and found["states"]
                and found["states"][value]
                and found["states"][value].get("messages_disabled")
            ):
                log_message = False
    if log_message:
        Logger.info(
            build_cmd_output_string(target_name, cmd_name, cmd_params, packet, raw),
            scope,
        )
    return CommandTopic.send_command(command, timeout, scope)


def build_cmd_output_string(target_name, cmd_name, cmd_params, packet, raw):
    if raw:
        output_string = 'cmd_raw("'
    else:
        output_string = 'cmd("'
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
        if found:
            item_type = found["data_type"]
        else:
            item_type = None

        if type(value) == str:
            value = value.dup
            if item_type == "BLOCK" or item_type == "STRING":
                if value.isascii():
                    value = "0x" + value.simple_formatted
                else:
                    value = str(value)
            else:
                value = convert_to_value(value)
            if len(value) > 256:
                value = value[:255] + "...'"
            value = value.replace('"', "'")
        elif type(value) == list:
            value = f"[{', '.join(value)}]"
        params.append(f"{key} {value}")
        params = ", ".join(params)
        output_string += " with " + params + '")'
    return output_string
