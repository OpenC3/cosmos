# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from datetime import datetime, timezone
from typing import Any

from openc3.api import WHITELIST
from openc3.api.tlm_api import _tlm_packet_names, _tlm_process_args, _tlm_process_args_all_packets
from openc3.environment import OPENC3_SCOPE
from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet_item import PacketItem
from openc3.topics.limits_event_topic import LimitsEventTopic
from openc3.utilities import limits_rollup
from openc3.utilities.authorization import authorize
from openc3.utilities.logger import Logger
from openc3.utilities.time import to_nsec_from_epoch


WHITELIST.extend(
    [
        "get_out_of_limits",
        "get_overall_limits_state",
        "limits_enabled",
        "enable_limits",
        "disable_limits",
        "get_limits",
        "set_limits",
        "set_state_color",
        "get_limits_groups",
        "enable_limits_group",
        "disable_limits_group",
        "get_limits_sets",
        "set_limits_set",
        "get_limits_set",
        "delete_limits_set",
        "get_limits_events",
    ]
)


def get_out_of_limits(scope: str = OPENC3_SCOPE) -> list[list[str]]:
    """Return all telemetry items which are currently out of limits.

    Args:
        scope: COSMOS scope.

    Returns:
        A [target_name, packet_name, item_name, limits_state] list for each
        item which is YELLOW or RED.
    """
    authorize(permission="tlm", scope=scope)
    return LimitsEventTopic.out_of_limits(scope=scope)


def get_overall_limits_state(ignored_items: list[Any] | None = None, scope: str = OPENC3_SCOPE) -> str:
    """Return the overall limits state, which is the worst state of all items.

    For example if any item is YELLOW_LOW or YELLOW_HIGH the overall state is
    YELLOW. If a single item then turns RED_HIGH the overall state is RED.

    Args:
        ignored_items: [TGT, PKT, ITEM] lists to ignore when determining the
            overall state. ITEM can be None to ignore the entire packet.
        scope: COSMOS scope.

    Returns:
        The overall limits state: GREEN, YELLOW or RED.

    Raises:
        RuntimeError: If an ignored item does not have exactly three elements.
    """
    # We only need to check out of limits items so call get_out_of_limits() which authorizes
    out_of_limits = get_out_of_limits(scope=scope)

    # Build easily matchable ignore list without modifying the caller's list
    ignored_keys = []
    if ignored_items is not None:
        for item in ignored_items:
            if len(item) != 3:
                raise RuntimeError(f"Invalid ignored item: {item}. Must be [TGT, PKT, ITEM] where ITEM can be None.")
            ignored_keys.append(f"{item[0]}__{item[1]}__{item[2] or ''}")

    states = []
    for target_name, packet_name, item_name, limits_state in out_of_limits:
        # Ignore this item if we match one of the ignored items. A key ending in __
        # has no item so it matches every item in the packet, otherwise the item must
        # match exactly so ignoring TEMP1 does not also ignore TEMP10.
        full_name = f"{target_name}__{packet_name}__{item_name}"
        if any(full_name.startswith(key) if key.endswith("__") else full_name == key for key in ignored_keys):
            continue
        states.append(limits_state)
    overall = limits_rollup.worst(states)
    # The overall state has never been BLUE
    return "GREEN" if overall is None or overall == "BLUE" else overall


def limits_enabled(*args: str, scope: str = OPENC3_SCOPE) -> bool:
    """Return whether limits checking is enabled for a telemetry item.

    Accepts two calling styles. Favor the first as it is more succinct::

        limits_enabled("TGT PKT ITEM")
        limits_enabled("TGT", "PKT", "ITEM")

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        scope: COSMOS scope.

    Returns:
        True if limits checking is enabled for the item.
    """
    target_name, packet_name, item_name = _tlm_process_args(args, "limits_enabled", scope=scope)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    item = TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    return bool(item["limits"].get("enabled"))


def enable_limits(*args: str, scope: str = OPENC3_SCOPE) -> None:
    """Enable limits checking for a telemetry item.

    Accepts two calling styles. Favor the first as it is more succinct::

        enable_limits("TGT PKT ITEM")
        enable_limits("TGT", "PKT", "ITEM")

    A packet name of LATEST applies to every packet which contains the item.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        scope: COSMOS scope.
    """
    target_name, packet_names, item_name = _tlm_process_args_all_packets(args, "enable_limits", scope=scope)
    for packet_name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=packet_name, scope=scope)
    for packet_name in packet_names:
        _set_limits_enabled(target_name, packet_name, item_name, True, scope)


def disable_limits(*args: str, scope: str = OPENC3_SCOPE) -> None:
    """Disable limits checking for a telemetry item.

    Accepts two calling styles. Favor the first as it is more succinct::

        disable_limits("TGT PKT ITEM")
        disable_limits("TGT", "PKT", "ITEM")

    A packet name of LATEST applies to every packet which contains the item.

    Args:
        *args: A single "TGT PKT ITEM" string, or the target, packet and item names.
        scope: COSMOS scope.
    """
    target_name, packet_names, item_name = _tlm_process_args_all_packets(args, "disable_limits", scope=scope)
    for packet_name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=packet_name, scope=scope)
    for packet_name in packet_names:
        _set_limits_enabled(target_name, packet_name, item_name, False, scope)


def get_limits(target_name: str, packet_name: str, item_name: str, scope: str = OPENC3_SCOPE) -> dict[str, list[float]]:
    """Return all the limits sets defined for a telemetry item.

    Each value is a list of red low, yellow low, yellow high, red high and the
    optional green low and green high limits. For example::

        {"DEFAULT": [-80, -70, 60, 80, -20, 20], "TVAC": [-25, -10, 50, 55]}

    Args:
        target_name: Target name.
        packet_name: Packet name. LATEST reads the packet most recently
            received which contains the item.
        item_name: Item name.
        scope: COSMOS scope.

    Returns:
        Uppercase limits set names (there is always a DEFAULT) mapped to the limits.
    """
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    # Resolve LATEST before authorizing so the real packet is authorized
    if packet_name == "LATEST":
        packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, scope=scope)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    limits = {}
    item = TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    for key, vals in item["limits"].items():
        # Skip non-numeric limits such as SEQUENCE, CHANGE, or STATIC change limits
        if not isinstance(vals, dict) or "red_low" not in vals:
            continue

        limits[key] = [
            vals["red_low"],
            vals["yellow_low"],
            vals["yellow_high"],
            vals["red_high"],
        ]
        if vals.get("green_low") is not None:
            limits[key] += [vals["green_low"], vals["green_high"]]
    return limits


def set_limits(
    target_name: str,
    packet_name: str,
    item_name: str,
    red_low: float,
    yellow_low: float,
    yellow_high: float,
    red_high: float,
    green_low: float | None = None,
    green_high: float | None = None,
    limits_set: str = "CUSTOM",
    persistence: int | None = None,
    enabled: bool = True,
    scope: str = OPENC3_SCOPE,
) -> None:
    """Change the limits settings for a telemetry item.

    By default a new limits set called CUSTOM is created to avoid overriding
    existing limits. Every packet is validated before any is changed, so a
    validation error does not leave a partial update.

    Args:
        target_name: Target name.
        packet_name: Packet name. LATEST applies to every packet which
            contains the item.
        item_name: Item name.
        red_low: Red low limit.
        yellow_low: Yellow low limit.
        yellow_high: Yellow high limit.
        red_high: Red high limit.
        green_low: Optional green low limit. Requires green_high.
        green_high: Optional green high limit. Requires green_low.
        limits_set: Name of the limits set to change.
        persistence: Number of consecutive out of limits samples before the
            limits state changes. None leaves the current setting.
        enabled: Whether limits checking is enabled for the item.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the limits are not nested correctly, or the item does
            not exist or has no limits.
    """
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    packet_names = (
        _tlm_packet_names(target_name, packet_name, item_name, scope) if packet_name == "LATEST" else [packet_name]
    )
    for name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=name, scope=scope)
    if (red_low > yellow_low) or (yellow_low >= yellow_high) or (yellow_high > red_high):
        raise RuntimeError("Invalid limits specified. Ensure yellow limits are within red limits.")
    if (green_low is not None and green_high is not None) and (
        (yellow_low > green_low) or (green_low >= green_high) or (green_high > yellow_high)
    ):
        raise RuntimeError("Invalid limits specified. Ensure green limits are within yellow limits.")
    # Validate every packet before changing any so an error doesn't leave a partial update.
    # TargetModel.packet returns a cached dict so it must not be modified until validated.
    items = []
    for name in packet_names:
        packet = TargetModel.packet(target_name, name, scope=scope)
        item = next((packet_item for packet_item in packet["items"] if packet_item["name"] == item_name), None)
        if item is None:
            raise RuntimeError(f"Item '{target_name} {name} {item_name}' does not exist while setting limits")
        if not item["limits"]:
            raise RuntimeError("Cannot set_limits on item without any limits")
        default = item["limits"].get("DEFAULT")
        if isinstance(default, dict) and default.get("change_type"):
            raise RuntimeError(
                f"Cannot set_limits on item '{target_name} {name} {item_name}' with {default['change_type']} limits"
            )
        items.append((name, packet, item))
    for name, packet, item in items:
        if persistence:
            item["limits"]["persistence_setting"] = persistence
        if enabled:
            item["limits"]["enabled"] = True
        else:
            item["limits"].pop("enabled", None)
        limits = {}
        limits["red_low"] = red_low
        limits["yellow_low"] = yellow_low
        limits["yellow_high"] = yellow_high
        limits["red_high"] = red_high
        if green_low is not None and green_high is not None:
            limits["green_low"] = green_low
            limits["green_high"] = green_high
        item["limits"][limits_set] = limits

        message = (
            f"Setting '{target_name} {name} {item_name}' limits to {red_low} {yellow_low} {yellow_high} {red_high}"
        )
        if green_low is not None and green_high is not None:
            message += f" {green_low} {green_high}"
        message += f" in set {limits_set} with persistence {persistence} as enabled {enabled}"
        Logger.info(message, scope=scope)

        TargetModel.set_packet(target_name, name, packet, scope=scope)

        event = {
            "type": "LIMITS_SETTINGS",
            "target_name": target_name,
            "packet_name": name,
            "item_name": item_name,
            "red_low": red_low,
            "yellow_low": yellow_low,
            "yellow_high": yellow_high,
            "red_high": red_high,
            "green_low": green_low,
            "green_high": green_high,
            "limits_set": limits_set,
            "persistence": persistence,
            "enabled": enabled,
            "time_nsec": to_nsec_from_epoch(datetime.now(timezone.utc)),
            "message": message,
        }
        LimitsEventTopic.write(event, scope=scope)


def set_state_color(
    target_name: str, packet_name: str, item_name: str, state_name: str, color: str | None, scope: str = OPENC3_SCOPE
) -> None:
    """Change the color of a telemetry item state in realtime.

    Items with states use the state color (GREEN, YELLOW, RED) to determine
    their limits state rather than numeric limits. Setting a color also
    enables limits checking for the item.

    Args:
        target_name: Target name.
        packet_name: Packet name. LATEST applies to every packet which
            contains the item.
        item_name: Item name.
        state_name: Name of the state to change, e.g. CONNECTED.
        color: New color for the state: GREEN, YELLOW or RED. None clears the
            state color.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the color is invalid, or the item or state does not exist.
    """
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    packet_names = (
        _tlm_packet_names(target_name, packet_name, item_name, scope) if packet_name == "LATEST" else [packet_name]
    )
    for name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=name, scope=scope)
    state_name = str(state_name).upper()
    if color is not None:
        color = str(color).upper()
        if color not in PacketItem.VALID_STATE_COLORS:
            raise RuntimeError(
                f"Invalid state color '{color}'. Must be one of {', '.join(PacketItem.VALID_STATE_COLORS)}."
            )
    # Validate every packet before changing any so an error doesn't leave a partial update.
    # TargetModel.packet returns a cached dict so it must not be modified until validated.
    items = []
    for name in packet_names:
        packet = TargetModel.packet(target_name, name, scope=scope)
        item = next((packet_item for packet_item in packet["items"] if packet_item["name"] == item_name), None)
        if item is None:
            raise RuntimeError(f"Item '{target_name} {name} {item_name}' does not exist while setting state color")
        if not (item.get("states") and item["states"].get(state_name)):
            raise RuntimeError(f"State '{state_name}' does not exist for item '{target_name} {name} {item_name}'")
        items.append((name, packet, item))
    for name, packet, item in items:
        if color is None:
            # Clear the state color
            item["states"][state_name].pop("color", None)
        else:
            item["states"][state_name]["color"] = color
            # Defining a state color implies limits are enabled for the item
            if not item.get("limits"):
                item["limits"] = {}
            item["limits"]["enabled"] = True

        if color is None:
            message = f"Clearing '{target_name} {name} {item_name}' state {state_name} color"
        else:
            message = f"Setting '{target_name} {name} {item_name}' state {state_name} color to {color}"
        Logger.info(message, scope=scope)

        TargetModel.set_packet(target_name, name, packet, scope=scope)

        event = {
            "type": "LIMITS_STATE_COLOR",
            "target_name": target_name,
            "packet_name": name,
            "item_name": item_name,
            "state_name": state_name,
            "color": color,
            "time_nsec": to_nsec_from_epoch(datetime.now(timezone.utc)),
            "message": message,
        }
        LimitsEventTopic.write(event, scope=scope)


def get_limits_groups(target_name: str | None = None, scope: str = OPENC3_SCOPE) -> dict[str, list[list[str]]]:
    """Return limits groups and their members.

    A nested group is the member [TARGET, "LIMITS_GROUP", GROUP].

    With no target name the groups of every target are keyed by group name. A
    group name defined by more than one target is keyed TARGET__GROUP instead
    since the name alone doesn't identify the group.

    Args:
        target_name: Only return the groups defined by this target.
        scope: COSMOS scope.

    Returns:
        Group names mapped to the [target_name, packet_name, item_name] of
        each member.
    """
    # Like Ruby an empty target name is a target name, not an omitted one
    if target_name is not None:
        target_name = str(target_name).upper()
    authorize(permission="tlm", target_name=target_name, scope=scope)
    groups = []
    for key, items in TargetModel.limits_groups(scope=scope).items():
        group_target_name, group_name = LimitsEventTopic.split_limits_group_key(key)
        groups.append((key, group_target_name, group_name, items))
    if target_name is not None:
        return {
            group_name: items
            for _key, group_target_name, group_name, items in groups
            if group_target_name == target_name
        }
    counts = {}
    for group in groups:
        counts[group[2]] = counts.get(group[2], 0) + 1
    return {(key if counts[group_name] > 1 else group_name): items for key, _target, group_name, items in groups}


def enable_limits_group(*args: str, cascade: bool = True, scope: str = OPENC3_SCOPE) -> None:
    """Enable limits checking for all the items in a limits group.

    Accepts two calling styles::

        enable_limits_group("GROUP")
        enable_limits_group("TGT", "GROUP")

    A group name alone must only be defined by one target.

    Args:
        *args: The group name, or the target name and group name.
        cascade: Whether to also enable the nested groups and their items.
            When False only the group itself and the items directly in it
            are enabled.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the number of arguments is invalid or the group is
            undefined or ambiguous.
    """
    _limits_group(args, "enable_limits_group", action="enable", cascade=cascade, scope=scope)


def disable_limits_group(*args: str, cascade: bool = True, scope: str = OPENC3_SCOPE) -> None:
    """Disable limits checking for all the items in a limits group.

    Accepts two calling styles::

        disable_limits_group("GROUP")
        disable_limits_group("TGT", "GROUP")

    A group name alone must only be defined by one target.

    Args:
        *args: The group name, or the target name and group name.
        cascade: Whether to also disable the nested groups and their items.
            When False only the group itself and the items directly in it
            are disabled.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the number of arguments is invalid or the group is
            undefined or ambiguous.
    """
    _limits_group(args, "disable_limits_group", action="disable", cascade=cascade, scope=scope)


def get_limits_sets(scope: str = OPENC3_SCOPE) -> list[str]:
    """Return the names of all defined limits sets.

    Args:
        scope: COSMOS scope.

    Returns:
        Sorted limits set names.
    """
    authorize(permission="tlm", scope=scope)
    sets = list(LimitsEventTopic.sets(scope=scope).keys())
    sets.sort()
    return sets


def set_limits_set(limits_set: str, scope: str = OPENC3_SCOPE) -> None:
    """Change the active limits set that applies to all telemetry.

    Args:
        limits_set: Name of the limits set.
        scope: COSMOS scope.
    """
    authorize(permission="tlm_set", scope=scope)
    message = f"Setting Limits Set: {limits_set}"
    Logger.info(message, scope=scope)
    LimitsEventTopic.write(
        {
            "type": "LIMITS_SET",
            "set": str(limits_set),
            "time_nsec": to_nsec_from_epoch(datetime.now(timezone.utc)),
            "message": message,
        },
        scope=scope,
    )


def delete_limits_set(limits_set: str, scope: str = OPENC3_SCOPE) -> None:
    """Delete a limits set.

    The DEFAULT limits set and the active limits set cannot be deleted. Use
    `set_limits_set` to change the active set before deleting it. The limits
    set is not removed from the target packet definitions; that is cleaned up
    on the next plugin install.

    Args:
        limits_set: Name of the limits set to delete.
        scope: COSMOS scope.

    Raises:
        RuntimeError: If the set is DEFAULT, is the active set, or does not exist.
    """
    authorize(permission="tlm_set", scope=scope)
    limits_set = str(limits_set)
    if limits_set == "DEFAULT":
        raise RuntimeError("Cannot delete the DEFAULT limits set")
    if limits_set == LimitsEventTopic.current_set(scope=scope):
        raise RuntimeError(
            f"Cannot delete the current limits set '{limits_set}'. Use set_limits_set to change the current set first."
        )
    if limits_set not in LimitsEventTopic.sets(scope=scope):
        raise RuntimeError(f"Limits set '{limits_set}' does not exist")

    # Remove the limits set from Redis (limits_sets and current_limits_settings)
    LimitsEventTopic.delete_set(limits_set, scope=scope)

    message = f"Deleting Limits Set: {limits_set}"
    Logger.info(message, scope=scope)


def get_limits_set(scope: str = OPENC3_SCOPE) -> str:
    """Return the active limits set that applies to all telemetry.

    Args:
        scope: COSMOS scope.

    Returns:
        Name of the active limits set.
    """
    authorize(permission="tlm", scope=scope)
    return LimitsEventTopic.current_set(scope=scope)


def get_limits_events(offset: str | None = None, count: int = 100, scope: str = OPENC3_SCOPE) -> list[list[Any]]:
    """Return limits events starting at an offset.

    Args:
        offset: Offset to start reading events from, as returned by a previous
            call. None returns the last received event (if any).
        count: Maximum number of events to return.
        scope: COSMOS scope.

    Returns:
        An [offset, event] list for each event. Pass the last offset to the
        next call to continue where this call left off.
    """
    authorize(permission="tlm", scope=scope)
    return LimitsEventTopic.read(offset, count=count, scope=scope)


# Enables or disables a limits group
def _limits_group(args: tuple[str, ...], method_name: str, action: str, cascade: bool, scope: str):
    match len(args):
        case 1:
            target_name = None
            group_name = args[0]
        case 2:
            target_name, group_name = args
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    authorize(
        permission="tlm_set", target_name=str(target_name).upper() if target_name is not None else None, scope=scope
    )
    key = LimitsEventTopic.find_limits_group(target_name, group_name, scope)
    target_name, group_name = LimitsEventTopic.split_limits_group_key(key)
    # Items grouped by target and packet so each packet is read and written once
    cascade = bool(cascade)
    items = LimitsEventTopic.limits_group_items(key, scope, cascade)
    # Members can be items of other targets, directly or through nested groups,
    # so check every target before changing any of them
    for item_target_name in items:
        authorize(permission="tlm_set", target_name=item_target_name, scope=scope)

    enabled = action == "enable"
    message = f"{'Enabling' if enabled else 'Disabling'} Limits Group: {' '.join(name for name in (target_name, group_name) if name)}"
    if not cascade:
        message += " (not nested groups)"
    Logger.info(message, scope=scope)

    for item_target_name, packets in items.items():
        for packet_name, item_names in packets.items():
            packet = TargetModel.packet(item_target_name, packet_name, scope=scope)
            item_names_set = set(item_names)
            for item in packet["items"]:
                if item["name"] in item_names_set:
                    if enabled:
                        item["limits"]["enabled"] = True
                    else:
                        item["limits"].pop("enabled", None)
            TargetModel.set_packet(item_target_name, packet_name, packet, scope=scope)

    # Write a single event for the entire group. Writing one event per item
    # floods the limits event stream, which is trimmed to ~1000 entries, so
    # decom microservices could miss events and leave limits enabled.
    # The event only names the group (readers look up the items) so it stays
    # small no matter how many items the group contains.
    event = {
        "type": "LIMITS_GROUP_ENABLE_STATE",
        "group_name": group_name,
        "enabled": enabled,
        "time_nsec": to_nsec_from_epoch(datetime.now(timezone.utc)),
        "message": message,
    }
    # Groups stored before they were owned by a target have no target name
    if target_name:
        event["target_name"] = target_name
    # Readers expand nested groups unless the event says not to
    if not cascade:
        event["cascade"] = False
    LimitsEventTopic.write(event, scope=scope)


def _set_limits_enabled(target_name: str, packet_name: str, item_name: str, enabled: bool, scope: str):
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    item = next((packet_item for packet_item in packet["items"] if packet_item["name"] == item_name), None)
    if item is None:
        action = "enabling" if enabled else "disabling"
        raise RuntimeError(f"Item '{target_name} {packet_name} {item_name}' does not exist while {action} limits")

    if enabled:
        item["limits"]["enabled"] = True
    else:
        item["limits"].pop("enabled", None)
    TargetModel.set_packet(target_name, packet_name, packet, scope=scope)

    if enabled:
        message = f"Enabling Limits For '{target_name} {packet_name} {item_name}'"
    else:
        message = f"Disabling Limits for '{target_name} {packet_name} {item_name}'"
    Logger.info(message, scope=scope)

    event = {
        "type": "LIMITS_ENABLE_STATE",
        "target_name": target_name,
        "packet_name": packet_name,
        "item_name": item_name,
        "enabled": enabled,
        "time_nsec": to_nsec_from_epoch(datetime.now(timezone.utc)),
        "message": message,
    }
    LimitsEventTopic.write(event, scope=scope)
