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

# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

import contextlib
import json

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.models.cvt_model import CvtModel
from openc3.models.interface_model import InterfaceModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet
from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.topic import Topic
from openc3.utilities.authorization import authorize
from openc3.utilities.extract import (
    extract_fields_from_set_tlm_text,
    extract_fields_from_tlm_text,
)
from openc3.utilities.questdb_client import TlmItem
from openc3.utilities.store import Store


WHITELIST.extend(
    [
        "tlm",
        "tlm_raw",
        "tlm_formatted",
        "tlm_with_units",  # DEPRECATED
        "set_tlm",
        "inject_tlm",
        "override_tlm",
        "get_overrides",
        "normalize_tlm",
        "get_tlm_buffer",
        "get_tlm_packet",
        "get_tlm_available",
        "get_tlm_values",
        "get_all_tlm",
        "get_all_telemetry",  # DEPRECATED
        "get_all_tlm_names",
        "get_all_telemetry_names",  # DEPRECATED
        "get_all_tlm_item_names",
        "get_tlm",
        "get_telemetry",  # DEPRECATED
        "get_item",
        "subscribe_packets",
        "get_packets",
        "get_tlm_cnt",
        "get_tlm_cnts",
        "get_packet_derived_items",
    ]
)


# Request a telemetry item from a packet.
#
# Accepts two different calling styles:
#   tlm("TGT PKT ITEM")
#   tlm('TGT','PKT','ITEM')
#
# Favor the first syntax where possible as it is more succinct.
#
# @param args [String|Array<String>] See the description for calling style
# @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED
# @return [Object] The telemetry value formatted as requested
def tlm(*args, type="CONVERTED", cache_timeout=0.1, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_process_args(args, "tlm", cache_timeout=cache_timeout, scope=scope)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    return CvtModel.get_item(target_name, packet_name, item_name, type, cache_timeout, scope)


def tlm_raw(*args, cache_timeout=0.1, scope=OPENC3_SCOPE):
    return tlm(*args, type="RAW", cache_timeout=cache_timeout, scope=scope)


def tlm_formatted(*args, cache_timeout=0.1, scope=OPENC3_SCOPE):
    return tlm(*args, type="FORMATTED", cache_timeout=cache_timeout, scope=scope)


# DEPRECATED
def tlm_with_units(*args, cache_timeout=0.1, scope=OPENC3_SCOPE):
    return tlm(*args, type="FORMATTED", cache_timeout=cache_timeout, scope=scope)


# Set a telemetry item in the current value table.
#
# Note: If this is done while OpenC3 is currently receiving telemetry,
# this value could get overwritten at any time. Thus this capability is
# best used for testing or for telemetry items that are not received
# regularly through the target interface.
#
# Accepts two different calling styles:
#   set_tlm("TGT PKT ITEM = 1.0")
#   set_tlm('TGT','PKT','ITEM', 10.0)
#
# Favor the first syntax where possible as it is more succinct.
#
# @param args [String|Array<String>] See the description for calling style
# @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED
def set_tlm(*args, type="CONVERTED", cache_timeout=0.1, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name, value = _set_tlm_process_args(
        args, "set_tlm", cache_timeout=cache_timeout, scope=scope
    )
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    CvtModel.set_item(target_name, packet_name, item_name, value, type, scope)


# Injects a packet into the system as if it was received from an interface
#
# @param target_name [String] Target name of the packet
# @param packet_name [String] Packet name of the packet
# @param item_hash [Hash] Hash of item_name and value for each item you want to change from the current value table
# @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED
# @param received_time [Integer|None] Optional received time as nanoseconds since Unix epoch
def inject_tlm(
    target_name,
    packet_name,
    item_hash=None,
    type="CONVERTED",
    stored=False,
    scope=OPENC3_SCOPE,
    received_time=None,
):
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    if type not in CvtModel.VALUE_TYPES:
        raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name} (inject_tlm)")

    if item_hash:
        item_hash = {k.upper(): v for k, v in item_hash.items()}
        # Check that the items exist ... exceptions are raised if not
        items = TargetModel.packet_items(target_name, packet_name, item_hash.keys(), scope=scope)
        if type == "CONVERTED":
            # If the type is converted, check that the item states are valid
            for item_name, item_value in item_hash.items():
                item = next((i for i in items if i["name"] == item_name.upper()), None)
                if item and item.get("states") and item_value not in item["states"]:
                    raise RuntimeError(
                        f"Unknown state '{item_value}' for {item['name']}, must be one of {', '.join(item['states'].keys())}"
                    )
    else:
        # Check that the packet exists ... exceptions are raised if not
        TargetModel.packet(target_name, packet_name, scope=scope)

    # See if this target has a tlm interface
    interface_name = None
    for _, interface in InterfaceModel.all(scope).items():
        if target_name in interface["tlm_target_names"]:
            interface_name = interface["name"]
            break

    # Use an interface microservice if it exists, other use the decom microservice
    if interface_name:
        InterfaceTopic.inject_tlm(
            interface_name,
            target_name,
            packet_name,
            item_hash,
            type=type,
            stored=stored,
            scope=scope,
            received_time=received_time,
        )
    else:
        DecomInterfaceTopic.inject_tlm(
            target_name,
            packet_name,
            item_hash,
            type=type,
            stored=stored,
            scope=scope,
            received_time=received_time,
        )


# Override the current value table such that a particular item always
# returns the same value (for a given type) even when new telemetry
# packets are received from the target.
#
# Accepts two different calling styles:
#   override_tlm("TGT PKT ITEM = 1.0")
#   override_tlm('TGT','PKT','ITEM', 10.0)
#
# Favor the first syntax where possible as it is more succinct.
#
# @param args The args must either be a string followed by a value or
#   three strings followed by a value (see the calling style in the
#   description). A packet name of LATEST overrides the item in every
#   packet which contains it.
# @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED
def override_tlm(*args, type="ALL", scope=OPENC3_SCOPE):
    target_name, packet_names, item_name, value = _set_tlm_process_args_all_packets(args, "override_tlm", scope=scope)
    for packet_name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=packet_name, scope=scope)
    for packet_name in packet_names:
        CvtModel.override(target_name, packet_name, item_name, value, type=type, scope=scope)


# Get the list of CVT overrides
def get_overrides(scope=OPENC3_SCOPE):
    authorize(permission="tlm", scope=scope)
    return CvtModel.overrides(scope=scope)


# Normalize a telemetry item in a packet to its default behavior. Called
# after override_tlm to restore standard processing.
#
# Accepts two different calling styles:
#   normalize_tlm("TGT PKT ITEM")
#   normalize_tlm('TGT','PKT','ITEM')
#
# Favor the first syntax where possible as it is more succinct.
#
# @param args The args must either be a string or three strings
#   (see the calling style in the description). A packet name of LATEST
#   normalizes the item in every packet which contains it.
# @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED
#   Also takes :ALL which means to normalize all telemetry types
def normalize_tlm(*args, type="ALL", scope=OPENC3_SCOPE):
    target_name, packet_names, item_name = _tlm_process_args_all_packets(args, "normalize_tlm", scope=scope)
    for packet_name in packet_names:
        authorize(permission="tlm_set", target_name=target_name, packet_name=packet_name, scope=scope)
    for packet_name in packet_names:
        CvtModel.normalize(target_name, packet_name, item_name, type=type, scope=scope)


# Returns the raw buffer for a telemetry packet.
#
# @param target_name [String] Name of the target
# @param packet_name [String] Name of the packet
# @return [Hash] telemetry hash with last telemetry buffer
def get_tlm_buffer(*args, scope=OPENC3_SCOPE, timeout=5):
    target_name, packet_name = _extract_target_packet_names("get_tlm_buffer", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    model = TargetModel.packet(target_name, packet_name, scope=scope)
    if model.get("subpacket"):
        msg_hash = DecomInterfaceTopic.get_tlm_buffer(target_name, packet_name, timeout=timeout, scope=scope)
        return {k.decode(): v for (k, v) in msg_hash.items()}
    else:
        topic = f"{scope}__TELEMETRY__{{{target_name}}}__{packet_name}"
        db_shard = Store.db_shard_for_target(target_name, scope=scope)
        msg_id, msg_hash = Topic.get_newest_message(topic, db_shard=db_shard)
        if msg_id:
            # Decode the keys for user convenience
            return {k.decode(): v for (k, v) in msg_hash.items()}
    return None


def get_tlm_packet(*args, stale_time: int = 30, type: str = "CONVERTED", scope: str = OPENC3_SCOPE):
    """Returns all the values (along with their limits state) for a packet.

    Args:
        target_name (str) Name of the target
        packet_name (str) Name of the packet
        stale_time (int) Time in seconds from Time.now that packet will be marked stale
        type (str) Types returned, :RAW, :CONVERTED (default), :FORMATTED

    Return:
        (List[String, Object, Symbol|None]) Returns an Array consisting of
        [item name, item value, item limits state] where the item limits state
        can be one of {OpenC3::Limits::LIMITS_STATES}
    """
    target_name, packet_name = _extract_target_packet_names("get_tlm_packet", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    t = _validate_tlm_type(type)
    if t is None:
        raise TypeError(f"Unknown type '{type}' for {target_name} {packet_name} (get_tlm_packet)")
    cvt_items = []
    for item in packet["items"]:
        if not item.get("hidden", False):
            cvt_items.append(item)
    cvt_items = [TlmItem(target_name, packet_name, item["name"].upper(), type) for item in cvt_items]
    # This returns an array of arrays containing the value and the limits state:
    # [[0, None], [0, 'RED_LOW'], ... ]
    current_values = CvtModel.get_tlm_values(cvt_items, stale_time=stale_time, scope=scope)
    return [[cvt_items[index].item_name, item[0], item[1]] for index, item in enumerate(current_values)]


def get_tlm_available(items, manual=False, scope=OPENC3_SCOPE):
    """Returns available telemetry items with proper type conversion based on item configuration.

    Args:
        items: List of items formatted as TGT__PKT__ITEM__TYPE
        manual: Whether this is a manual request (unused in Python version)
        scope: Scope to use for the request

    Returns:
        List of available items with proper type suffixes, or None for unavailable items
    """
    results = []
    for item in items:
        item_upcase = str(item).upper()
        try:
            target_name, orig_packet_name, item_name, value_type = item_upcase.split("__")
        except ValueError:
            raise ValueError("items must be formatted as TGT__PKT__ITEM__TYPE") from None

        packet_name = orig_packet_name
        if orig_packet_name == "LATEST":
            # A LATEST item can come from any packet containing it. Report the best value
            # type and limits of any of them since the CVT falls back to the available
            # type and historical lookups check the type available in each packet.
            # We can have a large cache_timeout of 1 because all we're trying to do is lookup a packet
            packet_name = CvtModel.determine_latest_packet_for_item(
                target_name, item_name, cache_timeout=1, scope=scope
            )
            packet_names = _tlm_packet_names(target_name, orig_packet_name, item_name, scope)
        else:
            packet_names = [packet_name]

        authorize(
            permission="tlm",
            target_name=target_name,
            packet_name=packet_name,
            scope=scope,
        )

        try:
            item_configs = [TargetModel.packet_item(target_name, name, item_name, scope=scope) for name in packet_names]
            available_type = max(
                (_tlm_available_value_type(item_config, item_name, value_type) for item_config in item_configs),
                key=VALUE_TYPE_ORDER.index,
            )
            result_item = "__".join([target_name, orig_packet_name, item_name, available_type])

            # Tack on __LIMITS to notify that we have an available limits value
            if any(item_config.get("limits", {}).get("DEFAULT") for item_config in item_configs):
                result_item += "__LIMITS"

            results.append(result_item)
        except Exception:
            results.append(None)

    return results


# Returns all the item values (along with their limits state). The items
# can be from any target and packet and thus must be fully qualified with
# their target and packet names.
#
# @param items [Array<String>] Array of items consisting of 'tgt__pkt__item__type'
# @param stale_time [Integer] Time in seconds from Time.now that data will be marked stale
# @return [Array<Object, Symbol>]
#   Array consisting of the item value and limits state
#   given as symbols such as :RED, :YELLOW, :STALE
def get_tlm_values(
    items,
    stale_time=30,
    cache_timeout=0.1,
    start_time=None,
    end_time=None,
    scope=OPENC3_SCOPE,
):
    if not isinstance(items, list) or len(items) == 0:
        raise TypeError("items must be array of strings: ['TGT__PKT__ITEM__TYPE', ...]")
    packets = []
    cvt_items = []
    # Index of each historical LATEST item in cvt_items => every packet containing the item
    latest_candidates = {}
    for item in items:
        # get_tlm_available returns None for items which don't exist and its result is
        # passed directly here, so None is a placeholder which returns a None value
        if item is None:
            cvt_items.append(TlmItem(None, None, None, None, None))
            continue
        if not isinstance(item, str):
            raise TypeError("items must be array of strings: ['TGT__PKT__ITEM__TYPE', ...]")
        # get_tlm_available tacks on __LIMITS to indicate a limits value is available
        # so accept both TGT__PKT__ITEM__TYPE and TGT__PKT__ITEM__TYPE__LIMITS
        parts = item.upper().split("__")
        if len(parts) < 4 or len(parts) > 5:
            raise ValueError("items must be formatted as TGT__PKT__ITEM__TYPE")
        target_name, packet_name, item_name, value_type = parts[0:4]
        limits = parts[4] if len(parts) == 5 else None
        if packet_name == "LATEST":
            if start_time is not None:
                # The packet received most recently now isn't necessarily the one received most
                # recently at start_time so keep every candidate packet for _tlm_latest_history
                # Each packet must be queried for the value type and limits it has or the query fails
                candidates = []
                for candidate in _tlm_packet_names(target_name, packet_name, item_name, scope):
                    packets.append([target_name, candidate])
                    candidate_item = TargetModel.packet_item(target_name, candidate, item_name, scope=scope)
                    candidate_limits = limits if limits and candidate_item.get("limits", {}).get("DEFAULT") else None
                    candidate_type = _tlm_available_value_type(candidate_item, item_name, value_type)
                    candidates.append(TlmItem(target_name, candidate, item_name, candidate_type, candidate_limits))
                latest_candidates[len(cvt_items)] = candidates
                cvt_items.append(TlmItem(target_name, packet_name, item_name, value_type, limits))
                continue
            packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout, scope)
        # NOTE: limits is required by the historical (start_time) QuestDB lookup
        cvt_items.append(TlmItem(target_name, packet_name, item_name, value_type, limits))
        packets.append([target_name, packet_name])
    # Make the array of arrays unique
    packets = [list(x) for x in {tuple(x) for x in packets}]
    for name in packets:
        authorize(
            permission="tlm",
            target_name=name[0],
            packet_name=name[1],
            scope=scope,
        )
    if latest_candidates:
        return _tlm_latest_history(cvt_items, latest_candidates, start_time, end_time, cache_timeout, scope)
    return CvtModel.get_tlm_values(cvt_items, stale_time, cache_timeout, start_time, end_time, scope)


# Returns an array of all the telemetry packet hashes
#
# @param target_name [String] Name of the target
# @return [Array<Hash>] Array of all telemetry packet hashes
def get_all_tlm(target_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    authorize(permission="tlm", target_name=target_name, scope=scope)
    return TargetModel.packets(target_name, type="TLM", scope=scope)


# get_all_telemetry is DEPRECATED
get_all_telemetry = get_all_tlm


def get_all_tlm_names(target_name: str, hidden: bool = False, scope: str = OPENC3_SCOPE):
    """Returns an array of all the telemetry packet names

    Args:
        target_name [] Name of the target

    Return:
        List[str] Array of all telemetry packet names
    """
    try:
        packets = get_all_tlm(target_name, scope=scope)
    except Exception:
        packets = []
    names = []
    for packet in packets:
        if hidden:
            names.append(packet["packet_name"])
        else:
            if "hidden" not in packet:
                names.append(packet["packet_name"])
    return names


def get_all_tlm_item_names(target_name: str, hidden: bool = False, scope: str = OPENC3_SCOPE):
    """Returns an array of all the item names for every packet in a target

    Args:
        target_name (str) Name of the target

    Return:
        List[str] Array of all telemetry item names
    """
    authorize(permission="tlm", target_name=target_name, scope=scope)
    try:
        items = TargetModel.all_item_names(target_name, scope=scope)
    except Exception:
        items = []
    return items


# get_all_telemetry_names is DEPRECATED
get_all_telemetry_names = get_all_tlm_names


def get_tlm(*args, scope: str = OPENC3_SCOPE):
    """Returns a telemetry packet hash

    Args:
        scope (str) Name of the scope

    Return:
        (dict) Telemetry packet hash
    """
    target_name, packet_name = _extract_target_packet_names("get_tlm", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    return TargetModel.packet(target_name, packet_name, scope=scope)


# get_telemetry is DEPRECATED
get_telemetry = get_tlm


def get_item(*args, scope: str = OPENC3_SCOPE, cache_timeout=0.1):
    """Returns a telemetry packet item hash

    Args:
        scope (str) Name of the scope

    Return:
        (dict) Telemetry packet hash
    """
    target_name, packet_name, item_name = _extract_target_packet_item_names("get_item", *args)
    if packet_name == "LATEST":
        packet_name = CvtModel.determine_latest_packet_for_item(
            target_name, item_name, cache_timeout=cache_timeout, scope=scope
        )
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    return TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)


# 2x double underscore since __ is reserved
SUBSCRIPTION_DELIMITER = "____"


def subscribe_packets(packets, scope=OPENC3_SCOPE):
    """Subscribe to a list of packets. An ID is returned which is passed to get_packets(id) to return packets.

    Args:
        packets (List[List[str]]) List of consisting of target name, packet name
        scope (str) Name of the scope

    Return:
        (str) ID which should be passed to get_packets
    """
    if not isinstance(packets, list) or not isinstance(packets[0], list):
        raise RuntimeError("packets must be nested array: [['TGT','PKT'],...]")

    result = {}
    for target_name, packet_name in packets:
        target_name = target_name.upper()
        packet_name = packet_name.upper()
        authorize(
            permission="tlm",
            target_name=target_name,
            packet_name=packet_name,
            scope=scope,
        )
        topic = f"{scope}__DECOM__{{{target_name}}}__{packet_name}"
        db_shard = Store.db_shard_for_target(target_name, scope=scope)
        id_, _ = Topic.get_newest_message(topic, db_shard=db_shard)
        result[topic] = id_ if id_ else "0-0"

    mylist = []
    for k, v in result.items():
        mylist += [k, v]
    return SUBSCRIPTION_DELIMITER.join(mylist)


def get_packets(id, count=1000, scope=OPENC3_SCOPE):
    """Get packets based on ID returned from subscribe_packet.

    Packets are ordered within each subscribed packet stream (target/packet pair)
    but are NOT interleaved by time across streams. If chronological order across
    streams is required, sort the returned list by the 'time' field. Sorting only
    orders the current batch - packets across separate get_packets calls may still
    arrive out of order, so subscribers needing global ordering must buffer and merge
    across calls.

    Args:
        id (str) ID returned from subscribe_packets or last call to get_packets
        count (int) Maximum number of packets to return from EACH packet stream
        scope ()

    Return:
        [Array<String, Array<Hash>] Array of the ID and array of all packets found
    """
    authorize(permission="tlm", scope=scope)
    # Split the list of topic, ID values and turn it into a hash for easy updates
    items = id.split(SUBSCRIPTION_DELIMITER)
    # Convert it back into a dict to create a lookup
    lookup = dict(zip(items[::2], items[1::2], strict=False))
    packets = []
    # Group topics by db_shard for multi-db_shard support
    import re

    db_shard_groups = {}
    for topic, offset in lookup.items():
        match = re.search(r"__\{?([^}_]+)\}?__", topic)
        target_name = match.group(1) if match else None
        db_shard = Store.db_shard_for_target(target_name, scope=scope)
        if db_shard not in db_shard_groups:
            db_shard_groups[db_shard] = {"topics": [], "offsets": []}
        db_shard_groups[db_shard]["topics"].append(topic)
        db_shard_groups[db_shard]["offsets"].append(offset)
    for db_shard, group in db_shard_groups.items():
        for topic, topic_id, msg_hash, _ in Topic.read_topics(
            group["topics"], group["offsets"], None, count, db_shard=db_shard
        ):
            lookup[topic] = topic_id  # save the new ID
            # decode the binary string keys and values to strings
            msg_hash = {k.decode(): v.decode() for (k, v) in msg_hash.items()}
            json_hash = json.loads(msg_hash["json_data"])
            msg_hash.pop("json_data")
            packets.append(msg_hash | json_hash)
    mylist = []
    for k, v in lookup.items():
        mylist += [k, v]
    return (SUBSCRIPTION_DELIMITER.join(mylist), packets)


def get_tlm_cnt(*args, scope: str = OPENC3_SCOPE):
    """Get the receive count for a telemetry packet

    Args:
        args (*args) target_name, packet_name (str) Packet name
        scope (str) Name of the scope

    Return:
        [Numeric] Receive count for the telemetry packet
    """
    target_name, packet_name = _extract_target_packet_names("get_tlm_cnt", *args)
    authorize(
        permission="system",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    TargetModel.packet(target_name, packet_name, scope=scope)
    return TargetModel.get_telemetry_count(target_name, packet_name, scope=scope)


def get_tlm_cnts(target_packets, scope=OPENC3_SCOPE):
    """Get the transmit counts for telemetry packets

    Args:
        target_packets [Array<Array<String, String>>] Array of arrays containing target_name, packet_name

    Return:
        [Numeric] Transmit count for the command
    """
    authorize(permission="system", scope=scope)
    return TargetModel.get_telemetry_counts(target_packets, scope=scope)


def get_packet_derived_items(*args, scope=OPENC3_SCOPE):
    """Get the list of derived telemetry items for a packet

    Args:
        args (*args) target_name, packet_name (str) Packet name
        scope (str)

    Return:
        # @return [Array<String>] All the ignored telemetry items for a packet.
    """
    target_name, packet_name = _extract_target_packet_names("get_packet_derived_items", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    return [item["name"] for item in packet["items"] if item["data_type"] == "DERIVED"]


def _extract_target_packet_names(method_name, *args):
    target_name = None
    packet_name = None
    match len(args):
        case 1:
            with contextlib.suppress(ValueError):
                # We get ValueError if passing not enough parameters
                # The check below for None handles this case
                target_name, packet_name = args[0].upper().split()
        case 2:
            target_name = args[0].upper()
            packet_name = args[1].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or packet_name is None:
        raise RuntimeError(
            f'ERROR: Both target name and packet name required. Usage: {method_name}("TGT PKT") or {method_name}("TGT", "PKT")'
        )
    # LATEST picks a packet per item so it can't identify a whole packet
    if packet_name == "LATEST":
        raise RuntimeError(f"ERROR: LATEST is not supported by {method_name}(), specify a packet name")
    return target_name, packet_name


def _extract_target_packet_item_names(method_name, *args):
    target_name = None
    packet_name = None
    item_name = None
    match len(args):
        case 1:
            with contextlib.suppress(ValueError):
                # Thrown when not enough items given
                target_name, packet_name, item_name = args[0].upper().split()
        case 3:
            target_name = args[0].upper()
            packet_name = args[1].upper()
            item_name = args[2].upper()
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    if target_name is None or packet_name is None or item_name is None:
        raise RuntimeError(
            f'ERROR: Target name, packet name and item name required. Usage: {method_name}("TGT PKT ITEM") or {method_name}("TGT", "PKT", "ITEM")'
        )
    return target_name, packet_name, item_name


def _validate_tlm_type(tlm_type):
    match tlm_type:
        case "RAW":
            return ""
        case "CONVERTED":
            return "C"
        case "FORMATTED" | "WITH_UNITS":
            return "F"
    return None


def _tlm_process_args(args, method_name, cache_timeout=0.1, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_extract_args(args, method_name)
    packet_name = _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout, scope)
    return target_name, packet_name, item_name


def _set_tlm_process_args(args, method_name, cache_timeout=0.1, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name, value = _set_tlm_extract_args(args, method_name)
    packet_name = _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout, scope)
    return target_name, packet_name, item_name, value


# Like _tlm_process_args but returns a list of packet names where LATEST
# expands to every packet containing the item. Used by APIs which change
# an item so the change applies wherever the item appears.
def _tlm_process_args_all_packets(args, method_name, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_extract_args(args, method_name)
    return target_name, _tlm_packet_names(target_name, packet_name, item_name, scope), item_name


def _set_tlm_process_args_all_packets(args, method_name, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name, value = _set_tlm_extract_args(args, method_name)
    return target_name, _tlm_packet_names(target_name, packet_name, item_name, scope), item_name, value


def _tlm_extract_args(args, method_name):
    match len(args):
        case 1:
            target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        case 3:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    return target_name.upper(), packet_name.upper(), item_name.upper()


def _set_tlm_extract_args(args, method_name):
    match len(args):
        case 1:
            target_name, packet_name, item_name, value = extract_fields_from_set_tlm_text(args[0])
        case 4:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            value = args[3]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    return target_name.upper(), packet_name.upper(), item_name.upper(), value


# Resolve LATEST to the most recently received packet containing the item
def _tlm_resolve_packet_name(target_name, packet_name, item_name, cache_timeout=0.1, scope=OPENC3_SCOPE):
    if packet_name == "LATEST":
        return CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout, scope)
    # Determine if this item exists, it will raise appropriate errors if not
    TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    return packet_name


VALUE_TYPE_ORDER = ["RAW", "CONVERTED", "FORMATTED"]


# Returns the value type available for an item given the requested value type
def _tlm_available_value_type(item_config, item_name, value_type):
    # Must request the raw value when dealing with the reserved items
    if item_name in Packet.RESERVED_ITEM_NAMES:
        return "RAW"
    # Arrays must be accessed as RAW since there's no conversion
    if item_config.get("array_size") is not None:
        return "RAW"
    converted = item_config.get("read_conversion") or item_config.get("states")
    if value_type == "FORMATTED" or value_type == "WITH_UNITS":
        if item_config.get("format_string") or item_config.get("units"):
            return "FORMATTED"
        return "CONVERTED" if converted else "RAW"
    if value_type == "CONVERTED":
        return "CONVERTED" if converted else "RAW"
    return "RAW"  # RAW or unknown


# Historical lookup where some items are LATEST. latest_candidates maps the index
# of each LATEST item in cvt_items to the item to look up in every packet which contains it.
def _tlm_latest_history(cvt_items, latest_candidates, start_time, end_time, cache_timeout, scope):
    regular = [index for index in range(len(cvt_items)) if index not in latest_candidates]

    if end_time is not None:
        # The QuestDB lookup ASOF JOINs every packet to the rows of the first, so
        # a range needs a regular item first to drive the rows. Without one keep
        # the realtime behavior of using the packet received most recently now.
        if all(cvt_items[index].item_name is None for index in regular):
            resolved = []
            for cvt_item in cvt_items:
                if cvt_item.packet_name == "LATEST":
                    packet_name = CvtModel.determine_latest_packet_for_item(
                        cvt_item.target_name, cvt_item.item_name, cache_timeout, scope
                    )
                    cvt_item = cvt_item._replace(packet_name=packet_name)
                resolved.append(cvt_item)
            return CvtModel.tsdb_lookup(resolved, start_time=start_time, end_time=end_time, scope=scope)

        query = []
        query_index = {}

        def add(query_item):
            if query_item not in query_index:
                query_index[query_item] = len(query)
                query.append(query_item)
            return query_index[query_item]

        positions = [None] * len(cvt_items)
        for index in regular:
            positions[index] = add(cvt_items[index])
        for index, candidates in latest_candidates.items():
            positions[index] = [
                (
                    add(candidate),
                    add(TlmItem(candidate.target_name, candidate.packet_name, "PACKET_TIMESECONDS", "RAW", None)),
                )
                for candidate in candidates
            ]
        rows = CvtModel.tsdb_lookup(query, start_time=start_time, end_time=end_time, scope=scope, flatten=False)
        if not isinstance(rows, list) or len(rows) == 0:
            return rows
        collapsed = []
        for row in rows:
            values = []
            for position in positions:
                if isinstance(position, int):
                    values.append(row[position])
                else:
                    # Take the candidate with the newest packet time at this row
                    newest = _tlm_newest(
                        [(row[time_index][0], row[value_index]) for value_index, time_index in position]
                    )
                    values.append(newest or [None, None])
            collapsed.append(values)
        # Match tsdb_lookup which returns a flat array for a single row
        return collapsed[0] if len(collapsed) == 1 else collapsed

    # A point in time returns the last row of the first packet before start_time
    # with the other packets ASOF JOINed at that row. A candidate packet received
    # after that row would be missed so query each candidate packet on its own.
    found = False
    row = [[None, None] for _ in cvt_items]
    if not all(cvt_items[index].item_name is None for index in regular):
        result = CvtModel.tsdb_lookup(
            [cvt_items[index] for index in regular], start_time=start_time, scope=scope, flatten=False
        )
        if isinstance(result, list) and len(result) > 0:
            found = True
            for result_index, index in enumerate(regular):
                row[index] = result[0][result_index]
    # Group the LATEST items by candidate packet so each packet is queried once
    by_packet = {}
    for index, candidates in latest_candidates.items():
        for candidate in candidates:
            by_packet.setdefault((candidate.target_name, candidate.packet_name), {})[index] = candidate
    found_values = {}
    for (target_name, packet_name), packet_items in by_packet.items():
        query = list(dict.fromkeys(packet_items.values()))
        query.append(TlmItem(target_name, packet_name, "PACKET_TIMESECONDS", "RAW", None))
        result = CvtModel.tsdb_lookup(query, start_time=start_time, scope=scope, flatten=False)
        if not isinstance(result, list) or len(result) == 0:
            continue
        values = result[0]
        for index, query_item in packet_items.items():
            found_values.setdefault(index, []).append((values[-1][0], values[query.index(query_item)]))
    for index, candidates in found_values.items():
        value = _tlm_newest(candidates)
        if value is None:
            continue
        found = True
        row[index] = value
    return row if found else {}


# Return the value with the newest time from (time, value) pairs, or None
def _tlm_newest(candidates):
    candidates = [candidate for candidate in candidates if candidate[0] is not None]
    if not candidates:
        return None
    return max(candidates, key=lambda candidate: candidate[0])[1]


# Expand LATEST to every packet containing the item
def _tlm_packet_names(target_name, packet_name, item_name, scope=OPENC3_SCOPE):
    if packet_name == "LATEST":
        packet_names = TargetModel.get_item_to_packet_map(target_name, scope=scope).get(item_name)
        if packet_names is None:
            raise RuntimeError(f"Item '{target_name} LATEST {item_name}' does not exist for scope: {scope}")
        return packet_names
    # Determine if this item exists, it will raise appropriate errors if not
    TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    return [packet_name]
