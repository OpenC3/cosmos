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
from datetime import datetime
from typing import Any

import openc3.script
from openc3.environment import OPENC3_SCOPE
from openc3.packets.packet import Packet
from openc3.top_level import CriticalCmdError, HazardousError
from openc3.utilities.extract import *


def cmd(*args: Any, **kwargs: Any) -> None:
    """Send a command packet to a target.

    The script logs the command and, if it is hazardous or critical, prompts
    the user before sending it.

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
            to send the command to, or False to bypass OPENC3_DEFAULT_QUEUE)
            and extra (dict of extra data to send with the command).
    """
    return _cmd("cmd", "cmd_no_hazardous_check", *args, **kwargs)


def cmd_raw(*args: Any, **kwargs: Any) -> None:
    """Send a command packet to a target without converting the parameter values.

    Parameter values are given as RAW values. See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.
    """
    return _cmd("cmd_raw", "cmd_raw_no_hazardous_check", *args, **kwargs)


def cmd_no_range_check(*args: Any, **kwargs: Any) -> None:
    """Send a command packet to a target without range checking the parameters.

    Useful for testing to allow sending parameters outside the allowable
    range defined in the configuration. See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.
    """
    return _cmd("cmd_no_range_check", "cmd_no_checks", *args, **kwargs)


def cmd_raw_no_range_check(*args: Any, **kwargs: Any) -> None:
    """Send a command with RAW parameter values and without range checking the parameters.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.
    """
    return _cmd("cmd_raw_no_range_check", "cmd_raw_no_checks", *args, **kwargs)


def cmd_no_hazardous_check(*args: Any, **kwargs: Any) -> None:
    """Send a command packet to a target without hazardous checks.

    Hazardous checks are skipped on both the command and its parameters.
    Useful in scripts to prevent prompting the user. See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.
    """
    return _cmd("cmd_no_hazardous_check", None, *args, **kwargs)


def cmd_raw_no_hazardous_check(*args: Any, **kwargs: Any) -> None:
    """Send a command with RAW parameter values and without hazardous checks.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.
    """
    return _cmd("cmd_raw_no_hazardous_check", None, *args, **kwargs)


def cmd_no_checks(*args: Any, **kwargs: Any) -> None:
    """Send a command packet to a target without range or hazardous checks.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.
    """
    return _cmd("cmd_no_checks", None, *args, **kwargs)


def cmd_raw_no_checks(*args: Any, **kwargs: Any) -> None:
    """Send a command with RAW parameter values and without range or hazardous checks.

    See `cmd` for the calling styles.

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Keyword arguments described in `cmd`.
    """
    return _cmd("cmd_raw_no_checks", None, *args, **kwargs)


def build_cmd(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Build a command binary without sending it.

    Accepts two calling styles. Favor the first as it is more succinct::

        build_cmd("TGT CMD with PARAM1 val, PARAM2 val")
        build_cmd("TGT", "CMD", {"PARAM1": val, "PARAM2": val})

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Not supported. Keyword arguments are not forwarded to the API server.

    Returns:
        The built command with the raw bytes under the "buffer" key.
    """
    extract_string_kwargs_to_args(args, kwargs)
    return openc3.script.API_SERVER.build_cmd(*args)


# build_command is DEPRECATED
build_command = build_cmd


def get_cmd_hazardous(*args: Any, **kwargs: Any) -> bool:
    """Return whether a command is hazardous.

    A command is hazardous if the command itself is marked hazardous or if a
    given parameter value matches the name or value of a hazardous state.

    Accepts two calling styles::

        get_cmd_hazardous("TGT CMD with PARAM1 val, PARAM2 val")
        get_cmd_hazardous("TGT", "CMD", {"PARAM1": val, "PARAM2": val})

    Args:
        *args: A single "TGT CMD with PARAM1 val, PARAM2 val" string, or the
            target name, command name and optional dict of parameter values.
        **kwargs: Not supported. Keyword arguments are not forwarded to the API server.

    Returns:
        Whether the command is hazardous.
    """
    extract_string_kwargs_to_args(args, kwargs)
    return openc3.script.API_SERVER.get_cmd_hazardous(*args)


def get_cmd_time(
    target_name: str | None = None, command_name: str | None = None, scope: str = OPENC3_SCOPE
) -> list[Any]:
    """Return the time the most recent command was sent.

    Args:
        target_name: Target name of the command. If not given, the most recent
            time from all commands is returned.
        command_name: Command name. If not given, the most recent time from
            the given target is returned.
        scope: COSMOS scope.

    Returns:
        The target name, command name and the time as a datetime. If either
        the whole seconds or the microseconds from the server are 0 (e.g. no
        command has been sent), the time is not converted and the list holds
        the target name, command name, whole seconds and microseconds.
    """
    results = openc3.script.API_SERVER.get_cmd_time(target_name, command_name, scope=scope)
    results = list(results)
    if results[2] and results[3]:
        results[2] = datetime.fromtimestamp(results[2] + results[3] / 1000000)
        results.pop(3)
    return results


# Format the command like it appears in a script
def _cmd_string(
    target_name: str,
    cmd_name: str,
    cmd_params: dict[str, Any] | None,
    raw: bool,
    obfuscated_items: list[str] | str | None,
):
    # Normally obfuscated_items is returned as an list formatted as a JSON string
    # because we're hitting the API server, but in the case of a disconnect command, it is a list
    if obfuscated_items and isinstance(obfuscated_items, str):
        obfuscated_items = json.loads(obfuscated_items)

    output_string = ""
    if openc3.script.DISCONNECT:
        output_string += "openc3.script.DISCONNECT: "
    if raw:
        output_string += 'cmd_raw("'
    else:
        output_string += 'cmd("'
    output_string += target_name + " " + cmd_name
    if not cmd_params:
        output_string += '")'
    else:
        params = []
        for key, value in cmd_params.items():
            if key in Packet.RESERVED_ITEM_NAMES:
                continue
            if obfuscated_items and key in obfuscated_items:
                params.append(f"{key} *****")
            else:
                if isinstance(value, str):
                    if not value.isascii():
                        value = "BINARY"
                    elif len(value) > 256:
                        value = value[:255] + "...'"
                    value = value.replace('"', "'")
                elif isinstance(value, list):
                    value = str(value)
                params.append(f"{key} {value}")
        params = ", ".join(params)
        output_string += " with " + params + '")'
    return output_string


# Log any warnings about disabling checks and log the command itself
# NOTE: This is a helper method and should not be called directly
def _log_cmd(cmd: dict[str, Any], raw: bool, no_range: bool, no_hazardous: bool):
    if no_range:
        print(f"WARN: Command {cmd['target_name']} {cmd['cmd_name']} being sent ignoring range checks")
    if no_hazardous:
        print(f"WARN: Command {cmd['target_name']} {cmd['cmd_name']} being sent ignoring hazardous warnings")
    print(
        _cmd_string(
            cmd["target_name"],
            cmd["cmd_name"],
            cmd["cmd_params"],
            raw,
            cmd["obfuscated_items"],
        )
    )


def _cmd_disconnect(cmd: str, raw: bool, no_range: bool, no_hazardous: bool, *args: Any, scope: str):
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
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {cmd}()")

    # Get the command and validate the parameters
    command = openc3.script.API_SERVER.get_cmd(target_name, cmd_name, scope=scope)
    # This returns a packet hash instead of the command hash so add missing fields
    command["cmd_name"] = cmd_name
    command["cmd_params"] = cmd_params
    if cmd_params:
        for param_name in cmd_params:
            found = False
            if "items" in command:
                for item in command["items"]:
                    if item["name"] == param_name:
                        found = item
                        break
            if not found:
                raise RuntimeError(
                    f"Item '{target_name} {cmd_name} {param_name}' does not exist (command parameter validation)"
                )
    _log_cmd(command, raw, no_range, no_hazardous)


# Send the command and log the results
# This method signature has to include the keyword params present in cmd_api.py cmd_implementation()
# NOTE: This is a helper method and should not be called directly
def _cmd(
    cmd: str,
    cmd_no_hazardous: Any,
    *args: Any,
    timeout: float | None = None,
    log_message: bool | None = None,
    validate: bool = True,
    queue: str | bool | None = None,
    extra: dict[str, Any] | None = None,
    scope: str = OPENC3_SCOPE,
):
    raw = "raw" in cmd
    no_range = "no_range" in cmd or "no_checks" in cmd
    no_hazardous = "no_hazardous" in cmd or "no_checks" in cmd
    # Only send extra when given so commands still work against servers that predate it
    extra_kwargs = {} if extra is None else {"extra": extra}

    if openc3.script.DISCONNECT:
        _cmd_disconnect(cmd, raw, no_range, no_hazardous, *args, scope=scope)
    else:
        try:
            try:
                command = getattr(openc3.script.API_SERVER, cmd)(
                    *args,
                    timeout=timeout,
                    log_message=log_message,
                    validate=validate,
                    queue=queue,
                    **extra_kwargs,
                    scope=scope,
                )
                if log_message is None or log_message:
                    _log_cmd(command, raw, no_range, no_hazardous)
            except HazardousError as error:
                # Need to reimport here to pick up changes from running_script
                from openc3.script import prompt_for_hazardous

                # This opens a prompt at which point they can cancel and stop the script
                # or say Yes and send the command. Thus we don't care about the return value.
                prompt_for_hazardous(
                    error.target_name,
                    error.cmd_name,
                    error.hazardous_description,
                )
                command = getattr(openc3.script.API_SERVER, cmd_no_hazardous)(
                    *args,
                    timeout=timeout,
                    log_message=log_message,
                    validate=validate,
                    queue=queue,
                    **extra_kwargs,
                    scope=scope,
                )
                if log_message is None or log_message:
                    _log_cmd(command, raw, no_range, no_hazardous)
        except CriticalCmdError as error:
            # Need to reimport here to pick up changes from running_script
            from openc3.script import prompt_for_critical_cmd

            # This should not return until the critical command has been approved
            prompt_for_critical_cmd(
                error.uuid,
                error.command["username"],
                error.command["target_name"],
                error.command["cmd_name"],
                error.command["cmd_params"],
                error.command["cmd_string"],
            )
            if log_message is None or log_message:
                _log_cmd(error.command, raw, no_range, no_hazardous)
