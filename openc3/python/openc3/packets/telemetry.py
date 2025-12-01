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

from typing import TYPE_CHECKING, Any, Callable, Optional, Union

# TYPE_CHECKING is False at runtime but True during type checking.
# This allows us to import types for type hints without causing circular import errors.
# These imports are only used for static type checking by tools like Pylance/mypy.
if TYPE_CHECKING:
    from openc3.packets.packet_config import PacketConfig
    from openc3.packets.packet import Packet
    from openc3.packets.packet_item import PacketItem
    from openc3.system.system import System


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
    def __init__(self, config: "PacketConfig", system: "System") -> None:
        self.system = system
        self.config = config

    # (see PacketConfig#warnings)
    def warnings(self) -> list[str]:
        return self.config.warnings

    # @return [Array<String>] The command target names (excluding UNKNOWN)
    def target_names(self) -> list[str]:
        result = list(self.config.telemetry.keys())
        result.remove("UNKNOWN")
        result.sort()
        return result

    # @param target_name [String] The target name
    # @return [Hash<packet_name=>Packet>] Hash of the telemetry packets for the given
    #   target name keyed by the packet name
    def packets(self, target_name: str) -> dict[str, "Packet"]:
        upcase_target_name = target_name.upper()
        target_packets = self.config.telemetry.get(upcase_target_name, None)
        if not target_packets:
            raise RuntimeError(f"Telemetry target '{upcase_target_name}' does not exist")

        return target_packets

    # @param target_name [String] The target name
    # @param packet_name [String] The packet name. Must be a defined packet name
    #   and not 'LATEST'.
    # @return [Packet] The telemetry packet for the given target and packet name
    def packet(self, target_name: str, packet_name: str) -> "Packet":
        target_packets = self.packets(target_name)
        upcase_packet_name = packet_name.upper()
        packet = target_packets.get(upcase_packet_name, None)
        if not packet:
            upcase_target_name = target_name.upper()
            raise RuntimeError(f"Telemetry packet '{upcase_target_name} {upcase_packet_name}' does not exist")
        return packet

    # Finds the newest (most recently defined) packet that contains the given item
    #
    # @param target_name [String] The target name
    # @param item_name [String] The item name
    # @return [Packet] The newest packet that contains the item
    def newest_packet(self, target_name: str, item_name: str) -> "Packet":
        upcase_target_name = target_name.upper()
        upcase_item_name = item_name.upper()

        target_latest_data = self.config.latest_data.get(upcase_target_name)
        if not target_latest_data:
            raise RuntimeError(f"Telemetry target '{upcase_target_name}' does not exist")

        item_latest_data = target_latest_data.get(upcase_item_name)
        if not item_latest_data:
            raise RuntimeError(f"Telemetry item '{upcase_target_name} LATEST {upcase_item_name}' does not exist")

        packet = item_latest_data
        return packet

    # Get a telemetry packet and item
    #
    # @param target_name [String] The target name
    # @param packet_name [String] The packet name. 'LATEST' can also be given
    #   to specify the last received (or defined if no packets have been
    #   received) packet within the given target that contains the item_name.
    # @param item_name [String] The item name
    # @return [Packet, PacketItem] The packet and the packet item
    def packet_and_item(self, target_name: str, packet_name: str, item_name: str) -> tuple["Packet", "PacketItem"]:
        upcase_packet_name = packet_name.upper()
        if upcase_packet_name == self.LATEST_PACKET_NAME:
            return_packet = self.newest_packet(target_name, item_name)
        else:
            return_packet = self.packet(target_name, packet_name)
        item = return_packet.get_item(item_name)
        return (return_packet, item)

    # Return a telemetry value from a packet.
    #
    # @param target_name [String] The target name
    # @param packet_name [String] The packet name
    # @param item_name [String] The item name
    # @param value_type [String] How to convert the item before returning.
    #   Must be one of 'RAW', 'CONVERTED', 'FORMATTED', 'WITH_UNITS'
    # @return The value. 'FORMATTED' and 'WITH_UNITS' values are always returned
    #   as Strings. 'RAW' values will match their data_type. 'CONVERTED' values
    #   can be any type.
    def value(self, target_name: str, packet_name: str, item_name: str, value_type: str = "CONVERTED") -> Any:
        packet, _ = self.packet_and_item(target_name, packet_name, item_name)  # Handles LATEST
        return packet.read(item_name, value_type)

    # Reads the specified list of items and returns their values and limits state.
    #
    # @param item_array [List[List[str]]] A list of lists containing
    #   [target_name, packet_name, item_name]
    # @param value_types [str|List[str]] How to convert the items before
    #   returning. A single string can be passed which will convert all items
    #   the same way. Or a list of strings can be passed to control how each
    #   item is converted.
    # @return [List, List, List] The first list contains the item values, the
    #   second their limits state, and the third their limits settings which includes
    #   the red, yellow, and green (if given) limits values.
    def values_and_limits_states(self, item_array: list[list[str]], value_types: Union[str, list[str]] = "CONVERTED") -> tuple[list[Any], list[Any], list[Any]]:
        items = []
        states = []
        settings = []

        # Verify item_array is a nested list
        if not isinstance(item_array[0], (list, tuple)):
            raise ValueError("item_array must be a nested array consisting of [[tgt,pkt,item],[tgt,pkt,item],...]")

        limits_set = self.system.limits_set()

        if isinstance(value_types, list) and len(item_array) != len(value_types):
            raise ValueError(f"Passed {len(item_array)} items but only {len(value_types)} value types")

        for index, entry in enumerate(item_array):
            target_name = entry[0]
            packet_name = entry[1]
            item_name = entry[2]

            if isinstance(value_types, list):
                value_type = value_types[index]
            else:
                value_type = value_types

            packet, item = self.packet_and_item(target_name, packet_name, item_name)  # Handles LATEST
            items.append(packet.read(item_name, value_type))

            limits = item.limits
            states.append(limits.state if limits else None)

            if limits and limits.values:
                limits_settings = limits.values.get(limits_set)
            else:
                limits_settings = None
            settings.append(limits_settings)

        return (items, states, settings)

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
    def identify_and_set_buffer(self, packet_data: bytes, target_names: Optional[list[str]] = None, subpackets: bool = False) -> Optional["Packet"]:
        identified_packet = self.identify(packet_data, target_names, subpackets=subpackets)
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
    def identify(self, packet_data: bytes, target_names: Optional[list[str]] = None, subpackets: bool = False) -> Optional["Packet"]:
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

            if (not subpackets and self.tlm_unique_id_mode(target_name)) or (
                subpackets and self.tlm_subpacket_unique_id_mode(target_name)
            ):
                # Iterate through the packets and see if any represent the buffer
                for _, packet in target_packets.items():
                    if subpackets:
                        if not packet.subpacket:
                            continue
                    else:
                        if packet.subpacket:
                            continue
                    if packet.identify(packet_data):  # Handles virtual
                        return packet
            else:
                # Do a hash lookup to quickly identify the packet
                packet = None
                for _, target_packet in target_packets.items():
                    if target_packet.virtual:
                        continue
                    if subpackets:
                        if not target_packet.subpacket:
                            continue
                    else:
                        if target_packet.subpacket:
                            continue
                    packet = target_packet
                    break
                if packet:
                    key = packet.read_id_values(packet_data)
                    if subpackets:
                        id_values = self.config.tlm_subpacket_id_value_hash[target_name]
                    else:
                        id_values = self.config.tlm_id_value_hash[target_name]
                    identified_packet = id_values.get(repr(key))
                    if identified_packet is None:
                        identified_packet = id_values.get("CATCHALL")
                    if identified_packet is not None:
                        return identified_packet

        return None

    def identify_and_define_packet(self, packet: "Packet", target_names: Optional[list[str]] = None, subpackets: bool = False) -> Optional["Packet"]:
        if not packet.identified():
            identified_packet = self.identify(packet.buffer_no_copy(), target_names, subpackets=subpackets)
            if not identified_packet:
                return None

            identified_packet = identified_packet.clone()
            identified_packet.buffer = packet.buffer
            identified_packet.received_time = packet.received_time
            identified_packet.stored = packet.stored
            identified_packet.extra = packet.extra
            return identified_packet

        if not packet.defined():
            if not packet.target_name or not packet.packet_name:
                return None
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
    def update(self, target_name: str, packet_name: str, packet_data: bytes) -> "Packet":
        identified_packet = self.packet(target_name, packet_name)
        identified_packet.buffer = packet_data
        return identified_packet

    # Assigns a limits change callback to all telemetry packets
    #
    # @param limits_change_callback
    def set_limits_change_callback(self, limits_change_callback: Callable) -> None:
        for _, packets in self.config.telemetry.items():
            for _, packet in packets.items():
                packet.limits_change_callback = limits_change_callback

    # Resets metadata on every packet in every target
    def reset(self) -> None:
        for _, packets in self.config.telemetry.items():
            for _, packet in packets.items():
                packet.reset()

    # @return [Hash{String=>Hash{String=>Packet}}] Hash of all the telemetry
    #   packets keyed by the target name. The value is another hash keyed by the
    #   packet name returning the packet.
    def all(self) -> dict[str, dict[str, "Packet"]]:
        return self.config.telemetry

    def dynamic_add_packet(self, packet: "Packet", affect_ids: bool = False) -> None:
        self.config.dynamic_add_packet(packet, "TELEMETRY", affect_ids=affect_ids)

    def tlm_unique_id_mode(self, target_name: str) -> Optional[bool]:
        return self.config.tlm_unique_id_mode.get(target_name.upper())

    def tlm_subpacket_unique_id_mode(self, target_name: str) -> Optional[bool]:
        return self.config.tlm_subpacket_unique_id_mode.get(target_name.upper())
