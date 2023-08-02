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
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.models.interface_model import InterfaceModel

# from openc3.utilities.logger import Logger

# require 'openc3/models/interface_model'
# require 'openc3/models/interface_status_model'
# require 'openc3/topics/interface_topic'


WHITELIST.extend(
    [
        "get_interface",
        "get_interface_names",
        "connect_interface",
        "disconnect_interface",
        "start_raw_logging_interface",
        "stop_raw_logging_interface",
        "get_all_interface_info",
        "map_target_to_interface",
        "interface_cmd",
        "interface_protocol_cmd",
    ]
)


# Get information about an interface
#
# @since 5.0.0
# @param interface_name [String] Interface name
# @return [Hash] Hash of all the interface information
def get_interface(interface_name, scope=OPENC3_SCOPE):
    authorize(permission="system", interface_name=interface_name, scope=scope)
    interface = InterfaceModel.get(name=interface_name, scope=scope)
    if not interface:
        raise RuntimeError(f"Interface '{interface_name}' does not exist")
    return interface
    # interface.merge(InterfaceStatusModel.get(name=interface_name, scope=scope))


# @return [Array<String>] All the interface names
def get_interface_names(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    InterfaceModel.names(scope=scope)


# # Connects an interface and starts its telemetry gathering thread
# #
# # @param interface_name [String] The name of the interface
# # @param interface_params [Array] Optional parameters to pass to the interface
# def connect_interface(interface_name, *interface_params, scope=OPENC3_SCOPE):
#   authorize(permission: 'system_set', interface_name: interface_name, scope: scope)
#   InterfaceTopic.connect_interface(interface_name, *interface_params, scope: scope)


# # Disconnects from an interface and kills its telemetry gathering thread
# #
# # @param interface_name [String] The name of the interface
# def disconnect_interface(interface_name, scope=OPENC3_SCOPE):
#   authorize(permission: 'system_set', interface_name: interface_name, scope: scope)
#   InterfaceTopic.disconnect_interface(interface_name, scope: scope)


# # Starts raw logging for an interface
# #
# # @param interface_name [String] The name of the interface
# def start_raw_logging_interface(interface_name = 'ALL', scope=OPENC3_SCOPE):
#   authorize(permission: 'system_set', interface_name: interface_name, scope: scope)
#   if interface_name == 'ALL'
#     get_interface_names().each do |interface_name|
#       InterfaceTopic.start_raw_logging(interface_name, scope: scope)

#   else
#     InterfaceTopic.start_raw_logging(interface_name, scope: scope)


# # Stop raw logging for an interface
# #
# # @param interface_name [String] The name of the interface
# def stop_raw_logging_interface(interface_name = 'ALL', scope=OPENC3_SCOPE):
#   authorize(permission: 'system_set', interface_name: interface_name, scope: scope)
#   if interface_name == 'ALL'
#     get_interface_names().each do |interface_name|
#       InterfaceTopic.stop_raw_logging(interface_name, scope: scope)

#   else
#     InterfaceTopic.stop_raw_logging(interface_name, scope: scope)


# # Get information about all interfaces
# #
# # @return [Array<Array<String, Numeric, Numeric, Numeric, Numeric, Numeric,
# #   Numeric, Numeric>>] Array of Arrays containing \[name, state, num clients,
# #   TX queue size, RX queue size, TX bytes, RX bytes, Command count,
# #   Telemetry count] for all interfaces
# def get_all_interface_info(scope=OPENC3_SCOPE):
#   authorize(permission: 'system', scope: scope)
#   info = []
#   InterfaceStatusModel.all(scope: scope).each do |int_name, int|
#     info << [int['name'], int['state'], int['clients'], int['txsize'], int['rxsize'],
#              int['txbytes'], int['rxbytes'], int['txcnt'], int['rxcnt']]

#   info.sort! { |a, b| a[0] <=> b[0] }
#   info


# # Associates a target and all its commands and telemetry with a particular
# # interface. All the commands will go out over and telemetry be received
# # from that interface.
# #
# # @param target_name [String/Array] The name of the target(s)
# # @param interface_name (see #connect_interface)
# def map_target_to_interface(target_name, interface_name, cmd_only: false, tlm_only: false, unmap_old: true, scope=OPENC3_SCOPE):
#   authorize(permission: 'system_set', interface_name: interface_name, scope: scope)
#   new_interface = InterfaceModel.get_model(name: interface_name, scope: scope)
#   if Array === target_name
#     target_names = target_name
#   else
#     target_names = [target_name]

#   target_names.each do |name|
#     new_interface.map_target(name, cmd_only: cmd_only, tlm_only: tlm_only, unmap_old: unmap_old)
#     Logger.info("Target #{name} mapped to Interface #{interface_name}", scope: scope)

#   nil


# def interface_cmd(interface_name, cmd_name, *cmd_params, scope=OPENC3_SCOPE):
#   authorize(permission: 'system_set', interface_name: interface_name, scope: scope)
#   InterfaceTopic.interface_cmd(interface_name, cmd_name, *cmd_params, scope: scope)


# def interface_protocol_cmd(interface_name, cmd_name, *cmd_params, read_write: :READ_WRITE, index: -1, scope=OPENC3_SCOPE):
#   authorize(permission: 'system_set', interface_name: interface_name, scope: scope)
#   InterfaceTopic.protocol_cmd(interface_name, cmd_name, *cmd_params, read_write: read_write, index: index, scope: scope)
