# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from datetime import datetime, timezone
from openc3.api import WHITELIST
from openc3.api.tlm_api import _tlm_process_args
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.topics.limits_event_topic import LimitsEventTopic
from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel

# from openc3.utilities.extract import *
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
        "get_limits_groups",
        "enable_limits_group",
        "disable_limits_group",
        "get_limits_sets",
        "set_limits_set",
        "get_limits_set",
        "get_limits_events",
    ]
)


# Return an array of arrays indicating all items in the packet that are out of limits
#   [[target name, packet name, item name, item limits state], ...]
#
# @return [Array<Array<String, String, String, String>>]
def get_out_of_limits(scope=OPENC3_SCOPE):
    authorize(permission="tlm", scope=scope)
    return LimitsEventTopic.out_of_limits(scope=scope)


# Get the overall limits state which is the worse case of all limits items.
# For example if any limits are YELLOW_LOW or YELLOW_HIGH then the overall limits state is YELLOW.
# If a single limit item then turns RED_HIGH the overall limits state is RED.
#
# @param ignored_items [Array<Array<String, String, String|nil>>] Array of [TGT, PKT, ITEM] strings
#   to ignore when determining overall state. Note, ITEM can be nil to indicate to ignore entire packet.
# @return [String] The overall limits state for the system, one of 'GREEN', 'YELLOW', 'RED'
def get_overall_limits_state(ignored_items=None, scope=OPENC3_SCOPE):
    # We only need to check out of limits items so call get_out_of_limits() which authorizes
    out_of_limits = get_out_of_limits(scope=scope)
    overall = "GREEN"

    # Build easily matchable ignore list
    if ignored_items is not None:
        new_items = []
        for item in ignored_items:
            if len(item) != 3:
                raise RuntimeError(f"Invalid ignored item: {item}. Must be [TGT, PKT, ITEM] where ITEM can be None.")
            if item[2] is None:
                item[2] = ""
            new_items.append("__".join(item))
        ignored_items = new_items
    else:
        ignored_items = []

    for target_name, packet_name, item_name, limits_state in out_of_limits:
        # Ignore this item if we match one of the ignored items
        for item in ignored_items:
            if item in f"{target_name}__{packet_name}__{item_name}":
                break
        else:  # Executed if 'for item in ignored_items:' did NOT break
            if limits_state == "RED" or limits_state == "RED_HIGH" or limits_state == "RED_LOW":
                overall = limits_state
                break  # Red is as high as we go so no need to look for more

            # If our overall state is currently blue or green we can go to any state
            if overall in ["BLUE", "GREEN", "GREEN_HIGH", "GREEN_LOW"]:
                overall = limits_state
            # else YELLOW - Stay at YELLOW until we find a red

    if overall == "GREEN_HIGH" or overall == "GREEN_LOW" or overall == "BLUE":
        overall = "GREEN"
    if overall == "YELLOW_HIGH" or overall == "YELLOW_LOW":
        overall = "YELLOW"
    if overall == "RED_HIGH" or overall == "RED_LOW":
        overall = "RED"
    return overall


# Whether the limits are enabled for the given item
#
# Accepts two different calling styles:
#   limits_enabled("TGT PKT ITEM")
#   limits_enabled('TGT','PKT','ITEM')
#
# Favor the first syntax where possible as it is more succinct.
#
# @param args [String|Array<String>] See the description for calling style
# @return [Boolean] Whether limits are enable for the item
def limits_enabled(*args, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_process_args(args, "limits_enabled", scope=scope)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    item = TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    if item["limits"].get("enabled"):
        return True
    else:
        return False


# Enable limits checking for a telemetry item
#
# Accepts two different calling styles:
#   enable_limits("TGT PKT ITEM")
#   enable_limits('TGT','PKT','ITEM')
#
# Favor the first syntax where possible as it is more succinct.
#
# @param args [String|Array<String>] See the description for calling style
def enable_limits(*args, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_process_args(args, "enable_limits", scope=scope)
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    found_item = None
    for item in packet["items"]:
        if item["name"] == item_name:
            item["limits"]["enabled"] = True
            found_item = item
            break
    if found_item is None:
        raise RuntimeError(f"Item '{target_name} {packet_name} {item_name}' does not exist")

    TargetModel.set_packet(target_name, packet_name, packet, scope=scope)

    message = f"Enabling Limits For '{target_name} {packet_name} {item_name}'"
    Logger.info(message, scope=scope)

    event = {
        "type": "LIMITS_ENABLE_STATE",
        "target_name": target_name,
        "packet_name": packet_name,
        "item_name": item_name,
        "enabled": True,
        "time_nsec": to_nsec_from_epoch(datetime.now(timezone.utc)),
        "message": message,
    }
    LimitsEventTopic.write(event, scope=scope)


# Disable limit checking for a telemetry item
#
# Accepts two different calling styles:
#   disable_limits("TGT PKT ITEM")
#   disable_limits('TGT','PKT','ITEM')
#
# Favor the first syntax where possible as it is more succinct.
#
# @param args [String|Array<String>] See the description for calling style
def disable_limits(*args, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_process_args(args, "disable_limits", scope=scope)
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    found_item = None
    for item in packet["items"]:
        if item["name"] == item_name:
            item["limits"].pop("enabled", None)
            found_item = item
            break
    if found_item is None:
        raise RuntimeError(f"Item '{target_name} {packet_name} {item_name}' does not exist")

    TargetModel.set_packet(target_name, packet_name, packet, scope=scope)

    message = f"Disabling Limits for '{target_name} {packet_name} {item_name}'"
    Logger.info(message, scope=scope)

    event = {
        "type": "LIMITS_ENABLE_STATE",
        "target_name": target_name,
        "packet_name": packet_name,
        "item_name": item_name,
        "enabled": False,
        "time_nsec": to_nsec_from_epoch(datetime.now(timezone.utc)),
        "message": message,
    }
    LimitsEventTopic.write(event, scope=scope)


# Get a Hash of all the limits sets defined for an item. Hash keys are the limit
# set name in uppercase (note there is always a DEFAULT) and the value is an array
# of limit values: red low, yellow low, yellow high, red high, <green low, green high>.
# Green low and green high are optional.
#
# For example: {'DEFAULT' => [-80, -70, 60, 80, -20, 20],
#               'TVAC' => [-25, -10, 50, 55] }
#
# @return [Hash{String => Array<Number, Number, Number, Number, Number, Number>}]
def get_limits(target_name, packet_name, item_name, scope=OPENC3_SCOPE):
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    limits = {}
    item = _get_item(target_name, packet_name, item_name, scope=scope)
    for key, vals in item["limits"].items():
        if not isinstance(vals, dict):
            continue

        limits[key] = [
            vals["red_low"],
            vals["yellow_low"],
            vals["yellow_high"],
            vals["red_high"],
        ]
        if vals.get("green_low"):
            limits[key] += [vals["green_low"], vals["green_high"]]
    return limits


# Change the limits settings for a given item. By default, a new limits set called 'CUSTOM'
# is created to avoid overriding existing limits.
def set_limits(
    target_name,
    packet_name,
    item_name,
    red_low,
    yellow_low,
    yellow_high,
    red_high,
    green_low=None,
    green_high=None,
    limits_set="CUSTOM",
    persistence=None,
    enabled=True,
    scope=OPENC3_SCOPE,
):
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    if (red_low > yellow_low) or (yellow_low >= yellow_high) or (yellow_high > red_high):
        raise RuntimeError("Invalid limits specified. Ensure yellow limits are within red limits.")
    if (green_low and green_high) and (
        (yellow_low > green_low) or (green_low >= green_high) or (green_high > yellow_high)
    ):
        raise RuntimeError("Invalid limits specified. Ensure green limits are within yellow limits.")
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    found_item = None
    for item in packet["items"]:
        if item["name"] == item_name:
            if item["limits"]:
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
                if green_low and green_high:
                    limits["green_low"] = green_low
                if green_low and green_high:
                    limits["green_high"] = green_high
                item["limits"][limits_set] = limits
                found_item = item
                break
            else:
                raise RuntimeError("Cannot set_limits on item without any limits")
    if found_item is None:
        raise RuntimeError(f"Item '{target_name} {packet_name} {item_name}' does not exist")
    message = (
        f"Setting '{target_name} {packet_name} {item_name}' limits to {red_low} {yellow_low} {yellow_high} {red_high}"
    )
    if green_low and green_high:
        message += f" {green_low} {green_high}"
    message += f" in set {limits_set} with persistence {persistence} as enabled {enabled}"
    Logger.info(message, scope=scope)

    TargetModel.set_packet(target_name, packet_name, packet, scope=scope)

    event = {
        "type": "LIMITS_SETTINGS",
        "target_name": target_name,
        "packet_name": packet_name,
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


# Returns all limits_groups and their members
# @since 5.0.0 Returns hash with values
# @return [Hash{String => Array<Array<String, String, String>>]
def get_limits_groups(scope=OPENC3_SCOPE):
    authorize(permission="tlm", scope=scope)
    return TargetModel.limits_groups(scope=scope)


# Enables limits for all the items in the group
#
# @param group_name [String] Name of the group to enable
def enable_limits_group(group_name, scope=OPENC3_SCOPE):
    _limits_group(group_name, action="enable", scope=scope)


# Disables limits for all the items in the group
#
# @param group_name [String] Name of the group to disable
def disable_limits_group(group_name, scope=OPENC3_SCOPE):
    _limits_group(group_name, action="disable", scope=scope)


# Returns all defined limits sets
#
# @return [Array<String>] All defined limits sets
def get_limits_sets(scope=OPENC3_SCOPE):
    authorize(permission="tlm", scope=scope)
    sets = list(LimitsEventTopic.sets(scope=scope).keys())
    sets.sort()
    return sets


# Changes the active limits set that applies to all telemetry
#
# @param limits_set [String] The name of the limits set
def set_limits_set(limits_set, scope=OPENC3_SCOPE):
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


# Returns the active limits set that applies to all telemetry
#
# @return [String] The current limits set
def get_limits_set(scope=OPENC3_SCOPE):
    authorize(permission="tlm", scope=scope)
    return LimitsEventTopic.current_set(scope=scope)


# Returns limits events starting at the provided offset. Passing nil for an
# offset will return the last received limits event and associated offset.
#
# @param offset [Integer] Offset to start reading limits events. Nil to return
#   the last received limits event (if any).
# @param count [Integer] The total number of events returned. Default is 100.
# @return [Hash, Integer] Event hash followed by the offset. The offset can
#   be used in subsequent calls to return events from where the last call left off.
def get_limits_events(offset=None, count=100, scope=OPENC3_SCOPE):
    authorize(permission="tlm", scope=scope)
    return LimitsEventTopic.read(offset, count=count, scope=scope)


# Enables or disables a limits group
def _limits_group(group_name, action, scope):
    authorize(permission="tlm_set", scope=scope)
    group_name.upper()
    group = get_limits_groups(scope=scope).get(group_name)
    if group is None:
        raise RuntimeError(
            f"LIMITS_GROUP {group_name} undefined. Ensure your telemetry definition contains the line: LIMITS_GROUP {group_name}"
        )

    Logger.info(f"{action.capitalize()} Limits Group: {group_name}", scope=scope)
    last_target_name = None
    last_packet_name = None
    packet = None
    for target_name, packet_name, item_name in group:
        if last_target_name != target_name or last_packet_name != packet_name:
            if last_target_name and last_packet_name:
                TargetModel.set_packet(last_target_name, last_packet_name, packet, scope=scope)
            packet = TargetModel.packet(target_name, packet_name, scope=scope)
        for item in packet["items"]:
            if item["name"] == item_name:
                if action == "enable":
                    enabled = True
                    item["limits"]["enabled"] = True
                    message = f"Enabling Limits for '{target_name} {packet_name} {item_name}'"
                elif action == "disable":
                    enabled = False
                    item["limits"].pop("enabled", None)
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
                break
        last_target_name = target_name
        last_packet_name = packet_name
    if last_target_name and last_packet_name:
        TargetModel.set_packet(last_target_name, last_packet_name, packet, scope=scope)


# Gets an item. The code below is mostly duplicated from tlm_process_args in tlm_api.rb.
#
# @param target_name [String] target name
# @param packet_name [String] packet name
# @param item_name [String] item name
# @param scope [String] scope
# @return Hash The requested item based on the packet name
def _get_item(target_name, packet_name, item_name, cache_timeout=0.1, scope=OPENC3_SCOPE):
    # Determine if this item exists, it will raise appropriate errors if not
    if packet_name == "LATEST":
        packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout, scope)
    return TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
