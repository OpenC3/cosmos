# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.:

from typing import Any

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.interface_model import InterfaceModel
from openc3.models.target_model import TargetModel
from openc3.utilities.authorization import authorize


WHITELIST.extend(
    [
        "get_target_names",
        "get_target",
        "get_target_interfaces",
    ]
)


def get_target_names(scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all targets.

    Args:
        scope: COSMOS scope.

    Returns:
        Sorted target names.
    """
    authorize(permission="system", scope=scope)
    return TargetModel.names(scope=scope)


def get_target(target_name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any] | None:
    """Return the full configuration of a target.

    Args:
        target_name: Name of the target.
        scope: COSMOS scope.

    Returns:
        All the target properties, or None if the target does not exist.
    """
    authorize(permission="system", target_name=target_name, scope=scope)
    return TargetModel.get(name=target_name, scope=scope)


def get_target_interfaces(scope: str = OPENC3_SCOPE) -> list[list[str]]:
    """Return every target and the interfaces it is mapped to.

    Args:
        scope: COSMOS scope.

    Returns:
        A [target_name, interface_names] pair for each target, where
        interface_names is a comma separated string.
    """
    authorize(permission="system", scope=scope)
    info = []
    interfaces = InterfaceModel.all(scope=scope)
    for target_name in get_target_names(scope=scope):
        interface_names = []
        for _, interface in interfaces.items():
            if target_name in interface["target_names"]:
                interface_names.append(interface["name"])
        info.append([target_name, ",".join(interface_names)])
    return info
