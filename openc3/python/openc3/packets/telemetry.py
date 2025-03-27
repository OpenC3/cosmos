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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1953


class Telemetry:
    """Telemetry uses PacketConfig to parse the command and telemetry
    configuration files. It contains all the knowledge of which telemetry packets
    exist in the system and how to access them. This class is the API layer
    which other classes use to access telemetry.

    This should not be confused with the Api module which implements the JSON
    API that is used by tools when accessing the Server. The Api module always
    provides Ruby primitives where the Telemetry class can return actual
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
        result = list(self.config.telemetry.keys())
        result.remove("UNKNOWN")
        result.sort()
        return result

    # @param target_name [String] The target name
    # @return [Hash<packet_name=>Packet>] Hash of the telemetry packets for the given
    #   target name keyed by the packet name
    def packets(self, target_name):
        upcase_target_name = target_name.upper()
        target_packets = self.config.telemetry.get(upcase_target_name, None)
        if not target_packets:
            raise RuntimeError(f"Telemetry target '{upcase_target_name}' does not exist")

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
            raise RuntimeError(f"Telemetry packet '{upcase_target_name} {upcase_packet_name}' does not exist")
        return packet

    # Identifies an unknown buffer of data as a defined packet and sets the
    # packet's data to the given buffer. Identifying a packet uses the fields
    # marked as ID_ITEM to identify if the buffer passed represents the
    # packet defined. Incorrectly sized buffers are still processed but an
    # error is logged.
    #
    # Note: This affects all subsequent requests for the packet (for example
    # using packet)
    #
    # @param packet_data [String] The binary packet data buffer
    # @param target_names [Array<String>] List of target names to limit the search. The
    #   default value of nil means to search all known targets.
    # @return [Packet] The identified packet with its data set to the given
    #   packet_data buffer. Returns nil if no packet could be identified.
    def identify_and_set_buffer(self, packet_data, target_names=None):
        identified_packet = self.identify(packet_data, target_names)
        if identified_packet:
            identified_packet.buffer = packet_data
        return identified_packet

    # Finds a packet from the Current Value Table that matches the given data
    # and returns it.  Does not fill the packets buffer.  Use identify! to update the CVT.
    #
    # @param packet_data [String] The binary packet data buffer
    # @param target_names [Array<String>] List of target names to limit the search. The
    #   default value of nil means to search all known targets.
    # @return [Packet] The identified packet, Returns nil if no packet could be identified.
    def identify(self, packet_data, target_names=None):
        if target_names is None:
            target_names = self.target_names()

        for target_name in target_names:
            target_name = str(target_name).upper()

            target_packets = None
            try:
                target_packets = self.packets(target_name)
            except RuntimeError:
                # No telemetry for this target
                continue

            target = self.system.targets.get(target_name)
            if target and target.tlm_unique_id_mode:
                # Iterate through the packets and see if any represent the buffer
                for _, packet in target_packets.items():
                    if packet.identify(packet_data):
                        return packet
            else:
                # Do a hash lookup to quickly identify the packet
                if len(target_packets) > 0:
                    packet = next(iter(target_packets.values()))
                    key = packet.read_id_values(packet_data)
                    id_values = self.config.tlm_id_value_hash[target_name]
                    identified_packet = id_values.get(repr(key))
                    if identified_packet is None:
                        identified_packet = id_values.get("CATCHALL")
                    if identified_packet is not None:
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

    # Assigns a limits change callback to all telemetry packets
    #
    # @param limits_change_callback
    def set_limits_change_callback(self, limits_change_callback):
        for _, packets in self.config.telemetry.items():
            for _, packet in packets.items():
                packet.limits_change_callback = limits_change_callback

    # Resets metadata on every packet in every target
    def reset(self):
        for _, packets in self.config.telemetry.items():
            for _, packet in packets.items():
                packet.reset()

    # @return [Hash{String=>Hash{String=>Packet}}] Hash of all the telemetry
    #   packets keyed by the target name. The value is another hash keyed by the
    #   packet name returning the packet.
    def all(self):
        return self.config.telemetry

    def dynamic_add_packet(self, packet, affect_ids=False):
        self.config.dynamic_add_packet(packet, "TELEMETRY", affect_ids=affect_ids)
