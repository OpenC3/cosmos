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
from datetime import datetime
from typing import Any

from requests import Response

import openc3.script
from openc3.environment import OPENC3_SCOPE


def list_timelines(scope: str = OPENC3_SCOPE) -> list[dict[str, Any]] | None:
    """Return all timelines in a scope.

    Args:
        scope: COSMOS scope.

    Returns:
        One dict per timeline, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error.
    """
    response = openc3.script.API_SERVER.request("get", "/openc3-api/timeline", scope=scope)
    return _handle_response(response, "Failed to list timelines")


def create_timeline(name: str, color: str | None = None, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Create a new timeline.

    Args:
        name: Timeline name.
        color: Display color, e.g. "#FF0000". Defaults to a random color.
        scope: COSMOS scope.

    Returns:
        The created timeline, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error.
    """
    data = {}
    data["name"] = name
    if color:
        data["color"] = color
    response = openc3.script.API_SERVER.request("post", "/openc3-api/timeline", data=data, json=True, scope=scope)
    return _handle_response(response, "Failed to create timeline")


def get_timeline(name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Return a timeline.

    Args:
        name: Timeline name.
        scope: COSMOS scope.

    Returns:
        The timeline, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error, including when the
            timeline is not found.
    """
    response = openc3.script.API_SERVER.request("get", f"/openc3-api/timeline/{name}", scope=scope)
    return _handle_response(response, "Failed to get timeline")


def set_timeline_color(name: str, color: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Set the color of an existing timeline.

    Args:
        name: Timeline name.
        color: Display color, e.g. "#FF0000".
        scope: COSMOS scope.

    Returns:
        The updated timeline, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error, including when the
            timeline is not found.
    """
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


def delete_timeline(name: str, force: bool = False, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Delete a timeline.

    Args:
        name: Timeline name.
        force: Also delete the timeline's activities. Deleting a timeline
            which has activities fails without this.
        scope: COSMOS scope.

    Returns:
        {"name": name}, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error, including when the
            timeline is not found.
    """
    url = f"/openc3-api/timeline/{name}"
    if force:
        url += "?force=true"
    response = openc3.script.API_SERVER.request("delete", url, scope=scope)
    return _handle_response(response, "Failed to delete timeline")


def create_timeline_activity(
    name: str,
    kind: str,
    start: datetime,
    stop: datetime,
    data: dict[str, Any] | None = None,
    scope: str = OPENC3_SCOPE,
) -> dict[str, Any] | None:
    """Create a new activity on a timeline.

    Args:
        name: Timeline name.
        kind: Activity kind: COMMAND, SCRIPT or RESERVE (case insensitive).
        start: Activity start time in UTC. It is sent with a Z suffix.
        stop: Activity stop time in UTC. It is sent with a Z suffix.
        data: Activity data. Any activity can provide "username", "notes"
            and "customTitle". The "command", "script" and "reserve" keys are
            reserved for the corresponding activity kind, with "environment"
            also available for script activities.
        scope: COSMOS scope. Must correspond to the timeline.

    Returns:
        The created activity, or None if the server returned an empty body.

    Raises:
        RuntimeError: If kind is unknown or the server returns an error.
    """
    post_data = _build_activity_data(kind, start, stop, data)
    response = openc3.script.API_SERVER.request(
        "post",
        f"/openc3-api/timeline/{name}/activities",
        data=post_data,
        json=True,
        scope=scope,
    )
    return _handle_response(response, "Failed to create timeline activity")


def update_timeline_activity(
    name: str,
    id: int | str,
    kind: str,
    start: datetime,
    stop: datetime,
    uuid: str,
    data: dict[str, Any] | None = None,
    scope: str = OPENC3_SCOPE,
) -> dict[str, Any] | None:
    """Update an existing activity on a timeline.

    Args:
        name: Timeline name.
        id: Current start time of the activity in epoch seconds.
        kind: Activity kind: COMMAND, SCRIPT or RESERVE (case insensitive).
        start: New start time in UTC. It is sent with a Z suffix.
        stop: New stop time in UTC. It is sent with a Z suffix.
        uuid: Activity UUID.
        data: Activity data. See `create_timeline_activity` for the keys.
        scope: COSMOS scope.

    Returns:
        The updated activity, or None if the server returned an empty body.

    Raises:
        RuntimeError: If kind is unknown or the server returns an error,
            including when the activity is not found.
    """
    post_data = _build_activity_data(kind, start, stop, data)
    url = f"/openc3-api/timeline/{name}/activity/{id}/{uuid}"
    response = openc3.script.API_SERVER.request(
        "put",
        url,
        data=post_data,
        json=True,
        scope=scope,
    )
    return _handle_response(response, "Failed to update timeline activity")


def get_timeline_activity(name: str, start: int | str, uuid: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Return an activity on a timeline.

    Args:
        name: Timeline name.
        start: Start time of the activity in epoch seconds.
        uuid: Activity UUID.
        scope: COSMOS scope.

    Returns:
        The activity, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error, including when the
            activity is not found.
    """
    response = openc3.script.API_SERVER.request(
        "get", f"/openc3-api/timeline/{name}/activity/{start}/{uuid}", scope=scope
    )
    return _handle_response(response, "Failed to get timeline activity")


def get_timeline_activities(
    name: str,
    start: int | float | str | None = None,
    stop: int | float | str | None = None,
    limit: int | None = None,
    scope: str = OPENC3_SCOPE,
) -> list[dict[str, Any]] | None:
    """Return the activities on a timeline within a time window.

    The window is only sent when both start and stop are given.

    Args:
        name: Timeline name.
        start: Window start as epoch seconds or an ISO 8601 string. Defaults
            to 7 days ago.
        stop: Window stop as epoch seconds or an ISO 8601 string. Defaults to
            7 days from now.
        limit: Maximum number of activities to return. Defaults to one per
            minute over the window.
        scope: COSMOS scope.

    Returns:
        The matching activities, or None if the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error.
    """
    url = f"/openc3-api/timeline/{name}/activities"
    if start and stop:
        url += f"?start={start}&stop={stop}"
    if limit:
        url += f"?limit={limit}"
    response = openc3.script.API_SERVER.request("get", url, scope=scope)
    return _handle_response(response, "Failed to get timeline activities")


def delete_timeline_activity(
    name: str, start: int | str, uuid: str, scope: str = OPENC3_SCOPE
) -> dict[str, Any] | None:
    """Delete an activity from a timeline.

    Args:
        name: Timeline name.
        start: Start time of the activity in epoch seconds.
        uuid: Activity UUID.
        scope: COSMOS scope.

    Returns:
        {"status": count} with the number of activities removed, or None if
        the server returned an empty body.

    Raises:
        RuntimeError: If the server returns an error, including when the
            activity is not found.
    """
    response = openc3.script.API_SERVER.request(
        "delete", f"/openc3-api/timeline/{name}/activity/{start}/{uuid}", scope=scope
    )
    return _handle_response(response, "Failed to delete timeline activity")


def _build_activity_data(kind: str, start: datetime, stop: datetime, data: dict[str, Any] | None):
    if data is None:
        data = {}
    kind = kind.lower()
    kinds = ["command", "script", "reserve"]
    if kind not in kinds:
        raise RuntimeError(f"Unknown kind: {kind}. Must be one of {', '.join(kinds)}.")
    return {
        "start": start.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "stop": stop.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "kind": kind,
        "data": data,
    }


# Helper method to handle the response
def _handle_response(response: Response | None, error_message: str):
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
