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
from openc3.system.system import System
from openc3.config.config_parser import ConfigParser
from openc3.interfaces.protocols.burst_protocol import BurstProtocol


# Delineates packets by identifying them and then
# reading out their entire fixed length. Packets lengths can vary but
# they must all be fixed.
class FixedProtocol(BurstProtocol):
    # self.param min_id_size [Integer] The minimum amount of data needed to
    #   identify a packet.
    # self.param discard_leading_bytes (see BurstProtocol#initialize)
    # self.param sync_pattern (see BurstProtocol#initialize)
    # self.param telemetry [Boolean] Whether the interface is returning
    #   telemetry (True) or commands (False)
    # self.param fill_fields (see BurstProtocol#initialize)
    # self.param unknown_raise Whether to raise an exception on an unknown packet
    # self.param allow_empty_data [True/False/None] See Protocol#initialize
    def __init__(
        self,
        min_id_size,
        discard_leading_bytes=0,
        sync_pattern=None,
        telemetry=True,
        fill_fields=False,
        unknown_raise=False,
        allow_empty_data=None,
    ):
        super().__init__(
            discard_leading_bytes, sync_pattern, fill_fields, allow_empty_data
        )
        self.min_id_size = int(min_id_size)
        self.telemetry = telemetry
        self.unknown_raise = ConfigParser.handle_true_false(unknown_raise)
        self.received_time = None
        self.target_name = None
        self.packet_name = None

    # Set the received_time, target_name and packet_name which we recorded when
    # we identified this packet. The server will also do this but since we know
    # the information here, we perform this optimization.
    def read_packet(self, packet):
        packet.received_time = self.received_time
        packet.target_name = self.target_name
        packet.packet_name = self.packet_name
        return packet

    # Identifies an unknown buffer of data as a Packet. The raw data is
    # returned but the packet that matched is recorded so it can be set in the
    # read_packet callback.
    #
    # self.return [String|Symbol] The identified packet data or 'STOP' if more data:
    #   is required to build a packet
    def identify_and_finish_packet(self, extra):
        packet_data = None
        identified_packet = None

        if self.telemetry:
            target_names = self.interface.tlm_target_names
        else:
            target_names = self.interface.cmd_target_names

        for target_name in target_names:
            target_packets = None
            unique_id_mode = False
            try:
                if self.telemetry:
                    target_packets = System.telemetry.packets(target_name)
                    target = System.targets[target_name]
                    if target:
                        unique_id_mode = target.tlm_unique_id_mode
                else:
                    target_packets = System.commands.packets(target_name)
                    target = System.targets[target_name]
                    if target:
                        unique_id_mode = target.cmd_unique_id_mode
            except RuntimeError as error:
                if "does not exist" in repr(error):
                    # No commands/telemetry for this target
                    continue
                else:
                    raise error

            if unique_id_mode:
                for _, packet in target_packets.items():
                    if packet.identify(self.data[self.discard_leading_bytes :]):
                        identified_packet = packet
                        break
            else:
                # Do a hash lookup to quickly identify the packet
                if len(target_packets) > 0:
                    packet = next(iter(target_packets.values()))
                    key = packet.read_id_values(self.data[self.discard_leading_bytes :])
                    if self.telemetry:
                        hash = System.telemetry.config.tlm_id_value_hash[target_name]
                    else:
                        hash = System.commands.config.cmd_id_value_hash[target_name]
                    identified_packet = hash.get(repr(key))
                    if identified_packet is None:
                        identified_packet = hash.get("CATCHALL")

            if identified_packet is not None:
                if identified_packet.defined_length + self.discard_leading_bytes > len(
                    self.data
                ):
                    # Check if need more data to finish packet:
                    return ("STOP", extra)

                # Set some variables so we can update the packet in
                # read_packet
                self.received_time = datetime.now(timezone.utc)
                self.target_name = identified_packet.target_name
                self.packet_name = identified_packet.packet_name

                # Get the data from this packet
                packet_data = self.data[
                    0 : (identified_packet.defined_length + self.discard_leading_bytes)
                ]
                self.data = self.data[
                    (identified_packet.defined_length + self.discard_leading_bytes) :
                ]
                break

        if identified_packet is None:
            if self.unknown_raise:
                raise RuntimeError("Unknown data received by FixedProtocol")

            # Unknown packet? Just return all the current data
            self.received_time = None
            self.target_name = None
            self.packet_name = None
            packet_data = self.data[:]
            self.data = b""

        return (packet_data, extra)

    def reduce_to_single_packet(self, extra=None):
        if len(self.data) < self.min_id_size:
            return ("STOP", extra)

        return self.identify_and_finish_packet(extra)
