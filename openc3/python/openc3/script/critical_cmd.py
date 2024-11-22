# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
from openc3.utilities.extract import *
import openc3.script
from openc3.environment import OPENC3_SCOPE


def critical_cmd_status(uuid: str, scope: str = OPENC3_SCOPE):
    try:
        endpoint = f"/openc3-api/criticalcmd/status/{uuid}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if not response or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to critical_cmd_status: {repr(response)}")
        result = json.loads(response.text)
        return result["status"]
    except Exception as error:
        raise RuntimeError(f"critical_cmd_status failed due to {repr(error)}") from error


def critical_cmd_approve(uuid: str, scope: str = OPENC3_SCOPE):
    try:
        endpoint = f"/openc3-api/criticalcmd/approve/{uuid}"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if not response or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"critical_cmd_approve error: {parsed['error']}")
            else:
                raise RuntimeError("critical_cmd_approve failed")
        return
    except Exception as error:
        raise RuntimeError(f"critical_cmd_approve failed due to {repr(error)}") from error


def critical_cmd_reject(uuid: str, scope: str = OPENC3_SCOPE):
    try:
        endpoint = f"/openc3-api/criticalcmd/reject/{uuid}"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if not response or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"critical_cmd_reject error: {parsed['error']}")
            else:
                raise RuntimeError("critical_cmd_reject failed")
        return
    except Exception as error:
        raise RuntimeError(f"critical_cmd_reject failed due to {repr(error)}") from error


def critical_cmd_can_approve(uuid: str, scope: str = OPENC3_SCOPE):
    try:
        endpoint = f"/openc3-api/criticalcmd/canapprove/{uuid}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if not response or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to critical_cmd_can_approve: {repr(response)}")
        result = json.loads(response.text)
        if result["status"] == "ok":
            return True
        else:
            return False
    except Exception as error:
        raise RuntimeError(f"critical_cmd_approve failed due to {repr(error)}") from error
