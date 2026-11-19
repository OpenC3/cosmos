# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.:

import json
from typing import Any

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.tool_config_model import ToolConfigModel
from openc3.utilities.authorization import authorize


WHITELIST.extend(["config_tool_names", "list_configs", "load_config", "save_config", "delete_config"])


def config_tool_names(scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all tools which have saved configurations.

    Args:
        scope: COSMOS scope.

    Returns:
        Sorted tool names.
    """
    authorize(permission="system", scope=scope)
    return ToolConfigModel.config_tool_names(scope=scope)


def list_configs(tool: str, scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all saved configurations for a tool.

    Args:
        tool: Name of the tool.
        scope: COSMOS scope.

    Returns:
        Configuration names.
    """
    authorize(permission="system", scope=scope)
    return ToolConfigModel.list_configs(tool, scope=scope)


def load_config(tool: str, name: str, scope: str = OPENC3_SCOPE) -> Any:
    """Load a saved tool configuration.

    Tool configurations are not fully documented and can change between
    releases. Only modify the returned values, never the keys.

    Args:
        tool: Name of the tool.
        name: Name of the configuration.
        scope: COSMOS scope.

    Returns:
        The configuration decoded from JSON.
    """
    authorize(permission="system", scope=scope)
    return json.loads(ToolConfigModel.load_config(tool, name, scope=scope))


def save_config(tool: str, name: str, data: str, local_mode: bool = True, scope: str = OPENC3_SCOPE) -> None:
    """Save a tool configuration.

    Args:
        tool: Name of the tool.
        name: Name of the configuration.
        data: Configuration encoded as a JSON string.
        local_mode: Whether to also save the configuration in local mode.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", scope=scope)
    ToolConfigModel.save_config(tool, name, data, local_mode, scope)


def delete_config(tool: str, name: str, local_mode: bool = True, scope: str = OPENC3_SCOPE) -> None:
    """Delete a saved tool configuration.

    Args:
        tool: Name of the tool.
        name: Name of the configuration.
        local_mode: Whether to also delete the configuration from local mode.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", scope=scope)
    ToolConfigModel.delete_config(tool, name, local_mode, scope)
