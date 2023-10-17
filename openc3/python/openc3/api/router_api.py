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
from openc3.models.router_model import RouterModel
from openc3.models.router_status_model import RouterStatusModel
from openc3.topics.router_topic import RouterTopic

WHITELIST.extend(
    [
        "get_router",
        "get_router_names",
        "connect_router",
        "disconnect_router",
        "start_raw_logging_router",
        "stop_raw_logging_router",
        "get_all_router_info",
        "router_cmd",
        "router_protocol_cmd",
    ]
)


# Get information about an router
#
# @since 5.0.0
# @param router_name [String] Router name
# @return [Hash] Hash of all the router information
def get_router(router_name, scope=OPENC3_SCOPE):
    authorize(permission="system", router_name=router_name, scope=scope)
    router = RouterModel.get(name=router_name, scope=scope)
    if not router:
        raise RuntimeError(f"Router '{router_name}' does not exist")
    return router | RouterStatusModel.get(name=router_name, scope=scope)


# @return [Array<String>] All the router names
def get_router_names(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    return RouterModel.names(scope=scope)


# Connects an router and starts its telemetry gathering thread
#
# @param router_name [String] The name of the router
# @param router_params [Array] Optional parameters to pass to the router
def connect_router(router_name, *router_params, scope=OPENC3_SCOPE):
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.connect_router(router_name, *router_params, scope=scope)


# Disconnects from an router and kills its telemetry gathering thread
#
# @param router_name [String] The name of the router
def disconnect_router(router_name, scope=OPENC3_SCOPE):
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.disconnect_router(router_name, scope=scope)


# Starts raw logging for an router
#
# @param router_name [String] The name of the router
def start_raw_logging_router(router_name="ALL", scope=OPENC3_SCOPE):
    authorize(permission="system_set", router_name=router_name, scope=scope)
    if router_name == "ALL":
        for router_name in get_router_names():
            RouterTopic.start_raw_logging(router_name, scope=scope)
    else:
        RouterTopic.start_raw_logging(router_name, scope=scope)


# Stop raw logging for an router
#
# @param router_name [String] The name of the router
def stop_raw_logging_router(router_name="ALL", scope=OPENC3_SCOPE):
    authorize(permission="system_set", router_name=router_name, scope=scope)
    if router_name == "ALL":
        for router_name in get_router_names():
            RouterTopic.stop_raw_logging(router_name, scope=scope)
    else:
        RouterTopic.stop_raw_logging(router_name, scope=scope)


# Consolidate all router info into a single API call
#
# @return [Array<Array<String, Numeric, Numeric, Numeric, Numeric, Numeric,
#   Numeric, Numeric>>] Array of Arrays containing \[name, state, num clients,
#   TX queue size, RX queue size, TX bytes, RX bytes, Command count,
#   Telemetry count] for all routers
def get_all_router_info(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    info = []
    for _, router in RouterStatusModel.all(scope=scope).items():
        info.append(
            [
                router["name"],
                router["state"],
                router["clients"],
                router["txsize"],
                router["rxsize"],
                router["txbytes"],
                router["rxbytes"],
                router["rxcnt"],
                router["txcnt"],
            ]
        )
    return info


def router_cmd(router_name, cmd_name, *cmd_params, scope=OPENC3_SCOPE):
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.router_cmd(router_name, cmd_name, *cmd_params, scope=scope)


def router_protocol_cmd(
    router_name,
    cmd_name,
    *cmd_params,
    read_write="READ_WRITE",
    index=-1,
    scope=OPENC3_SCOPE,
):
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.protocol_cmd(
        router_name,
        cmd_name,
        *cmd_params,
        read_write=read_write,
        index=index,
        scope=scope,
    )
