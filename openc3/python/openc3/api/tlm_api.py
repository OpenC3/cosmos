#!/usr/bin/env python3

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
        "set_tlm",
        "inject_tlm",
        "override_tlm",
        "get_overrides",
        "normalize_tlm",
        "get_tlm_buffer",
        "get_tlm_packet",
        "get_tlm_values",
        "get_all_telemetry",
        "get_all_telemetry_names",
        "get_telemetry",
        "get_item",
        # 'subscribe_packets',
        # 'get_packets',
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
def tlm(*args, type="CONVERTED", scope=OPENC3_SCOPE):
    target_name, packet_name, item_name = _tlm_process_args(args, "tlm", scope=scope)
    authorize(
        permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope
    )
    return CvtModel.get_item(target_name, packet_name, item_name, type, scope)


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
    target_name, packet_name, item_name, value = _set_tlm_process_args(
        args, "set_tlm", scope=scope
    )
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    CvtModel.set_item(
        target_name, packet_name, item_name, value, type=type, scope=scope
    )


# Injects a packet into the system as if it was received from an interface
#
# @param target_name [String] Target name of the packet
# @param packet_name [String] Packet name of the packet
# @param item_hash [Hash] Hash of item_name and value for each item you want to change from the current value table
# @param type [Symbol] Telemetry type, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
def inject_tlm(
    target_name, packet_name, item_hash=None, type="CONVERTED", scope=OPENC3_SCOPE
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
        raise RuntimeError(f"Unknown type '{type}' for {target_name} {packet_name}")

    if item_hash:
        item_hash = {k.upper(): v for k, v in item_hash.items()}
        # Check that the items exist ... exceptions are raised if not
        TargetModel.packet_items(target_name, packet_name, item_hash.keys, scope=scope)
    else:
        # Check that the packet exists ... exceptions are raised if not
        TargetModel.packet(target_name, packet_name, scope=scope)

    # See if this target has a tlm interface
    interface_name = None
    for _, interface in InterfaceModel.all(scope):
        if target_name in interface["tlm_target_names"]:
            interface_name = interface["name"]
            break

    # Use an interface microservice if it exists, other use the decom microservice
    if interface_name:
        InterfaceTopic.inject_tlm(
            interface_name, target_name, packet_name, item_hash, type=type, scope=scope
        )
    else:
        DecomInterfaceTopic.inject_tlm(
            target_name, packet_name, item_hash, type=type, scope=scope
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
#   description).
# @param type [Symbol] Telemetry type, :ALL (default), :RAW, :CONVERTED, :FORMATTED, :WITH_UNITS
def override_tlm(*args, type="ALL", scope=OPENC3_SCOPE):
    target_name, packet_name, item_name, value = _set_tlm_process_args(
        args, "override_tlm", scope=scope
    )
    authorize(
        permission="tlm_set",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    CvtModel.override(
        target_name, packet_name, item_name, value, type=type, scope=scope
    )


# Get the list of CVT overrides
def get_overrides(scope=OPENC3_SCOPE):
    authorize(permission="tlm", scope=scope)
    CvtModel.overrides(scope=scope)


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
    target_name, packet_name, item_name = _tlm_process_args(
        args, "normalize_tlm", scope=scope
    )
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
def get_tlm_buffer(target_name, packet_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    authorize(
        permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope
    )
    TargetModel.packet(target_name, packet_name, scope=scope)
    topic = f"{scope}__TELEMETRY__{{{target_name}}}__{packet_name}"
    msg_id, msg_hash = Topic.get_newest_message(topic)
    if msg_id:
        # TODO: Python equivalent of .b
        # msg_hash['buffer'] = msg_hash['buffer'].b
        return msg_hash
    return None


# Returns all the values (along with their limits state) for a packet.
#
# @param target_name [String] Name of the target
# @param packet_name [String] Name of the packet
# @param stale_time [Integer] Time in seconds from Time.now that packet will be marked stale
# @param type [Symbol] Types returned, :RAW, :CONVERTED (default), :FORMATTED, or :WITH_UNITS
# @return [Array<String, Object, Symbol|None>] Returns an Array consisting
#   of [item name, item value, item limits state] where the item limits
#   state can be one of {OpenC3::Limits::LIMITS_STATES}
def get_tlm_packet(
    self, target_name, packet_name, stale_time=30, type="CONVERTED", scope=OPENC3_SCOPE
):
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    authorize(
        permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope
    )
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    t = _validate_tlm_type(type)
    if not t:
        raise AttributeError(f"Unknown type '{type}' for {target_name} {packet_name}")
    items = {item["name"].upper() for item in packet["items"]}
    cvt_items = {f"{target_name}__{packet_name}__{item}__{type}" for item in items}
    current_values = CvtModel.get_tlm_values(
        cvt_items, stale_time=stale_time, scope=scope
    )
    return {[item, values[0], values[1]] for item, values in current_values}


# Returns all the item values (along with their limits state). The items
# can be from any target and packet and thus must be fully qualified with
# their target and packet names.
#
# @param items [Array<String>] Array of items consisting of 'tgt__pkt__item__type'
# @param stale_time [Integer] Time in seconds from Time.now that data will be marked stale
# @return [Array<Object, Symbol>]
#   Array consisting of the item value and limits state
#   given as symbols such as :RED, :YELLOW, :STALE
def get_tlm_values(items, stale_time=30, scope=OPENC3_SCOPE):
    if type(items) != list or type(items[0]) != str:
        raise AttributeError(
            "items must be array of strings: ['TGT__PKT__ITEM__TYPE', ...]"
        )
    for index, item in enumerate(items):
        target_name, packet_name, item_name, value_type = item.split("__")
        if not target_name or not packet_name or not item_name or not value_type:
            raise AttributeError("items must be formatted as TGT__PKT__ITEM__TYPE")
        target_name = target_name.upper()
        packet_name = packet_name.upper()
        item_name = item_name.upper()
        value_type = value_type.upper()
        if packet_name == "LATEST":
            _, packet_name, _ = _tlm_process_args(
                [target_name, packet_name, item_name], "get_tlm_values", scope=scope
            )  # Figure out which packet is LATEST
        # Change packet_name in case of LATEST and ensure upcase
        items[index] = f"{target_name}__{packet_name}__{item_name}__{value_type}"
        authorize(
            permission="tlm",
            target_name=target_name,
            packet_name=packet_name,
            scope=scope,
        )
    return CvtModel.get_tlm_values(items, stale_time=stale_time, scope=scope)


# Returns an array of all the telemetry packet hashes
#
# @param target_name [String] Name of the target
# @return [Array<Hash>] Array of all telemetry packet hashes
def get_all_telemetry(target_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    authorize(permission="tlm", target_name=target_name, scope=scope)
    return TargetModel.packets(target_name, type="TLM", scope=scope)


# Returns an array of all the telemetry packet names
#
# @param target_name [String] Name of the target
# @return [Array<String>] Array of all telemetry packet names
def get_all_telemetry_names(target_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    authorize(permission="cmd_info", target_name=target_name, scope=scope)
    return TargetModel.packet_names(target_name, type="TLM", scope=scope)


# Returns a telemetry packet hash
#
# @param target_name [String] Name of the target
# @param packet_name [String] Name of the packet
# @return [Hash] Telemetry packet hash
def get_telemetry(target_name, packet_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    authorize(
        permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope
    )
    return TargetModel.packet(target_name, packet_name, scope=scope)


# Returns a telemetry packet item hash
#
# @param target_name [String] Name of the target
# @param packet_name [String] Name of the packet
# @param item_name [String] Name of the packet
# @return [Hash] Telemetry packet item hash
def get_item(target_name, packet_name, item_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    authorize(
        permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope
    )
    return TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)


# # 2x double underscore since __ is reserved
# SUBSCRIPTION_DELIMITER = '____'

# # Subscribe to a list of packets. An ID is returned which is passed to
# # get_packets(id) to return packets.
# #
# # @param packets [Array<Array<String, String>>] Array of arrays consisting of target name, packet name
# # @return [String] ID which should be passed to get_packets
# def subscribe_packets(packets, scope=OPENC3_SCOPE)
#   if !packets.is_a?(Array) || !packets[0].is_a?(Array)
#     raise ArgumentError, "packets must be nested array: [['TGT','PKT'],...]"
#   end

#   result = {}
#   packets.each do |target_name, packet_name|
#     target_name = target_name.upper()
#     packet_name = packet_name.upper()
#     authorize(permission='tlm', target_name= target_name, packet_name= packet_name, scope=scope)
#     topic = "#{scope}__DECOM__{#{target_name}}__#{packet_name}"
#     id, _ = Topic.get_newest_message(topic)
#     result[topic] = id ? id : '0-0'
#   end
#   result.to_a.join(SUBSCRIPTION_DELIMITER)
# end
# # Alias the singular as well since that matches COSMOS 4
# alias subscribe_packet subscribe_packets

# # Get packets based on ID returned from subscribe_packet.
# # @param id [String] ID returned from subscribe_packets or last call to get_packets
# # @param block [Integer] Unused - Blocking must be implemented at the client
# # @param count [Integer] Maximum number of packets to return from EACH packet stream
# # @return [Array<String, Array<Hash>] Array of the ID and array of all packets found
# def get_packets(id, block: None, count: 1000, scope=OPENC3_SCOPE)
#   authorize(permission='tlm', scope=scope)
#   # Split the list of topic, ID values and turn it into a hash for easy updates
#   lookup = Hash[*id.split(SUBSCRIPTION_DELIMITER)]
#   xread = Topic.read_topics(lookup.keys, lookup.values, None, count) # Always don't block
#   # Return the original ID and and empty array if we didn't get anything
#   packets = []
#   return [id, packets] if xread.empty?
#   xread.each do |topic, data|
#     data.each do |id, msg_hash|
#       lookup[topic] = id # save the new ID
#       json_hash = JSON.parse(msg_hash['json_data'], :allow_nan => true, :create_additions => true)
#       msg_hash.delete('json_data')
#       packets << msg_hash.merge(json_hash)
#     end
#   end
#   return lookup.to_a.join(SUBSCRIPTION_DELIMITER), packets
# end


# Get the receive count for a telemetry packet
#
# @param target_name [String] Name of the target
# @param packet_name [String] Name of the packet
# @return [Numeric] Receive count for the telemetry packet
def get_tlm_cnt(target_name, packet_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    authorize(
        permission="system",
        target_name=target_name,
        packet_name=packet_name,
        scope=scope,
    )
    TargetModel.packet(target_name, packet_name, scope=scope)
    return Topic.get_cnt(f"{scope}__TELEMETRY__{{{target_name}}}__{packet_name}")


# Get the transmit counts for telemetry packets
#
# @param target_packets [Array<Array<String, String>>] Array of arrays containing target_name, packet_name
# @return [Numeric] Transmit count for the command
def get_tlm_cnts(target_packets, scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    counts = []
    for target_name, packet_name in target_packets:
        target_name = target_name.upper()
        packet_name = packet_name.upper()
        counts << Topic.get_cnt(f"{scope}__TELEMETRY__{{{target_name}}}__{packet_name}")
    return counts


# Get the list of derived telemetry items for a packet
#
# @param target_name [String] Target name
# @param packet_name [String] Packet name
# @return [Array<String>] All of the ignored telemetry items for a packet.
def get_packet_derived_items(target_name, packet_name, scope=OPENC3_SCOPE):
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    authorize(
        permission="tlm", target_name=target_name, packet_name=packet_name, scope=scope
    )
    packet = TargetModel.packet(target_name, packet_name, scope=scope)
    return [item["name"] for item in packet["items"] if item["data_type"] == "DERIVED"]


def _validate_tlm_type(type):
    match type:
        case "RAW":
            return ""
        case "CONVERTED":
            return "C"
        case "FORMATTED":
            return "F"
        case "WITH_UNITS":
            return "U"
    return None


def _tlm_process_args(args, method_name, scope=OPENC3_SCOPE):
    match (len(args)):
        case 1:
            target_name, packet_name, item_name = extract_fields_from_tlm_text(args[0])
        case 3:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
        case _:
            # Invalid number of arguments
            raise RuntimeError(
                f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()"
            )
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    if packet_name == "LATEST":
        latest = -1
        for packet in TargetModel.packets(target_name, scope=scope):
            found = None
            for item in packet["items"]:
                if item["name"] == item_name:
                    found = item
                    break
            if found:
                hash = CvtModel.get(target_name, packet["packet_name"], scope)
                if hash["PACKET_TIMESECONDS"] and hash["PACKET_TIMESECONDS"] > latest:
                    latest = hash["PACKET_TIMESECONDS"]
                    packet_name = packet["packet_name"]
        if latest == -1:
            raise RuntimeError(
                f"Item '{target_name} LATEST {item_name}' does not exist"
            )
    else:
        pass
        # Determine if this item exists, it will raise appropriate errors if not
        TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)
    return [target_name, packet_name, item_name]


def _set_tlm_process_args(args, method_name, scope=OPENC3_SCOPE):
    match len(args):
        case 1:
            (
                target_name,
                packet_name,
                item_name,
                value,
            ) = extract_fields_from_set_tlm_text(args[0])
        case 4:
            target_name = args[0]
            packet_name = args[1]
            item_name = args[2]
            value = args[3]
        case _:
            # Invalid number of arguments
            raise RuntimeError(
                f"ERROR: Invalid number of arguments ({len(args)}) passed to {method_name}()"
            )
    target_name = target_name.upper()
    packet_name = packet_name.upper()
    item_name = item_name.upper()
    # Determine if this item exists, it will raise appropriate errors if not
    TargetModel.packet_item(target_name, packet_name, item_name, scope=scope)

    return [target_name, packet_name, item_name, value]
