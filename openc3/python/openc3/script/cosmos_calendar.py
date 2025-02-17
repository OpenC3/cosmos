# Copyright 2023 OpenC3, Inc.
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
import openc3.script
from openc3.environment import OPENC3_SCOPE


def list_timelines(scope=OPENC3_SCOPE):
    response = openc3.script.API_SERVER.request("get", "/openc3-api/timeline", scope=scope)
    return _handle_response(response, "Failed to list timelines")


def create_timeline(name, color=None, scope=OPENC3_SCOPE):
    data = {}
    data["name"] = name
    if color:
        data["color"] = color
    response = openc3.script.API_SERVER.request("post", "/openc3-api/timeline", data=data, json=True, scope=scope)
    return _handle_response(response, "Failed to create timeline")


def get_timeline(name, scope=OPENC3_SCOPE):
    response = openc3.script.API_SERVER.request("get", f"/openc3-api/timeline/{name}", scope=scope)
    return _handle_response(response, "Failed to get timeline")


def set_timeline_color(name, color, scope=OPENC3_SCOPE):
    post_data = {}
    post_data["color"] = color
    response = openc3.script.API_SERVER.request(
        "post",
        f"/openc3-api/timeline/{name}/color",
        data=post_data,
        json=True,
        scope=scope,
    )
    return _handle_response(response, "Failed to set timeline color")


def delete_timeline(name, force=False, scope=OPENC3_SCOPE):
    url = f"/openc3-api/timeline/{name}"
    if force:
        url += "?force=true"
    response = openc3.script.API_SERVER.request("delete", url, scope=scope)
    return _handle_response(response, "Failed to delete timeline")


def create_timeline_activity(name, kind, start, stop, data={}, scope=OPENC3_SCOPE):
    kind = kind.lower()
    kinds = ["command", "script", "reserve"]
    if kind not in kinds:
        raise RuntimeError(f"Unknown kind: {kind}. Must be one of {', '.join(kinds)}.")
    post_data = {}
    post_data["start"] = start.isoformat()
    post_data["stop"] = stop.isoformat()
    post_data["kind"] = kind
    post_data["data"] = data
    response = openc3.script.API_SERVER.request(
        "post",
        f"/openc3-api/timeline/{name}/activities",
        data=post_data,
        json=True,
        scope=scope,
    )
    return _handle_response(response, "Failed to create timeline activity")


def get_timeline_activity(name, start, uuid, scope=OPENC3_SCOPE):
    response = openc3.script.API_SERVER.request("get", f"/openc3-api/timeline/{name}/activity/{start}/{uuid}", scope=scope)
    return _handle_response(response, "Failed to get timeline activity")


def get_timeline_activities(name, start=None, stop=None, limit=None, scope=OPENC3_SCOPE):
    url = f"/openc3-api/timeline/{name}/activities"
    if start and stop:
        url += f"?start={start}&stop={stop}"
    if limit:
        url += f"?limit={limit}"
    response = openc3.script.API_SERVER.request("get", url, scope=scope)
    return _handle_response(response, "Failed to get timeline activities")


def delete_timeline_activity(name, start, uuid, scope=OPENC3_SCOPE):
    response = openc3.script.API_SERVER.request(
        "delete", f"/openc3-api/timeline/{name}/activity/{start}/{uuid}", scope=scope
    )
    return _handle_response(response, "Failed to delete timeline activity")


# Helper method to handle the response
def _handle_response(response, error_message):
    if response is None:
        return None
    if response.status_code >= 400:
        result = json.loads(response.text)
        raise RuntimeError(f"{error_message} due to {result['message']}")
    # Not sure why the response body is empty (on delete) but check for that
    if response.text is None or len(response.text) == 0:
        return None
    else:
        return json.loads(response.text)
