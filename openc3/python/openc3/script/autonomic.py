# encoding: utf-8

# Copyright 2025 OpenC3, Inc.
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
from openc3.environment import OPENC3_SCOPE
import openc3.script


# Group Methods
def autonomic_group_list(scope=None):
    """List all autonomic groups

    Args:
        scope: Scope to operate in

    Returns:
        List of autonomic groups
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
        raise RuntimeError(f"autonomic_group_list failed due to {error}")


def autonomic_group_create(name, scope=None):
    """Create an autonomic group

    Args:
        name: Name of the group to create
        scope: Scope to operate in

    Returns:
        Created group data
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = "/openc3-api/autonomic/group"
        response = openc3.script.API_SERVER.request("post", endpoint, data={"name": name}, json=True, scope=scope)
        if response is None or response.status_code != 201:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_group_create error: {parsed.get('message', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_group_create failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_group_create failed due to {error}")


def autonomic_group_show(name, scope=None):
    """Show details about an autonomic group

    Args:
        name: Name of the group
        scope: Scope to operate in

    Returns:
        Group details
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
        raise RuntimeError(f"autonomic_group_show failed due to {error}")


def autonomic_group_destroy(name, scope=None):
    """Destroy an autonomic group

    Args:
        name: Name of the group to destroy
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/group/{name}"
        response = openc3.script.API_SERVER.request("delete", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_group_destroy error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_group_destroy failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_group_destroy failed due to {error}")


# Trigger Methods
def autonomic_trigger_list(group="DEFAULT", scope=None):
    """List all triggers in a group

    Args:
        group: Group to list triggers from
        scope: Scope to operate in

    Returns:
        List of triggers
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
        raise RuntimeError(f"autonomic_trigger_list failed due to {error}")


def autonomic_trigger_create(left, operator, right, group="DEFAULT", scope=None):
    """Create a new trigger

    Args:
        left: Left side of the trigger condition
        operator: Comparison operator
        right: Right side of the trigger condition
        group: Group to create the trigger in
        scope: Scope to operate in

    Returns:
        Created trigger data
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger"
        config = {"group": group, "left": left, "operator": operator, "right": right}
        response = openc3.script.API_SERVER.request("post", endpoint, data=config, json=True, scope=scope)
        if response is None or response.status_code != 201:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_create error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_create failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_create failed due to {error}")


def autonomic_trigger_show(name, group="DEFAULT", scope=None):
    """Show a trigger

    Args:
        name: Name of the trigger
        group: Group the trigger belongs to
        scope: Scope to operate in

    Returns:
        Trigger details
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
        raise RuntimeError(f"autonomic_trigger_show failed due to {error}")


def autonomic_trigger_enable(name, group="DEFAULT", scope=None):
    """Enable a trigger

    Args:
        name: Name of the trigger to enable
        group: Group the trigger belongs to
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}/enable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_enable error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_enable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_enable failed due to {error}")


def autonomic_trigger_disable(name, group="DEFAULT", scope=None):
    """Disable a trigger

    Args:
        name: Name of the trigger to disable
        group: Group the trigger belongs to
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}/disable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_disable error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_disable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_disable failed due to {error}")


def autonomic_trigger_update(name, group="DEFAULT", left=None, operator=None, right=None, scope=None):
    """Update a trigger

    Args:
        name: Name of the trigger to update
        group: Group the trigger belongs to
        left: Left side of the trigger condition
        operator: Comparison operator
        right: Right side of the trigger condition
        scope: Scope to operate in

    Returns:
        Updated trigger data
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
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_update error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_update failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_update failed due to {error}")


def autonomic_trigger_destroy(name, group="DEFAULT", scope=None):
    """Destroy a trigger

    Args:
        name: Name of the trigger to destroy
        group: Group the trigger belongs to
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/{group}/trigger/{name}"
        response = openc3.script.API_SERVER.request("delete", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_trigger_destroy error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_trigger_destroy failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_trigger_destroy failed due to {error}")


# Reaction Methods
def autonomic_reaction_list(scope=None):
    """List all reactions

    Args:
        scope: Scope to operate in

    Returns:
        List of reactions
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
        raise RuntimeError(f"autonomic_reaction_list failed due to {error}")


def autonomic_reaction_create(triggers, actions, trigger_level="EDGE", snooze=0, scope=None):
    """Create a new reaction

    Args:
        triggers: List of trigger names
        actions: List of actions to perform
        trigger_level: Trigger level (default: 'EDGE')
        snooze: Snooze time in seconds (default: 0)
        scope: Scope to operate in

    Returns:
        Created reaction data
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
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_create error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_create failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_create failed due to {error}")


def autonomic_reaction_show(name, scope=None):
    """Show details of a reaction

    Args:
        name: Name of the reaction
        scope: Scope to operate in

    Returns:
        Reaction details
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
        raise RuntimeError(f"autonomic_reaction_show failed due to {error}")


def autonomic_reaction_enable(name, scope=None):
    """Enable a reaction

    Args:
        name: Name of the reaction to enable
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}/enable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_enable error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_enable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_enable failed due to {error}")


def autonomic_reaction_disable(name, scope=None):
    """Disable a reaction

    Args:
        name: Name of the reaction to disable
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}/disable"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_disable error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_disable failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_disable failed due to {error}")


def autonomic_reaction_execute(name, scope=None):
    """Execute a reaction

    Args:
        name: Name of the reaction to execute
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}/execute"
        response = openc3.script.API_SERVER.request("post", endpoint, json=True, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_execute error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_execute failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_execute failed due to {error}")


def autonomic_reaction_update(name, triggers=None, actions=None, trigger_level=None, snooze=None, scope=None):
    """Update a reaction

    Args:
        name: Name of the reaction to update
        triggers: List of trigger names
        actions: List of actions to perform
        trigger_level: Trigger level
        snooze: Snooze time in seconds
        scope: Scope to operate in

    Returns:
        Updated reaction data
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
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_update error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_update failed")
        return json.loads(response.text)
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_update failed due to {error}")


def autonomic_reaction_destroy(name, scope=None):
    """Destroy a reaction

    Args:
        name: Name of the reaction to destroy
        scope: Scope to operate in
    """
    if scope is None:
        scope = OPENC3_SCOPE
    try:
        endpoint = f"/openc3-api/autonomic/reaction/{name}"
        response = openc3.script.API_SERVER.request("delete", endpoint, scope=scope)
        if response is None or response.status_code != 200:
            if response:
                parsed = json.loads(response.text)
                raise RuntimeError(f"autonomic_reaction_destroy error: {parsed.get('error', 'Unknown error')}")
            else:
                raise RuntimeError("autonomic_reaction_destroy failed")
        return
    except Exception as error:
        raise RuntimeError(f"autonomic_reaction_destroy failed due to {error}")
