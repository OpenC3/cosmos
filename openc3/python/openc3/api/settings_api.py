# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.:

import warnings
from typing import Any

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.setting_model import SettingModel
from openc3.utilities.authorization import authorize, user_info
from openc3.utilities.local_mode import LocalMode
from openc3.utilities.logger import Logger


WHITELIST.extend(
    [
        "list_settings",
        "get_all_settings",
        "get_setting",
        "get_settings",
        "set_setting",
        "save_setting",  # DEPRECATED
    ]
)


def list_settings(scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all settings.

    Args:
        scope: COSMOS scope.

    Returns:
        Sorted setting names.
    """
    authorize(permission="system", scope=scope)
    return SettingModel.names(scope=scope)


def get_all_settings(scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return every setting with its full configuration.

    Args:
        scope: COSMOS scope.

    Returns:
        Setting names mapped to the setting properties (name, data and updated_at).
    """
    authorize(permission="system", scope=scope)
    return SettingModel.all(scope=scope)


def get_setting(name: str, scope: str = OPENC3_SCOPE) -> Any:
    """Return the data of a setting.

    Args:
        name: Name of the setting.
        scope: COSMOS scope.

    Returns:
        The setting data, or None if the setting does not exist.
    """
    authorize(permission="system", scope=scope)
    setting = SettingModel.get(name=name, scope=scope)
    if setting:
        return setting["data"]
    else:
        return None


def get_settings(*settings: str, scope: str = OPENC3_SCOPE) -> list[Any]:
    """Return the data of several settings.

    Args:
        *settings: Names of the settings.
        scope: COSMOS scope.

    Returns:
        The data of each setting in the order requested. None for a setting
        which does not exist.
    """
    authorize(permission="system", scope=scope)
    result = []
    for name in settings:
        result.append(get_setting(name, scope))
    return result


def set_setting(name: str, data: Any, local_mode: bool = True, scope: str = OPENC3_SCOPE) -> None:
    """Set the data of a setting.

    Requires admin permission.

    Args:
        name: Name of the setting.
        data: Setting data. Must be JSON serializable.
        local_mode: Whether to also save the setting in local mode.
        scope: COSMOS scope.
    """
    authorize(permission="admin", scope=scope)
    SettingModel.set({"name": name, "data": data}, scope=scope)
    if local_mode:
        LocalMode.save_setting(scope, name, data)
    username = user_info(None).get("username") or "Anonymous"
    Logger.info(f"User {username} saved setting '{name}': {data}", scope=scope, user=username)


def save_setting(name, data, local_mode=True, scope=OPENC3_SCOPE):
    """Set the data of a setting.

    .. deprecated:: 5.12.0
       Use set_setting instead.
    
    Args:
        name: Name of the setting.
        data: Setting data. Must be JSON serializable.
        local_mode: Whether to also save the setting in local mode.
        scope: COSMOS scope.
    """
    warnings.warn("save_setting is deprecated, use set_setting", FutureWarning, stacklevel=2)
    set_setting(name, data, local_mode, scope)
