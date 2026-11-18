# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from typing import Any

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.interface_model import InterfaceModel
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.topics.interface_topic import InterfaceTopic
from openc3.utilities.authorization import authorize
from openc3.utilities.logger import Logger


WHITELIST.extend(
    [
        "get_interface",
        "get_interface_names",
        "connect_interface",
        "disconnect_interface",
        "start_raw_logging_interface",
        "stop_raw_logging_interface",
        "get_all_interface_info",
        "map_target_to_interface",
        "unmap_target_from_interface",
        "interface_cmd",
        "interface_protocol_cmd",
        "interface_target_enable",
        "interface_target_disable",
        "interface_details",
    ]
)


def get_interface(interface_name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return the configuration and current status of an interface.

    Args:
        interface_name: Interface name.
        scope: COSMOS scope.

    Returns:
        The interface configuration merged with its status (state, clients,
        queue sizes, byte and packet counts).

    Raises:
        RuntimeError: If the interface does not exist.
    """
    authorize(permission="system", interface_name=interface_name, scope=scope)
    interface = InterfaceModel.get(name=interface_name, scope=scope)
    if not interface:
        raise RuntimeError(f"Interface '{interface_name}' does not exist (get_interface)")
    return interface | InterfaceStatusModel.get_or_default(name=interface_name, scope=scope)


def get_interface_names(scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all interfaces.

    Args:
        scope: COSMOS scope.

    Returns:
        Sorted interface names.
    """
    authorize(permission="system", scope=scope)
    return InterfaceModel.names(scope=scope)


def connect_interface(interface_name: str, *interface_params: Any, scope: str = OPENC3_SCOPE) -> None:
    """Connect an interface and start its telemetry gathering thread.

    Args:
        interface_name: Interface name.
        *interface_params: Optional parameters which replace the interface's
            configured parameters when it is rebuilt.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    InterfaceTopic.connect_interface(interface_name, *interface_params, scope=scope)


def disconnect_interface(interface_name: str, scope: str = OPENC3_SCOPE) -> None:
    """Disconnect an interface and stop its telemetry gathering thread.

    Args:
        interface_name: Interface name.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    InterfaceTopic.disconnect_interface(interface_name, scope=scope)


def start_raw_logging_interface(interface_name: str = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Start raw logging on an interface.

    Args:
        interface_name: Interface name, or ALL (default) for every interface.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    if interface_name == "ALL":
        for interface_name in get_interface_names():
            InterfaceTopic.start_raw_logging(interface_name, scope=scope)
    else:
        InterfaceTopic.start_raw_logging(interface_name, scope=scope)


def stop_raw_logging_interface(interface_name: str = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Stop raw logging on an interface.

    Args:
        interface_name: Interface name, or ALL (default) for every interface.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    if interface_name == "ALL":
        for interface_name in get_interface_names():
            InterfaceTopic.stop_raw_logging(interface_name, scope=scope)
    else:
        InterfaceTopic.stop_raw_logging(interface_name, scope=scope)


def get_all_interface_info(scope: str = OPENC3_SCOPE) -> list[list[Any]]:
    """Return status information about all interfaces in a single call.

    Args:
        scope: COSMOS scope.

    Returns:
        One list per interface containing [name, state, num clients,
        TX queue size, RX queue size, TX bytes, RX bytes, command count,
        telemetry count, disable disconnect].
    """
    authorize(permission="system", scope=scope)
    info = []
    for int_name, int in InterfaceStatusModel.all(scope=scope).items():
        # Get the interface configuration to access disable_disconnect
        interface_model = InterfaceModel.get(name=int_name, scope=scope)
        if interface_model and interface_model["disable_disconnect"]:
            disable_disconnect = True
        else:
            disable_disconnect = False
        info.append(
            [
                int["name"],
                int["state"],
                int["clients"],
                int["txsize"],
                int["rxsize"],
                int["txbytes"],
                int["rxbytes"],
                int["txcnt"],
                int["rxcnt"],
                disable_disconnect,
            ]
        )
    return info


def map_target_to_interface(
    target_name: str | list[str],
    interface_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    unmap_old: bool = True,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Map one or more targets to an interface.

    All of the target's commands go out over, and telemetry is received
    from, that interface.

    Args:
        target_name: Target name, or a list of target names.
        interface_name: Interface name.
        cmd_only: Map only the target's commands.
        tlm_only: Map only the target's telemetry.
        unmap_old: Remove the target from any interface it was previously mapped to.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    interface = InterfaceModel.get_model(name=interface_name, scope=scope)
    if isinstance(target_name, list):
        target_names = target_name
    else:
        target_names = [target_name]
    for name in target_names:
        interface.map_target(name, cmd_only=cmd_only, tlm_only=tlm_only, unmap_old=unmap_old)
        Logger.info(f"Target {name} mapped to Interface {interface_name}", scope=scope)


def unmap_target_from_interface(
    target_name: str | list[str],
    interface_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Unmap one or more targets from an interface.

    None of the target's commands go out over, and no telemetry is received
    from, that interface.

    Args:
        target_name: Target name, or a list of target names.
        interface_name: Interface name.
        cmd_only: Unmap only the target's commands.
        tlm_only: Unmap only the target's telemetry.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    interface = InterfaceModel.get_model(name=interface_name, scope=scope)
    if isinstance(target_name, list):
        target_names = target_name
    else:
        target_names = [target_name]
    for name in target_names:
        interface.unmap_target(name, cmd_only=cmd_only, tlm_only=tlm_only)
        Logger.info(f"Target {name} unmapped from Interface {interface_name}", scope=scope)


def interface_cmd(interface_name: str, cmd_name: str, *cmd_params: Any, scope: str = OPENC3_SCOPE) -> None:
    """Send a command directly to an interface.

    The command is handled by the interface's `interface_cmd` method. The
    base Interface class supports clear_counters.

    Args:
        interface_name: Interface name.
        cmd_name: Name of the interface command.
        *cmd_params: Parameters for the interface command.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    InterfaceTopic.interface_cmd(interface_name, cmd_name, *cmd_params, scope=scope)


def interface_protocol_cmd(
    interface_name: str,
    cmd_name: str,
    *cmd_params: Any,
    read_write: str = "READ_WRITE",
    index: int = -1,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Send a command to the protocols of an interface.

    The command is handled by each matching protocol's `protocol_cmd` method.

    Args:
        interface_name: Interface name.
        cmd_name: Name of the protocol command.
        *cmd_params: Parameters for the protocol command.
        read_write: Protocols to send to: READ, WRITE or READ_WRITE (default).
        index: Index of the protocol in the stack to send to. -1 (default)
            sends to every protocol.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    InterfaceTopic.protocol_cmd(
        interface_name,
        cmd_name,
        *cmd_params,
        read_write=read_write,
        index=index,
        scope=scope,
    )


def interface_target_enable(
    interface_name: str,
    target_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Enable a target on an interface.

    Setting both cmd_only and tlm_only is the same as setting neither.

    Args:
        interface_name: Interface name.
        target_name: Target name.
        cmd_only: Enable only the target's commands.
        tlm_only: Enable only the target's telemetry.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    interface = InterfaceModel.get_model(name=interface_name, scope=scope)
    if cmd_only and tlm_only:
        cmd_only = False
        tlm_only = False
    if not tlm_only:
        interface.cmd_target_enabled[target_name.upper()] = True
    if not cmd_only:
        interface.tlm_target_enabled[target_name.upper()] = True
    interface.update()
    InterfaceTopic.interface_target_enable(
        interface_name, target_name, cmd_only=cmd_only, tlm_only=tlm_only, scope=scope
    )


def interface_target_disable(
    interface_name: str,
    target_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Disable a target on an interface.

    Setting both cmd_only and tlm_only is the same as setting neither.

    Args:
        interface_name: Interface name.
        target_name: Target name.
        cmd_only: Disable only the target's commands.
        tlm_only: Disable only the target's telemetry.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", interface_name=interface_name, scope=scope)
    interface = InterfaceModel.get_model(name=interface_name, scope=scope)
    if cmd_only and tlm_only:
        cmd_only = False
        tlm_only = False
    if not tlm_only:
        interface.cmd_target_enabled[target_name.upper()] = False
    if not cmd_only:
        interface.tlm_target_enabled[target_name.upper()] = False
    interface.update()
    InterfaceTopic.interface_target_disable(
        interface_name, target_name, cmd_only=cmd_only, tlm_only=tlm_only, scope=scope
    )


def interface_details(interface_name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return detailed runtime information from a running interface.

    Args:
        interface_name: Interface name.
        scope: COSMOS scope.

    Returns:
        Interface details such as its configuration, target mappings and
        enables, and recent raw data.

    Raises:
        RuntimeError: If the interface does not respond in time or fails to
            return details.
    """
    authorize(permission="system", interface_name=interface_name, scope=scope)
    return InterfaceTopic.interface_details(interface_name, scope=scope)
