# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
from typing import Any

from openc3.environment import OPENC3_SCOPE
from openc3.script import API_SERVER


def _make_request(action: str, verb: str, uri: str, scope: str, data: dict[str, Any] | None = None):
    """Make the request and parse the response."""
    kwargs = {"scope": scope}
    if data is not None:
        kwargs["data"] = data
        kwargs["json"] = True

    response = API_SERVER.request(verb, uri, **kwargs)

    if response is None:
        raise RuntimeError(f"Failed to {action}. No response from server.")
    elif response.status_code not in [200, 201]:
        try:
            result = json.loads(response.text)
            message = result.get("message", "Unknown error")
        except (json.JSONDecodeError, AttributeError):
            message = "Unknown error"
        raise RuntimeError(f"Failed to {action} due to {message}")

    return json.loads(response.text)


def queue_all(scope: str = OPENC3_SCOPE) -> list[dict[str, Any]]:
    """Return all queues in a scope.

    Args:
        scope: COSMOS scope.

    Returns:
        One dict per queue, sorted by name with the default queue first.

    Raises:
        RuntimeError: If the server returns an error.
    """
    return _make_request("index queue", "get", "/openc3-api/queues", scope)


def queue_get(name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return a queue.

    Args:
        name: Queue name.
        scope: COSMOS scope.

    Returns:
        The queue.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue is not found.
    """
    return _make_request("get queue", "get", f"/openc3-api/queues/{name}", scope)


def queue_list(name: str, scope: str = OPENC3_SCOPE) -> list[dict[str, Any]]:
    """Return the commands in a queue.

    Args:
        name: Queue name.
        scope: COSMOS scope.

    Returns:
        One dict per queued command. Each has an "id" key holding its
        position in the queue.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue is not found.
    """
    return _make_request("list queue", "get", f"/openc3-api/queues/{name}/list", scope)


def queue_create(name: str, state: str = "HOLD", scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Create a new queue.

    Args:
        name: Queue name.
        state: Initial state: HOLD, RELEASE or DISABLE.
        scope: COSMOS scope.

    Returns:
        The created queue.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue already exists.
    """
    data = {}
    data["state"] = state
    return _make_request("create queue", "post", f"/openc3-api/queues/{name}", scope, data=data)


def queue_hold(name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Hold a queue, pausing the processing of its commands.

    Args:
        name: Queue name.
        scope: COSMOS scope.

    Returns:
        The updated queue.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue is not found.
    """
    return _make_request("hold queue", "post", f"/openc3-api/queues/{name}/hold", scope)


def queue_release(name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Release a queue, resuming the processing of its commands.

    Args:
        name: Queue name.
        scope: COSMOS scope.

    Returns:
        The updated queue.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue is not found.
    """
    return _make_request("release queue", "post", f"/openc3-api/queues/{name}/release", scope)


def queue_disable(name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Disable a queue.

    Args:
        name: Queue name.
        scope: COSMOS scope.

    Returns:
        The updated queue.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue is not found.
    """
    return _make_request("disable queue", "post", f"/openc3-api/queues/{name}/disable", scope)


def queue_exec(name: str, id: float | None = None, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Remove a command from a queue and send it.

    Args:
        name: Queue name.
        id: Queue id of the command, as returned by `queue_list`. Defaults
            to the first command in the queue.
        scope: COSMOS scope.

    Returns:
        The command which was sent.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue or command is not found or the command fails.
    """
    data = {}
    if id is not None:
        data["id"] = id
    return _make_request(
        "exec command",
        "post",
        f"/openc3-api/queues/{name}/exec_command",
        scope,
        data=data,
    )


def queue_remove(name: str, id: float | None = None, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Remove a command from a queue without sending it.

    Args:
        name: Queue name.
        id: Queue id of the command, as returned by `queue_list`. Defaults
            to the first command in the queue.
        scope: COSMOS scope.

    Returns:
        The command which was removed.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue or command is not found.
    """
    data = {}
    if id is not None:
        data["id"] = id
    return _make_request(
        "remove command",
        "post",
        f"/openc3-api/queues/{name}/remove_command",
        scope,
        data=data,
    )


def queue_delete(name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Delete a queue.

    Args:
        name: Queue name.
        scope: COSMOS scope.

    Returns:
        The deleted queue.

    Raises:
        RuntimeError: If the server returns an error, including when the
            queue is not found.
    """
    return _make_request("delete queue", "delete", f"/openc3-api/queues/{name}", scope)


# Alias for queue_delete to match Ruby implementation
queue_destroy = queue_delete
