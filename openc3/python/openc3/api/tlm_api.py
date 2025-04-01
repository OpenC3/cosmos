# Copyright 2025 OpenC3, Inc.
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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963

# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957

import json
from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.topics.topic import Topic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel
from openc3.models.interface_model import InterfaceModel
from openc3.utilities.extract import *

WHITELIST.extend(
    [
        "tlm",
        "tlm_raw",
        "tlm_formatted",
        "tlm_with_units",
        "set_tlm",
        "inject_tlm",
        "override_tlm",
        "get_overrides",
        "normalize_tlm",
        "get_tlm_buffer",
        "get_tlm_packet",
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
# @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
# @return [Object] The telemetry value formatted as requested
def tlm(*args, type="CONVERTED", cache_timeout=0.1, scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_process_args(args, "tlm", cache_timeout=cache_timeout, scope=scope)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    return CvtModel.get_item(target_name, packet_name, item_name, type, cache_timeout, scope)


def tlm_raw(*args, cache_timeout=0.1, scope=OPENC3_SCOPE):
    return tlm(*args, type="RAW", cache_timeout=cache_timeout, scope=scope)


def tlm_formatted(*args, cache_timeout=0.1, scope=OPENC3_SCOPE):
    return tlm(*args, type="FORMATTED", cache_timeout=cache_timeout, scope=scope)


def tlm_with_units(*args, cache_timeout=0.1, scope=OPENC3_SCOPE):
    return tlm(*args, type="WITH_UNITS", cache_timeout=cache_timeout, scope=scope)


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
# @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
def set_tlm(*args, type="CONVERTED", scope=OPENC3_SCOPE):
    target_name, packet_name, item_name, value = _set_tlm_process_args(args, "set_tlm", scope)
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
# @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
def inject_tlm(target_name, packet_name, item_hash=None, type="CONVERTED", scope=OPENC3_SCOPE):
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    if type not in CvtModel.VALUE_TYPES:
        raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name}")

    if item_hash:
        item_hash = {k.upper(): v for k, v in item_hash.items()}
        # Check that the items exist ... exceptions are raised if not
        items = TargetModel.packet_items(target_name, packet_name, item_hash.keys(), scope=scope)
        if type == 'CONVERTED':
            # If the type is converted, check that the item states are valid
            for item_name, item_value in item_hash.items():
                item = next((i for i in items if i['name'] == item_name.upper()), None)
                if item and item.get('states') and item_value not in item['states']:
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
        InterfaceTopic.inject_tlm(interface_name, target_name, packet_name, item_hash, type=type, scope=scope)
    else:
        DecomInterfaceTopic.inject_tlm(target_name, packet_name, item_hash, type=type, scope=scope)


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
#   description).
# @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED, :WITH_UNITS
def override_tlm(*args, type="ALL", scope=OPENC3_SCOPE):
    target_name, packet_name, item_name, value = _set_tlm_process_args(args, "override_tlm", scope)
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
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
#   (see the calling style in the description).
# @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED, :WITH_UNITS
#   Also takes :ALL which means to normalize all telemetry types
def normalize_tlm(*args, type="ALL", scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_process_args(args, "normalize_tlm", scope=scope)
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    CvtModel.normalize(target_name, packet_name, item_name, type=type, scope=scope)


# Returns the raw buffer for a telemetry packet.
#
# @param target_name [String] Name of the target
# @param packet_name [String] Name of the packet
# @return [Hash] telemetry hash with last telemetry buffer
def get_tlm_buffer(*args, scope=OPENC3_SCOPE):
    target_name, packet_name = _extract_target_packet_names("get_tlm_buffer", *args)
    authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
    TargetModel.packet(target_name, packet_name, scope=scope)
    topic = f"{scope}__TELEMETRY__{{{target_name}}}__{packet_name}"
    msg_id, msg_hash = Topic.get_newest_message(topic)
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
        type (str) Types returned, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS

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
        raise TypeError(f"Unknown type '{type}' for {target_name} {packet_name}")
    cvt_items = [[target_name, packet_name, item["name"].upper(), type] for item in packet["items"]]
    # This returns an array of arrays containing the value and the limits state:
    # [[0, None], [0, 'RED_LOW'], ... ]
    current_values = CvtModel.get_tlm_values(cvt_items, stale_time=stale_time, scope=scope)
    return [[cvt_items[index][2], item[0], item[1]] for index, item in enumerate(current_values)]


# Returns all the item values (along with their limits state). The items
# can be from any target and packet and thus must be fully qualified with
# their target and packet names.
#
# @param items [Array<String>] Array of items consisting of 'tgt__pkt__item__type'
# @param stale_time [Integer] Time in seconds from Time.now that data will be marked stale
# @return [Array<Object, Symbol>]
#   Array consisting of the item value and limits state
#   given as symbols such as :RED, :YELLOW, :STALE
def get_tlm_values(items, stale_time=30, cache_timeout=0.1, scope=OPENC3_SCOPE):
    if not isinstance(items, list) or len(items) == 0 or not isinstance(items[0], str):
        raise TypeError("items must be array of strings: ['TGT__PKT__ITEM__TYPE', ...]")
    packets = []
    cvt_items = []
    for item in items:
        try:
            target_name, packet_name, item_name, value_type = item.upper().split("__")
        except ValueError:
            raise ValueError("items must be formatted as TGT__PKT__ITEM__TYPE")
        if packet_name == "LATEST":
            packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout, scope)
        # Change packet_name in case of LATEST and ensure upcase
        cvt_items.append([target_name, packet_name, item_name, value_type])
        packets.append([target_name, packet_name])
    # Make the array of arrays unique
    packets = [list(x) for x in set(tuple(x) for x in packets)]
    for name in packets:
        authorize(
            permission="tlm",
            target_name=name[0],
            packet_name=name[1],
            scope=scope,
        )
    return CvtModel.get_tlm_values(cvt_items, stale_time, cache_timeout, scope)


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
    except RuntimeError:
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
    except RuntimeError:
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


def get_item(*args, scope: str = OPENC3_SCOPE):
    """Returns a telemetry packet item hash

    Args:
        scope (str) Name of the scope

    Return:
        (dict) Telemetry packet hash
    """
    target_name, packet_name, item_name = _extract_target_packet_item_names("get_item", *args)
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
        authorize(permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope)
        topic = f"{scope}__DECOM__{{{target_name}}}__{packet_name}"
        id_, _ = Topic.get_newest_message(topic)
        result[topic] = id_ if id_ else "0-0"

    mylist = []
    for k, v in result.items():
        mylist += [k, v]
    return SUBSCRIPTION_DELIMITER.join(mylist)


def get_packets(id, count=1000, scope=OPENC3_SCOPE):
    """Get packets based on ID returned from subscribe_packet.

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
    lookup = dict(zip(items[::2], items[1::2]))
    packets = []
    for topic, _, msg_hash, _ in Topic.read_topics(lookup.keys(), list(lookup.values()), None, count):
        # # Return the original ID and empty array if we didn't get anything
        # for topic, data in xread:
        # for id, msg_hash in data:
        lookup[topic] = id  # save the new ID
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
    authorize(permission="system", target_name=target_name, packet_name=packet_name, scope=scope)
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
            try:
                target_name, packet_name = args[0].upper().split()
            except ValueError:
                # We get ValueError if passing not enough parameters
                # The check below for None handles this case
                pass
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
    return target_name, packet_name


def _extract_target_packet_item_names(method_name, *args):
    target_name = None
    packet_name = None
    item_name = None
    match len(args):
        case 1:
            try:
                target_name, packet_name, item_name = args[0].upper().split()
            except ValueError:  # Thrown when not enough items given
                # Do nothing because below error will catch this
                pass
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
        case "FORMATTED":
            return "F"
        case "WITH_UNITS":
            return "U"
    return None


def _tlm_process_args(args, method_name, cache_timeout=0.1, scope=OPENC3_SCOPE):
    match (len(args)):
        case 1:
            target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        case 3:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
        case _:
            # Invalid number of arguments
            raise RuntimeError(f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()")
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    if packet_name == "LATEST":
        packet_name = CvtModel.determine_latest_packet_for_item(target_name, item_name, cache_timeout, scope)
    else:
        # Determine if this item exists, it will raise appropriate errors if not
        TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    return target_name, packet_name, item_name


def _set_tlm_process_args(args, method_name, scope=OPENC3_SCOPE):
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
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    # Determine if this item exists, it will raise appropriate errors if not
    TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)

    return target_name, packet_name, item_name, value
