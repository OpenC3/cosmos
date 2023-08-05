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


def get_target_ignored_parameters(target_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_target_ignored_parameters", target_name
    )


def get_target_ignored_items(target_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_target_ignored_items", target_name
    )


def get_interface_info(interface_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_interface_info", interface_name
    )


def get_all_interface_info():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_all_interface_info")


def get_router_info(router_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_router_info", router_name)


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


def get_packet_loggers():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_packet_loggers")


def get_packet_logger_info(packet_logger_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_packet_logger_info", packet_logger_name
    )


def get_all_packet_logger_info():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_all_packet_logger_info")


def get_background_tasks():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_background_tasks")


def start_background_task(task_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request("start_background_task", task_name)


def stop_background_task(task_name):
    """ """
    return openc3.script.API_SERVER.json_rpc_request("stop_background_task", task_name)


def get_server_status():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_server_status")


def get_cmd_log_filename(packet_log_writer_name="DEFAULT"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_cmd_log_filename", packet_log_writer_name
    )


def get_tlm_log_filename(packet_log_writer_name="DEFAULT"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_tlm_log_filename", packet_log_writer_name
    )


def start_logging(packet_log_writer_name="ALL", label=None):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "start_logging", packet_log_writer_name, label
    )


def stop_logging(packet_log_writer_name="ALL"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "stop_logging", packet_log_writer_name
    )


def start_cmd_log(packet_log_writer_name="ALL", label=None):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "start_cmd_log", packet_log_writer_name, label
    )


def start_tlm_log(packet_log_writer_name="ALL", label=None):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "start_tlm_log", packet_log_writer_name, label
    )


def stop_cmd_log(packet_log_writer_name="ALL"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "stop_cmd_log", packet_log_writer_name
    )


def stop_tlm_log(packet_log_writer_name="ALL"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "stop_tlm_log", packet_log_writer_name
    )


def start_raw_logging_interface(interface_name="ALL"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "start_raw_logging_interface", interface_name
    )


def stop_raw_logging_interface(interface_name="ALL"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "stop_raw_logging_interface", interface_name
    )


def start_raw_logging_router(router_name="ALL"):
    """The start_raw_logging_router method starts logging of raw data on one or all routers. This is for debugging purposes only.
    Syntax:
        start_raw_logging_router("<Router Name (optional)>")
    """
    return openc3.script.API_SERVER.json_rpc_request(
        "start_raw_logging_router", router_name
    )


def stop_raw_logging_router(router_name="ALL"):
    """The stop_raw_logging_router method stops logging of raw data on one or all routers. This is for debugging purposes only.
    Syntax:
        stop_raw_logging_router("<Router Name (optional)>")
    """
    return openc3.script.API_SERVER.json_rpc_request(
        "stop_raw_logging_router", router_name
    )


def get_server_message_log_filename():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("get_server_message_log_filename")


def start_new_server_message_log():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("start_new_server_message_log")


def subscribe_server_messages(queue_size=DEFAULT_SERVER_MESSAGES_QUEUE_SIZE):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "subscribe_server_messages", queue_size
    )


def unsubscribe_server_messages(id_):
    """ """
    return openc3.script.API_SERVER.json_rpc_request("unsubscribe_server_messages", id_)


def get_server_message(id_, non_block=False):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_server_message", id_, non_block
    )


def cmd_tlm_reload():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("cmd_tlm_reload")


def cmd_tlm_clear_counters():
    """ """
    return openc3.script.API_SERVER.json_rpc_request("cmd_tlm_clear_counters")


def get_output_logs_filenames(filter_="*tlm.bin"):
    """ """
    return openc3.script.API_SERVER.json_rpc_request(
        "get_output_logs_filenames", filter_
    )
