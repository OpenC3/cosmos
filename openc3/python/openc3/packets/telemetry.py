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


class Telemetry:
    """Telemetry uses PacketConfig to parse the command and telemetry
    configuration files. It contains all the knowledge of which telemetry packets
    exist in the system and how to access them. This class is the API layer
    which other classes use to access telemetry.

    This should not be confused with the Api module which implements the JSON
    API that is used by tools when accessing the Server. The Api module always
    provides Ruby primatives where the Telemetry class can return actual
    Packet or PacketItem objects. While there are some overlapping methods between
    the two, these are separate interfaces into the system."""

    LATEST_PACKET_NAME = "LATEST"

    # @param config [PacketConfig] Packet configuration to use to access the
    #  telemetry
    def __init__(self, config, system):
        self.system = system
        self.config = config

    # (see PacketConfig#warnings)
    def warnings(self):
        return self.config.warnings

    # @return [Array<String>] The command target names (excluding UNKNOWN)
    def target_names(self):
        result = self.config.telemetry.keys()
        result.delete("UNKNOWN")
        result.sort()
        return result

    # @param target_name [String] The target name
    # @return [Hash<packet_name=>Packet>] Hash of the telemetry packets for the given
    #   target name keyed by the packet name
    def packets(self, target_name):
        upcase_target_name = target_name.upper()
        target_packets = self.config.telemetry.get(upcase_target_name, None)
        if not target_packets:
            raise RuntimeError(
                f"Telemetry target '{upcase_target_name}' does not exist"
            )

        return target_packets

    # @param target_name [String] The target name
    # @param packet_name [String] The packet name. Must be a defined packet name
    #   and not 'LATEST'.
    # @return [Packet] The telemetry packet for the given target and packet name
    def packet(self, target_name, packet_name):
        target_packets = self.packets(target_name)
        upcase_packet_name = packet_name.upper()
        packet = target_packets.get(upcase_packet_name, None)
        if not packet:
            upcase_target_name = target_name.upper()
            raise RuntimeError(
                f"Telemetry packet '{upcase_target_name} {upcase_packet_name}' does not exist"
            )
        return packet

    # # @param target_name (see #packet)
    # # @param packet_name [String] The packet name. 'LATEST' can also be given
    # #   to specify the last received (or defined if no packets have been
    # #   received) packet within the given target that contains the
    # #   item_name.
    # # @param item_name [String] The item name
    # # @return [Packet, PacketItem] The packet and the packet item
    # def packet_and_item(target_name, packet_name, item_name):
    #     upcase_packet_name = str(packet_name).upper()
    #     if upcase_packet_name == "LATEST":
    #       return_packet = newest_packet(target_name, item_name)
    #     else:
    #       return_packet = packet(target_name, packet_name)
    #     item = return_packet.get_item(item_name)
    #     return [return_packet, item]

    # # Return a telemetry value from a packet.
    # #
    # # @param target_name (see #packet_and_item)
    # # @param packet_name (see #packet_and_item)
    # # @param item_name (see #packet_and_item)
    # # @param value_type [Symbol] How to convert the item before returning.
    # #   Must be one of {Packet::VALUE_TYPES}
    # # @return The value. :FORMATTED and :WITH_UNITS values are always returned
    # #   as Strings. :RAW values will match their data_type. :CONVERTED values
    # #   can be any type.
    # def value(target_name, packet_name, item_name, value_type = 'CONVERTED'):
    #     packet, _ = packet_and_item(target_name, packet_name, item_name) # Handles LATEST
    #     return packet.read(item_name, value_type)

    # # Reads the specified list of items and returns their values and limits
    # # state.
    # #
    # # @param item_array [Array<Array(String String String)>] An array
    # #   consisting of [target name, packet name, item name]
    # # @param value_types [Symbol|Array<Symbol>] How to convert the items before
    # #   returning. A single symbol of {Packet::VALUE_TYPES}
    # #   can be passed which will convert all items the same way. Or
    # #   an array of symbols can be passed to control how each item is
    # #   converted.
    # # @return [Array, Array, Array] The first array contains the item values and the
    # #   second their limits state, and the third their limits settings which includes
    # #   the red, yellow, and green (if given) limits values.
    # def values_and_limits_states(item_array, value_types = 'CONVERTED'):
    #     items = []

    #     # Verify item_array is a nested array
    #     raise AttributeError(f"item_array must be a nested array consisting of [[tgt,pkt,item],[tgt,pkt,item],...]") if not Array === item_array[0]

    #     states = []
    #     settings = []
    #     limits_set = System.limits_set

    #     if (Array === value_types) and len(item_array) != len(value_types):
    #         raise AttributeError(f"Passed {len(item_array)} items but only {len(value_types)} value types")

    #     value_type = value_types if not Array === value_types
    #     len(item_array).times do |index|
    #       entry = item_array[index]
    #       target_name = entry[0]
    #       packet_name = entry[1]
    #       item_name = entry[2]
    #       if Array === value_types:
    #           value_type = value_types[index]

    #       packet, item = packet_and_item(target_name, packet_name, item_name) # Handles LATEST
    #       items.append(packet.read(item_name, value_type))
    #       limits = item.limits
    #       states.append(limits.state)
    #       limits_values = limits.values
    #       if limits_values:
    #         limits_settings = limits_values[limits_set]
    #       else:
    #         limits_settings = None
    #       settings.append(limits_settings)

    #     return [items, states, settings]

    # # @param target_name (see #packet)
    # # @param packet_name (see #packet)
    # # @return [Array<PacketItem>] The telemetry items for the given target and packet name
    # def items(target_name, packet_name):
    #   return packet(target_name, packet_name).sorted_items

    # # @param target_name (see #packet)
    # # @param packet_name (see #packet) The packet name.  LATEST is supported.
    # # @return [Array<PacketItem>] The telemetry item names for the given target and packet name
    # def item_names(target_name, packet_name):
    #   if LATEST_PACKET_NAME.casecmp(packet_name).zero?:
    #     target_upmatch = str(target_name).upper():
    #     target_latest_data = self.config.latest_data[target_upcase]
    #     raise "Telemetry Target '{target_upcase}' does not exist" if not target_latest_data

    #     item_names = target_latest_data.keys
    #   else:
    #     tlm_packet = packet(target_name, packet_name)
    #     item_names = []
    #     tlm_packet.sorted_items.each { |item| item_names.append(item.name })
    #   item_names

    # # Set a telemetry value in a packet.
    # #
    # # @param target_name (see #packet_and_item)
    # # @param packet_name (see #packet_and_item)
    # # @param item_name (see #packet_and_item)
    # # @param value The value to set in the packet
    # # @param value_type (see #tlm)
    # def set_value(target_name, packet_name, item_name, value, value_type = 'CONVERTED'):
    #   packet, _ = packet_and_item(target_name, packet_name, item_name)
    #   packet.write(item_name, value, value_type)

    # # @param target_name (see #packet_and_item)
    # # @param item_name (see #packet_and_item)
    # # @return [Array<Packet>] The latest (most recently arrived) packets with
    # #   the specified target and item.
    # def latest_packets(target_name, item_name):
    #   target_upmatch = str(target_name).upper():
    #   item_upmatch = str(item_name).upper():
    #   target_latest_data = self.config.latest_data[target_upcase]
    #   raise "Telemetry target '{target_upcase}' does not exist" if not target_latest_data

    #   packets = self.config.latest_data[target_upcase][item_upcase]
    #   raise "Telemetry item '{target_upcase} {LATEST_PACKET_NAME} {item_upcase}' does not exist" if not packets

    #   return packets

    # # @param target_name (see #packet_and_item)
    # # @param item_name (see #packet_and_item)
    # # @return [Packet] The packet with the most recent timestamp that contains
    # #   the specified target and item.
    # def newest_packet(target_name, item_name):
    #   # Handle LATEST_PACKET_NAME - Lookup packets for this target/item
    #   packets = latest_packets(target_name, item_name)

    #   # Find packet with newest timestamp
    #   newest_packet = None
    #   newest_received_time = None
    #    for packet in packets:
    #     received_time = packet.received_time
    #     if newest_received_time:
    #       # See if the received time from this packet is newer.
    #       # Having the >= makes this method return the last defined packet
    #       # whether the timestamps are both nil or both equal.
    #       if received_time and received_time >= newest_received_time:
    #         newest_packet = packet
    #         newest_received_time = newest_packet.received_time
    #     else:
    #       # No received time yet so take this packet
    #       newest_packet = packet
    #       newest_received_time = newest_packet.received_time
    #   return newest_packet

    # # Identifies an unknown buffer of data as a defined packet and sets the
    # # packet's data to the given buffer. Identifying a packet uses the fields
    # # marked as ID_ITEM to identify if the buffer passed represents the
    # # packet defined. Incorrectly sized buffers are still processed but an
    # # error is logged.
    # #
    # # Note: This affects all subsequent requests for the packet (for example
    # # using packet) which is why the method is marked with a bang!
    # #
    # # @param packet_data [String] The binary packet data buffer
    # # @param target_names [Array<String>] List of target names to limit the search. The
    # #   default value of nil means to search all known targets.
    # # @return [Packet] The identified packet with its data set to the given
    # #   packet_data buffer. Returns nil if no packet could be identified.
    # def identify!(packet_data, target_names = None):
    #   identified_packet = identify(packet_data, target_names)
    #   if identified_packet:
    #       identified_packet.buffer = packet_data
    #   return identified_packet

    # Finds a packet from the Current Value Table that matches the given data
    # and returns it.  Does not fill the packets buffer.  Use identify! to update the CVT.
    #
    # @param packet_data [String] The binary packet data buffer
    # @param target_names [Array<String>] List of target names to limit the search. The
    #   default value of nil means to search all known targets.
    # @return [Packet] The identified packet, Returns nil if no packet could be identified.
    def identify(self, packet_data, target_names=None):
        if not target_names:
            target_names = target_names()

        for target_name in target_names:
            target_name = str(target_name).upper()

            target_packets = None
            try:
                target_packets = self.packets(target_name)
            except RuntimeError:
                # No telemetry for this target
                continue

            target = self.system.targets[target_name]
            if target and target.tlm_unique_id_mode:
                # Iterate through the packets and see if any represent the buffer
                for _, packet in target_packets:
                    if packet.identify(packet_data):
                        return packet
            else:
                # Do a hash lookup to quickly identify the packet
                if len(target_packets) > 0:
                    packet = next(iter(target_packets.values()))
                    key = packet.read_id_values(packet_data)
                    hash = self.config.tlm_id_value_hash[target_name]
                    identified_packet = hash.get(repr(key))
                    if not identified_packet:
                        identified_packet = hash.get("CATCHALL")
                    if identified_packet:
                        return identified_packet

        return None

    def identify_and_define_packet(self, packet, target_names=None):
        if not packet.identified():
            identified_packet = self.identify(packet.buffer_no_copy(), target_names)
            if not identified_packet:
                return None

            identified_packet = identified_packet.clone()
            identified_packet.buffer = packet.buffer
            identified_packet.received_time = packet.received_time
            identified_packet.stored = packet.stored
            identified_packet.extra = packet.extra
            return identified_packet

        if not packet.defined():
            try:
                identified_packet = self.packet(packet.target_name, packet.packet_name)
            except RuntimeError:
                return None
            identified_packet = identified_packet.clone()
            identified_packet.buffer = packet.buffer
            identified_packet.received_time = packet.received_time
            identified_packet.stored = packet.stored
            identified_packet.extra = packet.extra
            return identified_packet

        return packet

    # Updates the specified packet with the given packet data. Raises an error
    # if the packet could not be found.
    #
    # Note: This affects all subsequent requests for the packet
    #
    # @param target_name (see #packet)
    # @param packet_name (see #packet)
    # @param packet_data (see #identify_tlm!)
    # @return [Packet] The packet with its data set to the given packet_data
    #   buffer.
    def update(self, target_name, packet_name, packet_data):
        identified_packet = self.packet(target_name, packet_name)
        identified_packet.buffer = packet_data
        return identified_packet

    # # Assigns a limits change callback to all telemetry packets
    # #
    # # @param limits_change_callback
    # def limits_change_callback=(limits_change_callback):
    #    for target_name, packets in self.config.telemetry:
    #      for packet_name, packet in packets:
    #       packet.limits_change_callback = limits_change_callback

    # # Clears the received_count value on every packet in every target
    # def clear_counters:
    #    for target_name, target_packets in self.config.telemetry:
    #      for packet_name, packet in target_packets:
    #       packet.received_count = 0

    # # Resets metadata on every packet in every target
    # def reset:
    #    for target_name, target_packets in self.config.telemetry:
    #      for packet_name, packet in target_packets:
    #       packet.reset

    # # Returns the first non-hidden packet
    # def first_non_hidden:
    #    for target_name, target_packets in self.config.telemetry:
    #     if target_name == 'UNKNOWN':
    #         next

    #      for packet_name, packet in target_packets:
    #       return packet if not packet.hidden
    #   None

    # # Returns an array with a "TARGET_NAME PACKET_NAME ITEM_NAME" string for every item in the system
    # def all_item_strings(include_hidden = False, splash = None):
    #   strings = []
    #   tnames = target_names()
    #   total = len(tnames) float()
    #   tnames.each_with_index do |target_name, index|
    #     if splash:
    #       splash.message = "Processing {target_name} telemetry"
    #       splash.progress = index / total

    #     # Note: System only has declared target structures but telemetry may have more
    #     system_target = System.targets[target_name]
    #     if system_target:
    #       ignored_items = system_target.ignored_items
    #     else:
    #       ignored_items = []

    #      for packet_name, packet in packets(target_name):
    #       # We don't audit against hidden or disabled packets
    #       if !include_hidden and (packet.hidden or packet.disabled):
    #           next

    #       packet.items.each_key do |item_name|
    #         # Skip ignored items
    #         if !include_hidden and ignored_items.include? item_name:
    #             next

    #         strings.append("{target_name} {packet_name} {item_name}")
    #   return strings

    # @return [Hash{String=>Hash{String=>Packet}}] Hash of all the telemetry
    #   packets keyed by the target name. The value is another hash keyed by the
    #   packet name returning the packet.
    def all(self):
        return self.config.telemetry
