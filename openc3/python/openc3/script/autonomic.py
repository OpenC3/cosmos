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
from typing import Any

import openc3.script
from openc3.environment import OPENC3_SCOPE


# Group Methods
def autonomic_group_list(scope: str | None = None) -> list[dict[str, Any]]:
    """List all autonomic trigger groups.

    Args:
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        A list of trigger group dicts.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = "/openc3-api/autonomic/group"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to autonomic_group_list: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_group_list failed due to {error}") from error


def autonomic_group_create(name: str, scope: str | None = None) -> dict[str, Any]:
    """Create an autonomic trigger group.

    Args:
        name: Name of the group to create.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The created group as a dict.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = "/openc3-api/autonomic/group"
        response = openc3.script.API_SERVER.request("post", endpoint, data={"name": name}, json=True, scope=scope)
        if response is None or response.status_code != 201:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_group_create error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_group_create failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_group_create failed due to {error}") from error


def autonomic_group_show(name: str, scope: str | None = None) -> dict[str, Any]:
    """Show the details of an autonomic trigger group.

    Args:
        name: Name of the group.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The group as a dict.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/group/{name}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to autonomic_group_show: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_group_show failed due to {error}") from error


def autonomic_group_destroy(name: str, scope: str | None = None) -> None:
    """Destroy an autonomic trigger group.

    Args:
        name: Name of the group to destroy.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/group/{name}"
        response = openc3.script.API_SERVER.request("delete", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_group_destroy error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_group_destroy failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_group_destroy failed due to {error}") from error


# Trigger Methods
def autonomic_trigger_list(group: str = "DEFAULT", scope: str | None = None) -> list[dict[str, Any]]:
    """List all triggers in a trigger group.

    Args:
        group: Group to list the triggers from.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        A list of trigger dicts.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to autonomic_trigger_list: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_list failed due to {error}") from error


def autonomic_trigger_create(
    left: dict[str, Any],
    operator: str,
    right: dict[str, Any] | None,
    group: str = "DEFAULT",
    scope: str | None = None,
) -> dict[str, Any]:
    """Create a trigger.

    The trigger name is generated by the server. Operands are dicts with a
    "type" key ("item", "limit", "float", "string" or "regex", or "trigger"
    for the AND / OR operators) plus the matching value key, for example
    ``{"type": "item", "target": "INST", "packet": "ADCS", "item": "POSX", "valueType": "RAW"}``
    or ``{"type": "float", "float": 690000}``.

    Args:
        left: Left operand of the trigger condition.
        operator: Comparison operator: ">", "<", ">=", "<=", "==", "!=", "CHANGES" or
            "DOES NOT CHANGE", or "AND" / "OR" when the operands are triggers.
        right: Right operand of the trigger condition. None for CHANGES and DOES NOT CHANGE.
        group: Group to create the trigger in.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The created trigger as a dict.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger"
        config = {"group": group, "left": left, "operator": operator, "right": right}
        response = openc3.script.API_SERVER.request("post", endpoint, data=config, json=True, scope=scope)
        if response is None or response.status_code != 201:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_create error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_create failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_create failed due to {error}") from error


def autonomic_trigger_show(name: str, group: str = "DEFAULT", scope: str | None = None) -> dict[str, Any]:
    """Show the details of a trigger.

    Args:
        name: Name of the trigger.
        group: Group the trigger belongs to.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The trigger as a dict.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to autonomic_trigger_show: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_show failed due to {error}") from error


def autonomic_trigger_enable(name: str, group: str = "DEFAULT", scope: str | None = None) -> None:
    """Enable a trigger.

    Args:
        name: Name of the trigger to enable.
        group: Group the trigger belongs to.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}/enable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_enable error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_enable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_enable failed due to {error}") from error


def autonomic_trigger_disable(name: str, group: str = "DEFAULT", scope: str | None = None) -> None:
    """Disable a trigger.

    Args:
        name: Name of the trigger to disable.
        group: Group the trigger belongs to.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}/disable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_disable error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_disable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_disable failed due to {error}") from error


def autonomic_trigger_update(
    name: str,
    group: str = "DEFAULT",
    left: dict[str, Any] | None = None,
    operator: str | None = None,
    right: dict[str, Any] | None = None,
    scope: str | None = None,
) -> dict[str, Any]:
    """Update a trigger.

    Only the parts of the condition that are not None are changed. See
    `autonomic_trigger_create` for the operand format.

    Args:
        name: Name of the trigger to update.
        group: Group the trigger belongs to.
        left: New left operand of the trigger condition.
        operator: New comparison operator.
        right: New right operand of the trigger condition.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The updated trigger as a dict.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}"
        config = {}
        if left is not None:
            config["left"] = left
        if operator is not None:
            config["operator"] = operator
        if right is not None:
            config["right"] = right
        response = openc3.script.API_SERVER.request("put", endpoint, data=config, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_update error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_update failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_update failed due to {error}") from error


def autonomic_trigger_destroy(name: str, group: str = "DEFAULT", scope: str | None = None) -> None:
    """Destroy a trigger.

    The server refuses to destroy a trigger that other triggers or reactions depend on.

    Args:
        name: Name of the trigger to destroy.
        group: Group the trigger belongs to.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}"
        response = openc3.script.API_SERVER.request("delete", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_destroy error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_destroy failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_destroy failed due to {error}") from error


# Reaction Methods
def autonomic_reaction_list(scope: str | None = None) -> list[dict[str, Any]]:
    """List all reactions.

    Args:
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        A list of reaction dicts.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = "/openc3-api/autonomic/reaction"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to autonomic_reaction_list: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_list failed due to {error}") from error


def autonomic_reaction_create(
    triggers: list[dict[str, Any]],
    actions: list[dict[str, Any]],
    trigger_level: str = "EDGE",
    snooze: int = 0,
    scope: str | None = None,
) -> dict[str, Any]:
    """Create a reaction which runs actions when its triggers fire.

    The reaction name is generated by the server. Each trigger is a dict with
    "name" and "group" keys, e.g. ``{"name": "TRIG1", "group": "DEFAULT"}``.
    Each action is a dict with a "type" of "command", "script" or "notify"
    and a "value", e.g. ``{"type": "command", "value": "INST CLEAR"}``.

    Args:
        triggers: Triggers which activate the reaction.
        actions: Actions to perform when the reaction activates.
        trigger_level: EDGE (default) to react only when a trigger becomes true, or LEVEL to react
            whenever a trigger is true.
        snooze: Minimum seconds between activations.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The created reaction as a dict.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = "/openc3-api/autonomic/reaction"
        config = {
            "triggers": triggers,
            "actions": actions,
            "trigger_level": trigger_level,
            "snooze": snooze,
        }
        response = openc3.script.API_SERVER.request("post", endpoint, data=config, json=True, scope=scope)
        if response is None or response.status_code != 201:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_create error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_create failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_create failed due to {error}") from error


def autonomic_reaction_show(name: str, scope: str | None = None) -> dict[str, Any] | None:
    """Show the details of a reaction.

    Args:
        name: Name of the reaction.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The reaction as a dict, or None if the reaction does not exist.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}"
        response = openc3.script.API_SERVER.request("get", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            raise RuntimeError(f"Unexpected response to autonomic_reaction_show: {response}")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_show failed due to {error}") from error


def autonomic_reaction_enable(name: str, scope: str | None = None) -> None:
    """Enable a reaction.

    Args:
        name: Name of the reaction to enable.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}/enable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_enable error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_enable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_enable failed due to {error}") from error


def autonomic_reaction_disable(name: str, scope: str | None = None) -> None:
    """Disable a reaction.

    Args:
        name: Name of the reaction to disable.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}/disable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_disable error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_disable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_disable failed due to {error}") from error


def autonomic_reaction_execute(name: str, scope: str | None = None) -> None:
    """Run the actions of a reaction now, regardless of its triggers.

    Args:
        name: Name of the reaction to execute.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}/execute"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_execute error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_execute failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_execute failed due to {error}") from error


def autonomic_reaction_update(
    name: str,
    triggers: list[dict[str, Any]] | None = None,
    actions: list[dict[str, Any]] | None = None,
    trigger_level: str | None = None,
    snooze: int | None = None,
    scope: str | None = None,
) -> dict[str, Any]:
    """Update a reaction.

    Only the settings that are not None are changed. See
    `autonomic_reaction_create` for the trigger and action formats.

    Args:
        name: Name of the reaction to update.
        triggers: New triggers which activate the reaction.
        actions: New actions to perform when the reaction activates.
        trigger_level: New trigger level, EDGE or LEVEL.
        snooze: New minimum seconds between activations.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Returns:
        The updated reaction as a dict.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}"
        config = {}
        if triggers is not None:
            config["triggers"] = triggers
        if actions is not None:
            config["actions"] = actions
        if trigger_level is not None:
            config["trigger_level"] = trigger_level
        if snooze is not None:
            config["snooze"] = snooze
        response = openc3.script.API_SERVER.request("put", endpoint, data=config, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_update error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_update failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_update failed due to {error}") from error


def autonomic_reaction_destroy(name: str, scope: str | None = None) -> None:
    """Destroy a reaction.

    Args:
        name: Name of the reaction to destroy.
        scope: COSMOS scope. None uses the OPENC3_SCOPE environment default.

    Raises:
        RuntimeError: If the request fails or returns an unexpected status.
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}"
        response = openc3.script.API_SERVER.request("delete", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            if response is not None:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_destroy error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_destroy failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_destroy failed due to {error}") from error
