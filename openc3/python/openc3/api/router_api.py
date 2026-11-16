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
from openc3.models.router_model import RouterModel
from openc3.models.router_status_model import RouterStatusModel
from openc3.topics.router_topic import RouterTopic
from openc3.utilities.authorization import authorize
from openc3.utilities.logger import Logger


WHITELIST.extend(
    [
        "get_router",
        "get_router_names",
        "connect_router",
        "disconnect_router",
        "start_raw_logging_router",
        "stop_raw_logging_router",
        "get_all_router_info",
        "router_cmd",
        "router_protocol_cmd",
        "map_target_to_router",
        "unmap_target_from_router",
        "router_target_enable",
        "router_target_disable",
        "router_details",
    ]
)


def get_router(router_name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return the configuration and current status of a router.

    Args:
        router_name: Router name.
        scope: COSMOS scope.

    Returns:
        The router configuration merged with its status (state, clients,
        queue sizes, byte and packet counts).

    Raises:
        RuntimeError: If the router does not exist.
    """
    authorize(permission="system", router_name=router_name, scope=scope)
    router = RouterModel.get(name=router_name, scope=scope)
    if not router:
        raise RuntimeError(f"Router '{router_name}' does not exist (get_router)")
    return router | RouterStatusModel.get_or_default(name=router_name, scope=scope)


def get_router_names(scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all routers.

    Args:
        scope: COSMOS scope.

    Returns:
        Sorted router names.
    """
    authorize(permission="system", scope=scope)
    return RouterModel.names(scope=scope)


def connect_router(router_name: str, *router_params: Any, scope: str = OPENC3_SCOPE) -> None:
    """Connect a router and start its command gathering thread.

    Args:
        router_name: Router name.
        *router_params: Optional parameters which replace the router's
            configured parameters when it is rebuilt.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.connect_router(router_name, *router_params, scope=scope)


def disconnect_router(router_name: str, scope: str = OPENC3_SCOPE) -> None:
    """Disconnect a router and stop its command gathering thread.

    Args:
        router_name: Router name.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.disconnect_router(router_name, scope=scope)


def start_raw_logging_router(router_name: str = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Start raw logging on a router.

    Args:
        router_name: Router name, or ALL (default) for every router.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    if router_name == "ALL":
        for router_name in get_router_names():
            RouterTopic.start_raw_logging(router_name, scope=scope)
    else:
        RouterTopic.start_raw_logging(router_name, scope=scope)


def stop_raw_logging_router(router_name: str = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Stop raw logging on a router.

    Args:
        router_name: Router name, or ALL (default) for every router.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    if router_name == "ALL":
        for router_name in get_router_names():
            RouterTopic.stop_raw_logging(router_name, scope=scope)
    else:
        RouterTopic.stop_raw_logging(router_name, scope=scope)


def get_all_router_info(scope: str = OPENC3_SCOPE) -> list[list[Any]]:
    """Return status information about all routers in a single call.

    Args:
        scope: COSMOS scope.

    Returns:
        One list per router containing [name, state, num clients,
        TX queue size, RX queue size, TX bytes, RX bytes, RX count,
        TX count]. A router receives commands and sends telemetry, so the
        RX count is the command count and the TX count is the telemetry count.
    """
    authorize(permission="system", scope=scope)
    info = []
    for _, router in RouterStatusModel.all(scope=scope).items():
        info.append(
            [
                router["name"],
                router["state"],
                router["clients"],
                router["txsize"],
                router["rxsize"],
                router["txbytes"],
                router["rxbytes"],
                router["rxcnt"],
                router["txcnt"],
            ]
        )
    return info


def router_cmd(router_name: str, cmd_name: str, *cmd_params: Any, scope: str = OPENC3_SCOPE) -> None:
    """Send a command directly to a router.

    The command is handled by the router's `interface_cmd` method. The
    base Interface class supports clear_counters.

    Args:
        router_name: Router name.
        cmd_name: Name of the router command.
        *cmd_params: Parameters for the router command.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.router_cmd(router_name, cmd_name, *cmd_params, scope=scope)


def router_protocol_cmd(
    router_name: str,
    cmd_name: str,
    *cmd_params: Any,
    read_write: str = "READ_WRITE",
    index: int = -1,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Send a command to the protocols of a router.

    The command is handled by each matching protocol's `protocol_cmd` method.

    Args:
        router_name: Router name.
        cmd_name: Name of the protocol command.
        *cmd_params: Parameters for the protocol command.
        read_write: Protocols to send to: READ, WRITE or READ_WRITE (default).
        index: Index of the protocol in the stack to send to. -1 (default)
            sends to every protocol.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    RouterTopic.protocol_cmd(
        router_name,
        cmd_name,
        *cmd_params,
        read_write=read_write,
        index=index,
        scope=scope,
    )


def map_target_to_router(
    target_name: str | list[str],
    router_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    unmap_old: bool = True,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Map one or more targets to a router.

    Args:
        target_name: Target name, or a list of target names.
        router_name: Router name.
        cmd_only: Map only the target's commands.
        tlm_only: Map only the target's telemetry.
        unmap_old: Remove the target from any router it was previously mapped to.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    router = RouterModel.get_model(name=router_name, scope=scope)
    if isinstance(target_name, list):
        target_names = target_name
    else:
        target_names = [target_name]
    for name in target_names:
        router.map_target(name, cmd_only=cmd_only, tlm_only=tlm_only, unmap_old=unmap_old)
        Logger.info(f"Target {name} mapped to Router {router_name}", scope=scope)


def unmap_target_from_router(
    target_name: str | list[str],
    router_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Unmap one or more targets from a router.

    Args:
        target_name: Target name, or a list of target names.
        router_name: Router name.
        cmd_only: Unmap only the target's commands.
        tlm_only: Unmap only the target's telemetry.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    router = RouterModel.get_model(name=router_name, scope=scope)
    if isinstance(target_name, list):
        target_names = target_name
    else:
        target_names = [target_name]
    for name in target_names:
        router.unmap_target(name, cmd_only=cmd_only, tlm_only=tlm_only)
        Logger.info(f"Target {name} unmapped from Router {router_name}", scope=scope)


def router_target_enable(
    router_name: str,
    target_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Enable a target on a router.

    Setting both cmd_only and tlm_only is the same as setting neither.

    Args:
        router_name: Router name.
        target_name: Target name.
        cmd_only: Enable only the target's commands.
        tlm_only: Enable only the target's telemetry.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    router = RouterModel.get_model(name=router_name, scope=scope)
    if cmd_only and tlm_only:
        cmd_only = False
        tlm_only = False
    if not tlm_only:
        router.cmd_target_enabled[target_name.upper()] = True
    if not cmd_only:
        router.tlm_target_enabled[target_name.upper()] = True
    router.update()
    RouterTopic.router_target_enable(router_name, target_name, cmd_only=cmd_only, tlm_only=tlm_only, scope=scope)


def router_target_disable(
    router_name: str,
    target_name: str,
    cmd_only: bool = False,
    tlm_only: bool = False,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Disable a target on a router.

    Setting both cmd_only and tlm_only is the same as setting neither.

    Args:
        router_name: Router name.
        target_name: Target name.
        cmd_only: Disable only the target's commands.
        tlm_only: Disable only the target's telemetry.
        scope: COSMOS scope.
    """
    authorize(permission="system_set", router_name=router_name, scope=scope)
    router = RouterModel.get_model(name=router_name, scope=scope)
    if cmd_only and tlm_only:
        cmd_only = False
        tlm_only = False
    if not tlm_only:
        router.cmd_target_enabled[target_name.upper()] = False
    if not cmd_only:
        router.tlm_target_enabled[target_name.upper()] = False
    router.update()
    RouterTopic.router_target_disable(router_name, target_name, cmd_only=cmd_only, tlm_only=tlm_only, scope=scope)


def router_details(router_name: str, scope: str = OPENC3_SCOPE) -> dict[str, Any]:
    """Return detailed runtime information from a running router.

    Args:
        router_name: Router name.
        scope: COSMOS scope.

    Returns:
        Router details such as its configuration, target mappings and
        enables, and recent raw data.

    Raises:
        RuntimeError: If the router does not respond in time or fails to
            return details.
    """
    authorize(permission="system", router_name=router_name, scope=scope)
    return RouterTopic.router_details(router_name, scope=scope)
