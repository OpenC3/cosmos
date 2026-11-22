# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963


import contextlib
import json
import os
from contextlib import contextmanager
from typing import Any

from openc3.api import WHITELIST
from openc3.api.api_types import ValueType
from openc3.api.interface_api import get_interface
from openc3.environment import OPENC3_SCOPE
from openc3.models.queue_model import QueueModel
from openc3.models.shared_resource_model import SharedResourceModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet  # noqa: F401
from openc3.top_level import DisabledError
from openc3.topics.command_decom_topic import CommandDecomTopic
from openc3.topics.command_topic import CommandTopic
from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.topic import Topic
from openc3.utilities.authorization import authorize
from openc3.utilities.cmd_log import _build_cmd_output_string
from openc3.utilities.extract import extract_fields_from_cmd_text
from openc3.utilities.store import Store


WHITELIST.extend(
    [
        "cmd",
        "cmd_no_range_check",
        "cmd_no_hazardous_check",
        "cmd_no_checks",
        "cmd_raw",
        "cmd_raw_no_range_check",
        "cmd_raw_no_hazardous_check",
        "cmd_raw_no_checks",
        "build_cmd",
        "build_command",  # DEPRECATED
        "enable_cmd",
        "disable_cmd",
        "send_raw",
        "get_all_cmds",
        "get_all_commands",  # DEPRECATED
        "get_all_cmd_names",
        "get_all_command_names",  # DEPRECATED
        "get_cmd",
        "get_command",  # DEPRECATED
        "get_param",
        "get_parameter",  # DEPRECATED
        "get_cmd_buffer",
        "get_cmd_hazardous",
        "get_cmd_value",
        "get_cmd_time",
        "get_cmd_cnt",
        "get_cmd_cnts",
    ]
)


def cmd(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command packet to a target.

    The cmd_raw variants send RAW parameter values without conversions.

    Accepts two calling styles. Favor the first as it is more succinct::

        cmd("TGT CMD with PARAM1 val, PARAM2 val")
        cmd("TGT", "CMD", {"PARAM1": val, "PARAM2": val})

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Optional keyword arguments: scope (COSMOS scope), timeout
            (seconds to wait for the command acknowledgement), log_message
            (True or False to override whether the command is logged),
            validate (True or False, default True), queue (name of the queue
            to send the command to, or False to bypass OPENC3_DEFAULT_QUEUE),
            queue_username (user who queued the command), extra (dict of
            extra data to send with the command) and manual (whether the
            request was made manually by a user, default False).

    Returns:
        The command that was sent, as a dict.

    Raises:
        RuntimeError: If the number of arguments is invalid, or the timeout,
            log_message, validate or extra keyword argument is invalid.
        DisabledError: If the command is disabled.
    """
    return _cmd_implementation(
        "cmd",
        *args,
        range_check=True,
        hazardous_check=True,
        raw=False,
        **kwargs,
    )


def cmd_raw(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command packet to a target without converting the parameter values.

    Parameter values are given as RAW values. See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.

    Returns:
        The command that was sent, as a dict.
    """
    return _cmd_implementation(
        "cmd_raw",
        *args,
        range_check=True,
        hazardous_check=True,
        raw=True,
        **kwargs,
    )


def cmd_no_range_check(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command packet to a target without range checking the parameters.

    Useful for testing to allow sending parameters outside the allowable
    range defined in the configuration. See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.

    Returns:
        The command that was sent, as a dict.
    """
    return _cmd_implementation(
        "cmd_no_range_check",
        *args,
        range_check=False,
        hazardous_check=True,
        raw=False,
        **kwargs,
    )


def cmd_raw_no_range_check(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command with RAW parameter values and without range checking the parameters.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.

    Returns:
        The command that was sent, as a dict.
    """
    return _cmd_implementation(
        "cmd_raw_no_range_check",
        *args,
        range_check=False,
        hazardous_check=True,
        raw=True,
        **kwargs,
    )


def cmd_no_hazardous_check(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command packet to a target without hazardous checks.

    Hazardous checks are skipped on both the command and its parameters.
    Useful in scripts to prevent popping up warnings to the user. See `cmd`
    for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.

    Returns:
        The command that was sent, as a dict.
    """
    return _cmd_implementation(
        "cmd_no_hazardous_check",
        *args,
        range_check=True,
        hazardous_check=False,
        raw=False,
        **kwargs,
    )


def cmd_raw_no_hazardous_check(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command with RAW parameter values and without hazardous checks.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.

    Returns:
        The command that was sent, as a dict.
    """
    return _cmd_implementation(
        "cmd_raw_no_hazardous_check",
        *args,
        range_check=True,
        hazardous_check=False,
        raw=True,
        **kwargs,
    )


def cmd_no_checks(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command packet to a target without range or hazardous checks.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.

    Returns:
        The command that was sent, as a dict.
    """
    return _cmd_implementation(
        "cmd_no_checks",
        *args,
        range_check=False,
        hazardous_check=False,
        raw=False,
        **kwargs,
    )


def cmd_raw_no_checks(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Send a command with RAW parameter values and without range or hazardous checks.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.

    Returns:
        The command that was sent, as a dict.
    """
    return _cmd_implementation(
        "cmd_raw_no_checks",
        *args,
        range_check=False,
        hazardous_check=False,
        raw=True,
        **kwargs,
    )


def build_cmd(
    *args: Any,
    range_check: bool = True,
    raw: bool = False,
    timeout: float = 5,
    scope: str = OPENC3_SCOPE,
    manual: bool = False,
) -> dict[str, Any]:
    """Build a command binary without sending it.

    Accepts two calling styles. Favor the first as it is more succinct::

        build_cmd("TGT CMD with PARAM1 val, PARAM2 val")
        build_cmd("TGT", "CMD", {"PARAM1": val, "PARAM2": val})

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        range_check: Whether to range check the parameters.
        raw: Whether the parameter values are RAW values.
        timeout: Seconds to wait for the decom microservice to build the command.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        The built command with the raw bytes under the "buffer" key.

    Raises:
        RuntimeError: If the number of arguments is invalid.
    """
    match len(args):
        case 1:
            target_name, cmd_name, cmd_params = extract_fields_from_cmd_text(args[0])
        case 2 | 3:
            target_name = args[0]
            cmd_name = args[1]
            if len(args) == 2:
                cmd_params = {}
            else:
                cmd_params = args[2]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to build_command()")
    target_name = target_name.upper()
    cmd_name = cmd_name.upper()
    cmd_params = {k.upper(): v for k, v in cmd_params.items()}
    authorize(permission="cmd_info", target_name=target_name, scope=scope, manual=manual)
    return DecomInterfaceTopic.build_cmd(target_name, cmd_name, cmd_params, range_check, raw, timeout, scope)


# build_command is DEPRECATED
build_command = build_cmd


# Helper method for disable_cmd / enable_cmd
@contextmanager
def _get_and_set_cmd(method: str, *args: str, scope: str = OPENC3_SCOPE, manual: bool = False):
    target_name, command_name = _extract_target_command_names(method, *args)
    authorize(
        permission="admin",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    command = TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    yield command
    TargetModel.set_packet(target_name, command_name, command, type="CMD", scope=scope)


def enable_cmd(*args: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> None:
    """Enable a command so it can be sent. Reverses `disable_cmd`.

    Accepts two calling styles::

        enable_cmd("TGT CMD")
        enable_cmd("TGT", "CMD")

    Args:
        *args: A single "TGT CMD" string, or the target and command names.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.
    """
    with _get_and_set_cmd("enable_cmd", *args, scope=scope, manual=manual) as command:
        command.pop("disabled", None)


def disable_cmd(*args: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> None:
    """Disable a command so that sending it raises a DisabledError.

    Accepts two calling styles::

        disable_cmd("TGT CMD")
        disable_cmd("TGT", "CMD")

    Args:
        *args: A single "TGT CMD" string, or the target and command names.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.
    """
    with _get_and_set_cmd("disable_cmd", *args, scope=scope, manual=manual) as command:
        command["disabled"] = True


def send_raw(interface_name: str, data: bytes, scope: str = OPENC3_SCOPE, manual: bool = False) -> None:
    """Send raw binary data to an interface.

    Args:
        interface_name: Name of the interface to write the data to.
        data: The raw binary data.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.
    """
    interface_name = interface_name.upper()
    authorize(permission="cmd_raw", interface_name=interface_name, scope=scope, manual=manual)
    get_interface(interface_name, scope=scope)  # Check to make sure the interface exists
    SharedResourceModel.check_interface_active("INTERFACE", interface_name, scope=scope)
    InterfaceTopic.write_raw(interface_name, data, scope=scope)


def get_cmd_buffer(*args: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> dict[str, Any] | None:
    """Return the most recent raw buffer for a command packet.

    Accepts two calling styles::

        get_cmd_buffer("TGT CMD")
        get_cmd_buffer("TGT", "CMD")

    Args:
        *args: A single "TGT CMD" string, or the target and command names.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        The command message with the raw bytes under the "buffer" key, or
        None if the command has not been sent.
    """
    target_name, command_name = _extract_target_command_names("get_cmd_buffer", *args)
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    topic = f"{scope}__COMMAND__{{{target_name}}}__{command_name}"
    db_shard = Store.db_shard_for_target(target_name, scope=scope)
    msg_id, message = Topic.get_newest_message(topic, db_shard=db_shard)
    if msg_id:
        # Decode the keys for user convenience
        return {k.decode(): v for (k, v) in message.items()}
    return None


def get_all_cmds(target_name: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> list[dict[str, Any]]:
    """Return the definitions of all the command packets in a target.

    Args:
        target_name: Name of the target.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        One packet definition dict per command packet.
    """
    target_name = target_name.upper()
    authorize(permission="cmd_info", target_name=target_name, scope=scope, manual=manual)
    return TargetModel.packets(target_name, type="CMD", scope=scope)


# get_all_commands is DEPRECATED
get_all_commands = get_all_cmds


def get_all_cmd_names(
    target_name: str, hidden: bool = False, scope: str = OPENC3_SCOPE, manual: bool = False
) -> list[str]:
    """Return the names of all the command packets in a target.

    Args:
        target_name: Name of the target.
        hidden: Whether to include packets marked HIDDEN.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        The packet names, or an empty list if the target does not exist or
        the user is not authorized.
    """
    target_name = target_name.upper()
    # Only the names are needed so avoid parsing every packet definition
    try:
        authorize(permission="cmd_info", target_name=target_name, scope=scope, manual=manual)
        names = TargetModel.packet_names(target_name, type="CMD", scope=scope)
        if not hidden:
            hidden_names = set(TargetModel.hidden_packet_names(target_name, type="CMD", scope=scope))
            names = [name for name in names if name not in hidden_names]
    except Exception:
        names = []
    return names


# get_all_command_names is DEPRECATED
get_all_command_names = get_all_cmd_names


def get_cmd(*args: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> dict[str, Any]:
    """Return the definition of a command packet.

    Accepts two calling styles::

        get_cmd("TGT CMD")
        get_cmd("TGT", "CMD")

    Args:
        *args: A single "TGT CMD" string, or the target and command names.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        The packet definition, including its parameters.
    """
    target_name, command_name = _extract_target_command_names("get_cmd", *args)
    authorize(permission="cmd_info", target_name=target_name, scope=scope, manual=manual)
    return TargetModel.packet(target_name, command_name, type="CMD", scope=scope)


# get_command is DEPRECATED
get_command = get_cmd


def get_param(*args: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> dict[str, Any]:
    """Return the definition of a command parameter.

    Accepts two calling styles::

        get_param("TGT CMD PARAM")
        get_param("TGT", "CMD", "PARAM")

    Args:
        *args: A single "TGT CMD PARAM" string, or the target, command and
            parameter names.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        The parameter definition.
    """
    target_name, command_name, parameter_name = _extract_target_command_parameter_names("get_param", *args)
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    return TargetModel.packet_item(target_name, command_name, parameter_name, type="CMD", scope=scope)


# get_parameter is DEPRECATED
get_parameter = get_param


def get_cmd_hazardous(*args: Any, scope: str = OPENC3_SCOPE, manual: bool = False) -> bool:
    """Return whether a command is hazardous.

    A command is hazardous if the command itself is marked hazardous or if a
    given parameter value matches the name or value of a hazardous state.

    Accepts two calling styles::

        get_cmd_hazardous("TGT CMD with PARAM1 val, PARAM2 val")
        get_cmd_hazardous("TGT", "CMD", {"PARAM1": val, "PARAM2": val})

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        Whether the command is hazardous.

    Raises:
        RuntimeError: If the number of arguments is invalid.
    """
    match len(args):
        case 1:
            target_name, command_name, parameters = extract_fields_from_cmd_text(args[0])
            target_name = target_name.upper()
            command_name = command_name.upper()
            parameters = {k.upper(): v for k, v in parameters.items()}
        case 2 | 3:
            target_name = args[0].upper()
            command_name = args[1].upper()
            if len(args) == 2:
                parameters = {}
            else:
                parameters = {k.upper(): v for k, v in args[2].items()}

        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to get_cmd_hazardous()")

    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    packet = TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    if packet.get("hazardous") is not None:
        return True

    for item in packet["items"]:
        if item["name"] not in parameters or not item.get("states"):
            continue

        # States are an array of the name followed by a dict of 'value' and sometimes 'hazardous'
        for name, items in item["states"].items():
            parameter_name = parameters[item["name"]]
            # Remove quotes from string parameters
            if isinstance(parameter_name, str):
                parameter_name = parameter_name.replace('"', "").replace("'", "")
            # To be hazardous the state must be marked hazardous
            # Check if either the state name or value matches the param passed
            if items.get("hazardous") is not None and (name == parameter_name or items["value"] == parameter_name):
                return True
    return False


def get_cmd_value(
    *args: Any,
    type: ValueType = "CONVERTED",  # Ignore SonarQube warning, changing is a breaking change.
    scope: str = OPENC3_SCOPE,
    manual: bool = False,
) -> Any:
    """Return a parameter value from the most recently sent command.

    Accepts three calling styles::

        get_cmd_value("TGT CMD PARAM")
        get_cmd_value("TGT", "CMD", "PARAM")
        get_cmd_value("TGT", "CMD", "PARAM", "RAW")

    The parameter name can also be a reserved item such as RECEIVED_COUNT or
    RECEIVED_TIMESECONDS.

    Args:
        *args: A single "TGT CMD PARAM" string, or the target, command and
            parameter names optionally followed by the value type.
        type: Value type to return: RAW, CONVERTED (default) or FORMATTED.
            Overridden by a fourth positional argument.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        The parameter value in the requested type, or None if the command
        has not been sent.

    Raises:
        RuntimeError: If the arguments are invalid.
    """
    target_name = None
    command_name = None
    parameter_name = None
    match len(args):
        case 1:
            with contextlib.suppress(ValueError):
                target_name, command_name, parameter_name = args[0].upper().split()
        case 3:
            target_name = args[0].upper()
            command_name = args[1].upper()
            parameter_name = args[2].upper()
        case 4:
            target_name = args[0].upper()
            command_name = args[1].upper()
            parameter_name = args[2].upper()
            type = args[3].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to get_cmd_value()")
    if target_name is None or command_name is None:
        raise RuntimeError('Usage: get_cmd_value("TGT CMD PARAM") or get_cmd_value("TGT", "CMD", "PARAM")')

    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    return CommandDecomTopic.get_cmd_item(target_name, command_name, parameter_name, type=type, scope=scope)


def get_cmd_time(
    target_name: str | None = None,
    command_name: str | None = None,
    scope: str = OPENC3_SCOPE,
    manual: bool = False,
) -> tuple[str | None, str | None, int, int]:
    """Return the time the most recent command was sent.

    Args:
        target_name: Target name of the command. If not given, the most recent
            time from all commands is returned.
        command_name: Command name. If not given, the most recent time from
            the given target is returned.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        The target name, command name, time in whole seconds and the
        remaining microseconds. The names are None and the times 0 if no
        command has been sent.
    """
    authorize(
        permission="cmd_info",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    if target_name and command_name:
        target_name = target_name.upper()
        command_name = command_name.upper()
        time = CommandDecomTopic.get_cmd_item(
            target_name,
            command_name,
            "RECEIVED_TIMESECONDS",
            type="CONVERTED",
            scope=scope,
        )
        if time is None:
            time = 0
        return (
            target_name,
            command_name,
            int(time),
            int((time - int(time)) * 1_000_000),
        )
    else:
        if not target_name:
            targets = TargetModel.names(scope=scope)
        else:
            targets = [target_name.upper()]

        time = 0
        command_name = None
        for cur_target in targets:
            # Only the names are needed so avoid parsing every packet definition
            for packet_name in TargetModel.packet_names(cur_target, type="CMD", scope=scope):
                cur_time = CommandDecomTopic.get_cmd_item(
                    cur_target,
                    packet_name,
                    "RECEIVED_TIMESECONDS",
                    type="CONVERTED",
                    scope=scope,
                )
                if cur_time is None:
                    continue

                if cur_time > time:
                    time = cur_time
                    command_name = packet_name
                    target_name = cur_target

        if not command_name:
            target_name = None
        return (
            target_name,
            command_name,
            int(time),
            int((time - int(time)) * 1_000_000),
        )


def get_cmd_cnt(*args: str, scope: str = OPENC3_SCOPE, manual: bool = False) -> int:
    """Return the transmit count for a command packet.

    Accepts two calling styles::

        get_cmd_cnt("TGT CMD")
        get_cmd_cnt("TGT", "CMD")

    Args:
        *args: A single "TGT CMD" string, or the target and command names.
        scope: COSMOS scope.
        manual: Whether the request was made manually by a user.

    Returns:
        Number of times the command has been sent.
    """
    target_name, command_name = _extract_target_command_names("get_cmd_cnt", *args)
    authorize(
        permission="system",
        target_name=target_name,
        packet_name=command_name,
        scope=scope,
        manual=manual,
    )
    TargetModel.packet(target_name, command_name, type="CMD", scope=scope)
    return TargetModel.get_command_count(target_name, command_name, scope=scope)


def get_cmd_cnts(target_commands: list[list[str]], scope: str = OPENC3_SCOPE) -> list[int]:
    """Return the transmit counts for several command packets.

    Args:
        target_commands: [target name, command name] pairs.
        scope: COSMOS scope.

    Returns:
        The transmit count of each command, in the same order.

    Raises:
        RuntimeError: If target_commands is not a nested list.
    """
    authorize(permission="system", scope=scope)
    if isinstance(target_commands, list) and len(target_commands) > 0 and isinstance(target_commands[0], list):
        return TargetModel.get_command_counts(target_commands, scope=scope)
    else:
        raise RuntimeError(
            "get_cmd_cnts takes a list of lists containing target, packet_name, e.g. [['INST', 'COLLECT'], ['INST', 'ABORT']]"
        )


def _extract_target_command_names(method_name: str, *args: str):
    target_name = None
    command_name = None
    match len(args):
        case 1:
            with contextlib.suppress(ValueError):
                target_name, command_name = args[0].upper().split()
        case 2:
            target_name = args[0].upper()
            command_name = args[1].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or command_name is None:
        raise RuntimeError(
            f'ERROR: Target name and command name required. Usage: {method_name}("TGT CMD") or {method_name}("TGT", "CMD")'
        )
    return (target_name, command_name)


def _extract_target_command_parameter_names(method_name: str, *args: str):
    target_name = None
    command_name = None
    parameter_name = None
    match len(args):
        case 1:
            with contextlib.suppress(ValueError):
                target_name, command_name, parameter_name = args[0].upper().split()
        case 3:
            target_name = args[0].upper()
            command_name = args[1].upper()
            parameter_name = args[2].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or command_name is None:
        raise RuntimeError(
            f'ERROR: Target name, command name and parameter name required. Usage: {method_name}("TGT CMD PARAM") or {method_name}("TGT", "CMD", "PARAM")'
        )
    return (target_name, command_name, parameter_name)


def _cmd_implementation(
    method_name: str,
    *args: Any,
    range_check: bool,
    hazardous_check: bool,
    raw: bool,
    manual: bool = False,
    **kwargs: Any,
):
    scope = OPENC3_SCOPE
    if kwargs.get("scope"):
        scope = kwargs["scope"]

    match len(args):
        case 1:
            target_name, cmd_name, cmd_params = extract_fields_from_cmd_text(args[0])
        case 2 | 3:
            target_name = args[0]
            cmd_name = args[1]
            if len(args) == 2:
                cmd_params = {}
            else:
                cmd_params = args[2]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")

    target_name = target_name.upper()
    cmd_name = cmd_name.upper()
    cmd_params = {k.upper(): v for k, v in cmd_params.items()}
    user = authorize(
        permission="cmd",
        target_name=target_name,
        packet_name=cmd_name,
        scope=scope,
        manual=manual,
    )
    SharedResourceModel.check_target_active(target_name, scope=scope)
    queue_username = kwargs.get("queue_username")
    extra = kwargs.get("extra")
    if extra is not None and not isinstance(extra, dict):
        raise RuntimeError(f"Invalid extra parameter: {extra}. Must be a dict.")
    if not user:
        user = {}
        user["username"] = os.environ.get("OPENC3_MICROSERVICE_NAME")

        # Get the caller stack trace to determine the point in the code where the command was called
        # This code works but ultimately we didn't want to overload 'username' and take a performance hit
        # stack_trace = traceback.extract_stack()
        # for frame in stack_trace:
        #     # Look for the following line in the stack trace which indicates custom code
        #     # File "/tmp/tmpp96e6j83/targets/INST2/lib/example_limits_response.py", line 25, in call"
        #     if f"/targets/{target_name}" in frame.filename:
        #         user = {}
        #         # username is the name of the custom code file
        #         user["username"] = frame.filename.split("/targets/")[-1].split('"')[0]
        #         break

    packet = TargetModel.packet(target_name, cmd_name, type="CMD", scope=scope)
    if packet.get("disabled", False):
        error = DisabledError()
        error.target_name = target_name
        error.cmd_name = cmd_name
        raise error

    timeout = None
    if kwargs.get("timeout") is not None:
        try:
            timeout = float(kwargs["timeout"])
        except (TypeError, ValueError) as e:
            raise RuntimeError(f"Invalid timeout parameter: {kwargs['timeout']}. Must be numeric.") from e

    # Determine if we should log this command
    log_message = True  # Default is True
    # If the packet has the DISABLE_MESSAGES keyword then no messages
    if packet.get("messages_disabled"):
        log_message = False
    else:
        # Check if any of the parameters have DISABLE_MESSAGES
        for key, value in cmd_params.items():
            found = None
            for item in packet["items"]:
                if item["name"] == key:
                    found = item
                    break
            if (
                found
                and "states" in found
                and value in found["states"]
                and found["states"][value].get("messages_disabled")
            ):
                log_message = False
    # If they explicitly set the log_message kwarg then that overrides the above
    if kwargs.get("log_message") is not None:
        if kwargs["log_message"] not in [True, False]:
            raise RuntimeError(f"Invalid log_message parameter: {kwargs['log_message']}. Must be True or False.")
        log_message = kwargs["log_message"]
    cmd_string = _build_cmd_output_string(method_name, target_name, cmd_name, cmd_params, packet)

    # Check for the validate kwarg
    validate = True
    if kwargs.get("validate") is not None:
        if kwargs["validate"] not in [True, False]:
            raise RuntimeError(f"Invalid validate parameter: {kwargs['validate']}. Must be True or False.")
        validate = kwargs["validate"]

    username = user["username"] if user and user["username"] else "anonymous"
    command = {
        "target_name": target_name,
        "cmd_name": cmd_name,
        "cmd_params": cmd_params,
        "range_check": str(range_check),
        "hazardous_check": str(hazardous_check),
        "raw": str(raw),
        "cmd_string": cmd_string,
        "username": username,
        "validate": str(validate),
        "manual": str(manual),
        "log_message": str(log_message),
        "obfuscated_items": json.dumps(packet.get("obfuscated_items", [])),
    }
    if extra is not None:
        command["extra"] = extra
    # Record the original queuing user (author) separately from 'username' (the
    # user or process that actually executed the command). Command History shows
    # 'username' as "Executed By" and queue_username as "Queued By".
    if queue_username:
        command["queue_username"] = queue_username

    # Users have to explicitly opt into a default queue by setting the OPENC3_DEFAULT_QUEUE
    # At which point ALL commands will go to that queue unless they specifically opt out with queue=False
    queue = kwargs.get("queue")
    if os.environ.get("OPENC3_DEFAULT_QUEUE", False) and queue is None:
        queue = os.environ["OPENC3_DEFAULT_QUEUE"]
    if queue:
        # Pull the command out of the script string, e.g. cmd("INST ABORT")
        queued = cmd_string.split('("')[1].split('")')[0]
        QueueModel.queue_command(
            queue, command=queued, username=username, scope=scope, validate=validate, timeout=timeout, extra=extra
        )
    else:
        CommandTopic.send_command(command, timeout=timeout, scope=scope)
    return command
