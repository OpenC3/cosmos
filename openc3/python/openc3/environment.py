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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os

from openc3.__version__ import __title__, __version__

_openc3_api_schema = "OPENC3_API_SCHEMA"
_openc3_api_hostname = "OPENC3_API_HOSTNAME"
_openc3_api_port = "OPENC3_API_PORT"
_openc3_api_timeout = "OPENC3_API_TIMEOUT"
_openc3_script_api_schema = "OPENC3_SCRIPT_API_SCHEMA"
_openc3_script_api_hostname = "OPENC3_SCRIPT_API_HOSTNAME"
_openc3_script_api_port = "OPENC3_SCRIPT_API_PORT"
_openc3_script_api_timeout = "OPENC3_SCRIPT_API_TIMEOUT"
_openc3_scope = "OPENC3_SCOPE"
_openc3_api_password = "OPENC3_API_PASSWORD"
_openc3_log_level = "OPENC3_LOG_LEVEL"
_openc3_no_store = "OPENC3_NO_STORE"
_openc3_user_agent = "OPENC3_USER_AGENT"
_openc3_redis_hostname = "OPENC3_REDIS_HOSTNAME"
_openc3_redis_port = "OPENC3_REDIS_PORT"
_openc3_redis_username = "OPENC3_REDIS_USERNAME"
_openc3_redis_password = "OPENC3_REDIS_PASSORD"
_openc3_redis_ephemeral_hostname = "OPENC3_REDIS_EPHEMERAL_HOSTNAME"
_openc3_redis_ephemeral_port = "OPENC3_REDIS_EPHEMERAL_PORT"

# The following variables are only used with Enterprise Edition
_openc3_api_user = "OPENC3_API_USER"
_openc3_api_client = "OPENC3_API_CLIENT"
_openc3_api_token = "OPENC3_API_TOKEN"
_openc3_keycloak_realm = "OPENC3_KEYCLOAK_REALM"
_openc3_keycloak_url = "OPENC3_KEYCLOAK_URL"
_openc3_redis_cluster = "OPENC3_REDIS_CLUSTER"

OPENC3_API_SCHEMA = os.environ.get(_openc3_api_schema, "http")
OPENC3_API_HOSTNAME = os.environ.get(_openc3_api_hostname, "openc3-cosmos-cmd-tlm-api")
try:
    OPENC3_API_PORT = int(os.environ.get(_openc3_api_port))
except TypeError:
    OPENC3_API_PORT = 2901
try:
    OPENC3_API_TIMEOUT = float(os.environ.get(_openc3_api_timeout))
except TypeError:
    OPENC3_API_TIMEOUT = 1.0

OPENC3_SCRIPT_API_SCHEMA = os.environ.get(_openc3_script_api_schema, "http")
OPENC3_SCRIPT_API_HOSTNAME = os.environ.get(_openc3_script_api_hostname, "openc3-cosmos-script-runner-api")
try:
    OPENC3_SCRIPT_API_PORT = int(os.environ.get(_openc3_script_api_port))
except TypeError:
    OPENC3_SCRIPT_API_PORT = 2902
try:
    OPENC3_SCRIPT_API_TIMEOUT = float(os.environ.get(_openc3_script_api_timeout))
except TypeError:
    OPENC3_SCRIPT_API_TIMEOUT = 5.0

OPENC3_REDIS_HOSTNAME = os.environ.get(_openc3_redis_hostname, "127.0.0.1")
try:
    OPENC3_REDIS_PORT = int(os.environ.get(_openc3_redis_port))
except TypeError:
    OPENC3_REDIS_PORT = 6379
OPENC3_REDIS_USERNAME = os.environ.get(_openc3_redis_username)
OPENC3_REDIS_PASSWORD = os.environ.get(_openc3_redis_password)
OPENC3_REDIS_EPHEMERAL_HOSTNAME = os.environ.get(_openc3_redis_ephemeral_hostname, "127.0.0.1")
try:
    OPENC3_REDIS_EPHEMERAL_PORT = int(os.environ.get(_openc3_redis_ephemeral_port))
except TypeError:
    OPENC3_REDIS_EPHEMERAL_PORT = 6379

OPENC3_SCOPE = os.environ.get(_openc3_scope, "DEFAULT")
OPENC3_API_PASSWORD = os.environ.get(_openc3_api_password, "password")
OPENC3_LOG_LEVEL = os.environ.get(_openc3_log_level, "INFO")
OPENC3_NO_STORE = os.environ.get(_openc3_no_store)
OPENC3_API_USER = os.environ.get(_openc3_api_user)
OPENC3_API_CLIENT = os.environ.get(_openc3_api_client, "api")
OPENC3_API_TOKEN = os.environ.get(_openc3_api_token)
OPENC3_KEYCLOAK_REALM = os.environ.get(_openc3_keycloak_realm, "openc3")
OPENC3_KEYCLOAK_URL = os.environ.get(_openc3_keycloak_url, "http://openc3-keycloak/auth")
OPENC3_REDIS_CLUSTER = os.environ.get(_openc3_redis_cluster)

# User agent used by all
_openc3_default_user_agent = [
    f"{__title__}:{__version__}",
]

if OPENC3_API_USER is not None:
    _openc3_default_user_agent[0] += f":({OPENC3_API_USER})"

if os.name == "nt":
    _openc3_default_user_agent.append(
        f"{os.environ.get('COMPUTERNAME')}:{os.environ.get('USERNAME')}"
    )
else:
    _openc3_default_user_agent.append(f"{os.environ.get('HOSTNAME')}:{os.environ.get('USER')}")

OPENC3_USER_AGENT = os.environ.get(_openc3_user_agent, " ".join(_openc3_default_user_agent))