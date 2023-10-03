#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
cmd_tlm_server.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import openc3.script

DEFAULT_SERVER_MESSAGES_QUEUE_SIZE = 1000


def get_interface_names():
    """The get_interface_names method returns a list of the interfaces in the system in an array.
    Syntax / Example:
        interface_names = get_interface_names()
    """
    return openc3.script.API_SERVER.json_rpc_request("get_interface_names")


def connect_interface(interface_name, *params):
    """The connect_interface method connects to targets associated with a openc3.script.API_SERVER interface.
    Syntax:
        connect_interface("<Interface Name>", <Interface Parameters (optional)>)
    """
    return openc3.script.API_SERVER.json_rpc_request(
        "connect_interface", interface_name, *params
    )


def disconnect_interface(interface_name):
    """The disconnect_interface method disconnects from targets associated with a openc3.script.API_SERVER interface.
    Syntax:
        disconnect_interface("<Interface Name>")
    """
    return openc3.script.API_SERVER.json_rpc_request(
        "disconnect_interface", interface_name
    )


def get_router_names():
    """The get_router_names method returns a list of the routers in the
    system in an array.
    Syntax:
        router_names = get_router_names()
    """
    return openc3.script.API_SERVER.json_rpc_request("get_router_names")


def get_all_router_info():
    """The get_all_router_info method returns information about all routers.
    The return value is an array of arrays where each subarray contains the
    router name, connection state, number of connected clients, transmit queue
    size, receive queue size, bytes transmitted, bytes received, packets
    received, and packets sent.
    Syntax:
        router_info = get_all_router_info()
    """
    return openc3.script.API_SERVER.json_rpc_request("get_all_router_info")


def connect_router(router_name, *params):
    """The connect_router method connects a openc3.script.API_SERVER router.
    Syntax:
        connect_router("<Router Name>", <Router Parameters (optional)>)
    """
    return openc3.script.API_SERVER.json_rpc_request(
        "connect_router", router_name, *params
    )


def disconnect_router(router_name):
    """The disconnect_router method disconnects a openc3.script.API_SERVER router.
    Syntax:
        disconnect_router("<Router Name>")
    """
    return openc3.script.API_SERVER.json_rpc_request("disconnect_router", router_name)


def get_all_target_info():
    """The get_all_target_info method returns information about all targets.
    The return value is an array of arrays where each subarray contains the
    target name, interface name, command count, and telemetry count for a target.
    Syntax:
        target_info = get_all_target_info()
    """
    return openc3.script.API_SERVER.json_rpc_request("get_all_target_info")


def get_all_interface_info():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_all_interface_info")


def get_all_cmd_info():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_all_cmd_info")


def get_all_tlm_info():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_all_tlm_info")


def get_cmd_cnt(target_name, command_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_cmd_cnt", target_name, command_name
    )


def get_tlm_cnt(target_name, packet_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_tlm_cnt", target_name, packet_name
    )


def subscribe_server_messages(queue_size=DEFAULT_SERVER_MESSAGES_QUEUE_SIZE):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "subscribe_server_messages", queue_size
    )


def unsubscribe_server_messages(id_):
    """ """
    return openc3.script.API_SERVER.json_rpc_request("unsubscribe_server_messages", id_)
