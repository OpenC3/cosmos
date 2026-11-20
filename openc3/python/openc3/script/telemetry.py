# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
from typing import Any

import openc3.script
from openc3.api.api_types import OverrideValueType, ValueType
from openc3.environment import OPENC3_SCOPE
from openc3.script.api_shared import openc3_script_sleep


def _format_call(method_name: str, args: tuple[Any, ...], type: str) -> str:
    # Format the call like it appears in a script, using only the arguments given
    # so a wrong number of arguments is reported by the API rather than here
    parts = [f'"{arg}"' if isinstance(arg, str) else str(arg) for arg in args]
    parts.append(f'type="{type}"')
    return f"{method_name}({', '.join(parts)})"


def get_packets(
    id: str, block: float | None = None, block_delay: float = 0.1, count: int = 1000, scope: str = OPENC3_SCOPE
) -> tuple[str, list[dict[str, Any]]]:
    """Return the packets received since the last call, using an ID from `subscribe_packets`.

    Packets are ordered within each subscribed packet stream (target/packet pair)
    but are NOT interleaved by time across streams. If chronological order across
    streams is required, sort the returned list by the 'time' field.

    Args:
        id: ID returned from `subscribe_packets` or the last call to get_packets.
        block: Seconds to keep polling while no packets are received. If not
            given, return after a single poll.
        block_delay: Seconds to sleep between polls.
        count: Maximum number of packets to return from EACH packet stream.
        scope: COSMOS scope.

    Returns:
        The ID to pass to the next call, and the decommutated packets found.
    """
    start_time = time.time()
    while True:
        id, packets = openc3.script.API_SERVER.get_packets(id, count=count, scope=scope)
        if block and time.time() < (start_time + block) and not packets:
            openc3_script_sleep(block_delay)
        else:
            break
    return id, packets


# inject_tlm, set_tlm, override_tlm, and normalize_tlm are implemented here simply to add a print
# these methods modify the telemetry so the user should be notified in the Script Runner log messages


def inject_tlm(
    target_name: str,
    packet_name: str,
    item_hash: dict[str, Any] | None = None,
    type: ValueType = "CONVERTED",
    stored: bool = False,
    scope: str = OPENC3_SCOPE,
    *,
    received_time: int | None = None,
) -> None:
    """Inject a packet into the system as if it was received from an interface.

    Items not in item_hash keep their current value from the current value table.
    The call is printed so it shows in the Script Runner log messages.

    Args:
        target_name: Target name of the packet.
        packet_name: Packet name. LATEST is not supported.
        item_hash: Item names mapped to the values to change.
        type: Value type of the item_hash values: RAW, CONVERTED (default) or FORMATTED.
        stored: Whether to flag the packet as stored (historical) telemetry.
        scope: COSMOS scope.
        received_time: Received time in nanoseconds since the Unix epoch. Defaults to now.
    """
    message = f'inject_tlm("{target_name}", "{packet_name}", {item_hash}, type="{type}", stored={stored}'
    kwargs = {"type": type, "stored": stored, "scope": scope}
    if received_time is not None:
        message += f", received_time={received_time}"
        kwargs["received_time"] = received_time
    print(f"{message})")
    openc3.script.API_SERVER.inject_tlm(target_name, packet_name, item_hash, **kwargs)


def set_tlm(*args: Any, type: OverrideValueType = "CONVERTED", scope: str = OPENC3_SCOPE) -> None:
    """Set a telemetry item in the current value table.

    If COSMOS is receiving telemetry for the packet, the next packet can
    overwrite this value at any time. This is best used for testing or for
    items which are not received regularly through the target interface.
    The call is printed so it shows in the Script Runner log messages.

    Accepts two calling styles. Favor the first as it is more succinct::

        set_tlm("TGT PKT ITEM = 1.0")
        set_tlm("TGT", "PKT", "ITEM", 10.0)

    Args:
        *args: A single "TGT PKT ITEM = value" string, or the target, packet
            and item names followed by the value.
        type: Value type to set: RAW, CONVERTED (default), FORMATTED, or ALL
            to set every value type.
        scope: COSMOS scope.
    """
    print(_format_call("set_tlm", args, type))
    openc3.script.API_SERVER.set_tlm(*args, type=type, scope=scope)


def override_tlm(*args: Any, type: OverrideValueType = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Override an item in the current value table so it always returns the same value.

    The override persists when new packets are received from the target.
    Call `normalize_tlm` to remove it. The call is printed so it shows in the
    Script Runner log messages.

    Accepts two calling styles. Favor the first as it is more succinct::

        override_tlm("TGT PKT ITEM = 1.0")
        override_tlm("TGT", "PKT", "ITEM", 10.0)

    A packet name of LATEST overrides the item in every packet which contains it.

    Args:
        *args: A single "TGT PKT ITEM = value" string, or the target, packet
            and item names followed by the value.
        type: Value type to override: ALL (default), RAW, CONVERTED or FORMATTED.
        scope: COSMOS scope.
    """
    print(_format_call("override_tlm", args, type))
    openc3.script.API_SERVER.override_tlm(*args, type=type, scope=scope)


def normalize_tlm(*args: str, type: OverrideValueType = "ALL", scope: str = OPENC3_SCOPE) -> None:
    """Remove an override set by `override_tlm` to restore normal telemetry processing.

    The call is printed so it shows in the Script Runner log messages.

    Accepts two calling styles. Favor the first as it is more succinct::

        normalize_tlm("TGT PKT ITEM")
        normalize_tlm("TGT", "PKT", "ITEM")

    A packet name of LATEST normalizes the item in every packet which contains it.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        type: Value type to normalize: ALL (default), RAW, CONVERTED or FORMATTED.
        scope: COSMOS scope.
    """
    print(_format_call("normalize_tlm", args, type))
    openc3.script.API_SERVER.normalize_tlm(*args, type=type, scope=scope)
