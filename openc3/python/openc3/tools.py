#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
tools.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import cosmosc2


def list_settings():
    return cosmosc2.COSMOS.json_rpc_request("list_settings", [])


def get_all_settings():
    return cosmosc2.COSMOS.json_rpc_request("get_all_settings", [])


def get_setting(name):
    return cosmosc2.COSMOS.json_rpc_request("get_setting", [name])


def get_settings(settings_list):
    return cosmosc2.COSMOS.json_rpc_request("get_settings", settings_list)


def save_setting(name, data):
    return cosmosc2.COSMOS.json_rpc_request("save_setting", [name, data])


def list_configs(tool):
    return cosmosc2.COSMOS.json_rpc_request("list_configs", [tool])


def load_config(tool, name):
    return cosmosc2.COSMOS.json_rpc_request("load_config", [tool, name])


def save_config(tool, name, data):
    return cosmosc2.COSMOS.json_rpc_request("save_config", [tool, name, data])


def delete_config(tool, name):
    return cosmosc2.COSMOS.json_rpc_request("delete_config", [tool, name])


def get_screen_list(config_filename=None, force_refresh=False):
    """Get the organized list of available telemetry screens"""
    return cosmosc2.COSMOS.json_rpc_request(
        "get_screen_list", config_filename, force_refresh
    )


def get_screen_definition(screen_full_name, config_filename=None, force_refresh=False):
    """Get a specific screen definition"""
    return cosmosc2.COSMOS.json_rpc_request(
        "get_screen_definition", screen_full_name, config_filename, force_refresh
    )
