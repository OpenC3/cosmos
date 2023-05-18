#!/usr/bin/env python3
# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
# -*- coding: latin-1 -*-
"""
environment.py
"""

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Lesser General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt

import os

from cosmosc2.__version__ import __title__, __version__

_cosmos_version = "COSMOS_VERSION"

_cosmos_api_user = "COSMOS_API_USER"

_cosmos_api_client = "COSMOS_API_CLIENT"

_cosmos_api_password = "COSMOS_API_PASSWORD"

_default_scope = "COSMOS_SCOPE"

_cosmos_api_schema = "COSMOS_API_SCHEMA"

_default_ws_schema = "COSMOS_WS_SCHEMA"

_cosmos_api_hostname = "COSMOS_API_HOSTNAME"

_cosmos_api_port = "COSMOS_API_PORT"

_json_rpc_version = "COSMOS_JSON_RPC_VERSION"

_log_level = "COSMOS_LOG_LEVEL"

_max_retry_count = "COSMOS_MAX_RETRY_COUNT"

_user_agent = "COSMOS_USER_AGENT"

COSMOS_API_SCHEMA = os.environ.get(_cosmos_api_schema, "http")

COSMOS_WS_SCHEMA = os.environ.get(_default_ws_schema, "ws")

COSMOS_API_HOSTNAME = os.environ.get(_cosmos_api_hostname, "127.0.0.1")

try:
    COSMOS_API_PORT = int(os.environ.get(_cosmos_api_port))
except TypeError:
    COSMOS_API_PORT = 2900

COSMOS_SCOPE = os.environ.get(_default_scope, "DEFAULT")

COSMOS_API_USER = os.environ.get(_cosmos_api_user)

COSMOS_API_CLIENT = os.environ.get(_cosmos_api_client, "api")

COSMOS_API_PASSWORD = os.environ.get(_cosmos_api_password, "SuperSecret")

COSMOS_VERSION = os.environ.get(_cosmos_version)

JSON_RPC_VERSION = os.environ.get(_json_rpc_version, "2.0")

LOG_LEVEL = os.environ.get(_log_level, "INFO")

try:
    MAX_RETRY_COUNT = int(os.environ.get(_max_retry_count))
except TypeError:
    MAX_RETRY_COUNT = 3

_default_user_agent = [
    f"{__title__}:{__version__}:{JSON_RPC_VERSION}:({COSMOS_VERSION})",
]

if COSMOS_API_USER is not None:
    _default_user_agent[0] += f":({COSMOS_API_USER})"

if os.name == "nt":
    _default_user_agent.append(
        f"{os.environ.get('COMPUTERNAME')}:{os.environ.get('USERNAME')}"
    )
else:
    _default_user_agent.append(f"{os.environ.get('HOSTNAME')}:{os.environ.get('USER')}")

USER_AGENT = os.environ.get(_user_agent, " ".join(_default_user_agent))
