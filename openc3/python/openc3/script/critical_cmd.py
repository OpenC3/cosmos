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
from typing import Any

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.extract import *


def critical_cmd_status(uuid: str, scope: str = OPENC3_SCOPE) -> str | None:
    """Return the approval status of a critical command.

    Args:
        uuid: UUID of the critical command, as shown when it was sent.
        scope: COSMOS scope.

    Returns:
        The status, e.g. WAITING, APPROVED or REJECTED, or None if the
        response has no status.

    Raises:
        RuntimeError: If the request fails or the response is not 200 OK.
    """
    try:
        endpoint = f"/openc3-api/criticalcmd/status/{uuid}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to critical_cmd_status: {repr(response)}")
        result = json.loads(response.text)
        return result.get("status")
    except Exception as error:
        raise RuntimeError(f"critical_cmd_status failed due to {traceback.format_exc()}") from error


def critical_cmd_info(uuid: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return the approval status and approvers of a critical command.

    Args:
        uuid: UUID of the critical command, as shown when it was sent.
        scope: COSMOS scope.

    Returns:
        A dict with 'status', 'approvers' (users who have approved so far,
        default []) and 'approvers_required' (number of approvals needed to
        send the command, default 1).

    Raises:
        RuntimeError: If the request fails or the response is not 200 OK.
    """
    try:
        endpoint = f"/openc3-api/criticalcmd/status/{uuid}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to critical_cmd_info: {repr(response)}")
        result = json.loads(response.text)
        return {
            "status": result.get("status"),
            "approvers": result.get("approvers") or [],
            "approvers_required": result.get("approvers_required") or 1,
        }
    except Exception as error:
        raise RuntimeError(f"critical_cmd_info failed due to {traceback.format_exc()}") from error


def critical_cmd_approve(uuid: str, scope: str = OPENC3_SCOPE) -> None:
    """Approve a critical command as the current user.

    Args:
        uuid: UUID of the critical command, as shown when it was sent.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request fails or the server rejects the approval.
    """
    try:
        endpoint = f"/openc3-api/criticalcmd/approve/{uuid}"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        # A requests.Response is falsy for error status codes so compare to None
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"critical_cmd_approve error: {parsed.get('message') or parsed.get('error')}")
            else:
                raise RuntimeError("critical_cmd_approve failed")
        return
    except Exception as error:
        raise RuntimeError(f"critical_cmd_approve failed due to {traceback.format_exc()}") from error


def critical_cmd_reject(uuid: str, scope: str = OPENC3_SCOPE) -> None:
    """Reject a critical command as the current user.

    Args:
        uuid: UUID of the critical command, as shown when it was sent.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the request fails or the server rejects the rejection.
    """
    try:
        endpoint = f"/openc3-api/criticalcmd/reject/{uuid}"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        # A requests.Response is falsy for error status codes so compare to None
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"critical_cmd_reject error: {parsed.get('message') or parsed.get('error')}")
            else:
                raise RuntimeError("critical_cmd_reject failed")
        return
    except Exception as error:
        raise RuntimeError(f"critical_cmd_reject failed due to {traceback.format_exc()}") from error


def critical_cmd_can_approve(uuid: str, scope: str = OPENC3_SCOPE) -> bool:
    """Return whether the current user can approve a critical command.

    Args:
        uuid: UUID of the critical command, as shown when it was sent.
        scope: COSMOS scope.

    Returns:
        Whether the current user can approve the command.

    Raises:
        RuntimeError: If the request fails or the response is not 200 OK.
    """
    try:
        endpoint = f"/openc3-api/criticalcmd/canapprove/{uuid}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to critical_cmd_can_approve: {repr(response)}")
        result = json.loads(response.text)
        return result.get("status") == "ok"
    except Exception as error:
        raise RuntimeError(f"critical_cmd_can_approve failed due to {traceback.format_exc()}") from error
