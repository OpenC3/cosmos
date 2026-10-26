# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import traceback

import openc3.script
from openc3.environment import OPENC3_SCOPE


# NOTE: plugin_list and plugin_get are intentionally NOT in openc3.api (and not in
# api.WHITELIST) like most other script methods. Python has no PluginModel and no
# way to read default_plugins.yaml (it lives outside the python package and Python
# has no yaml dependency), so a shared api implementation can't be mirrored in both
# languages. Instead these call the PluginsController REST endpoints directly,
# which also gives the same results in Ruby and Python scripts.


def plugin_list(default: bool = False, scope: str = OPENC3_SCOPE):
    try:
        endpoint = f"/openc3-api/plugins?scope={scope}"
        if not default:
            endpoint += "&exclude_default=true"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if not response or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to plugin_list: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"plugin_list failed due to {traceback.format_exc()}") from error


def plugin_get(plugin_name: str, scope: str = OPENC3_SCOPE):
    try:
        endpoint = f"/openc3-api/plugins/{plugin_name}?scope={scope}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if not response or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to plugin_get: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"plugin_get failed due to {traceback.format_exc()}") from error
