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
from openc3.models.stash_model import StashModel
from openc3.utilities.authorization import authorize


WHITELIST.extend(["stash_set", "stash_get", "stash_all", "stash_keys", "stash_delete"])


def stash_set(key: str, value: Any, scope: str = OPENC3_SCOPE) -> None:
    """Set a stash item.

    Args:
        key: Name of the stash key.
        value: Value to store. Must be JSON serializable.
        scope: COSMOS scope.
    """
    authorize(permission="script_run", scope=scope)
    return StashModel.set({"name": key, "value": json.dumps(value)}, scope=scope)


def stash_get(key: str, scope: str = OPENC3_SCOPE) -> Any:
    """Return the value of a stash item.

    Args:
        key: Name of the stash key.
        scope: COSMOS scope.

    Returns:
        The stored value, or None if the key does not exist.
    """
    authorize(permission="script_view", scope=scope)
    result = StashModel.get(name=key, scope=scope)
    if result:
        return json.loads(result["value"])
    else:
        return None


def stash_all(scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return all stash items.

    Args:
        scope: COSMOS scope.

    Returns:
        Stash keys mapped to their values.
    """
    authorize(permission="script_view", scope=scope)
    all = StashModel.all(scope=scope)
    for key, values in all.items():
        all[key] = json.loads(values["value"])
    return all


def stash_keys(scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all stash keys.

    Args:
        scope: COSMOS scope.

    Returns:
        Sorted stash keys.
    """
    authorize(permission="script_view", scope=scope)
    return StashModel.names(scope=scope)


def stash_delete(key: str, scope: str = OPENC3_SCOPE) -> StashModel | None:
    """Delete a stash item.

    Args:
        key: Name of the stash key.
        scope: COSMOS scope.

    Returns:
        The deleted model, or None if the key does not exist.
    """
    authorize(permission="script_run", scope=scope)
    model = StashModel.get_model(name=key, scope=scope)
    if model:
        model.destroy()
    return model
