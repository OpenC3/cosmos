# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.interfaces.protocols.protocol import Protocol
from openc3.system.system import System


# Ignore a specific packet by not letting it through the protocol
class IgnorePacketProtocol(Protocol):
    # @param target_name [String] Target name
    # @param packet_name [String] Packet name
    def __init__(self, target_name, packet_name, allow_empty_data=None):
        super().__init__(allow_empty_data)
        System.telemetry.packet(target_name, packet_name)
        self.target_name = target_name
        self.packet_name = packet_name

    def read_packet(self, packet):
        # Need to make sure packet is identified and defined
        target_names = None
        if self.interface:
            target_names = self.interface.tlm_target_names
        identified_packet = System.telemetry.identify_and_define_packet(packet, target_names)
        if (
            identified_packet
            and identified_packet.target_name == self.target_name
            and identified_packet.packet_name == self.packet_name
        ):
            return "STOP"
        return super().read_packet(packet)

    def write_packet(self, packet):
        if packet.target_name == self.target_name and packet.packet_name == self.packet_name:
            return "STOP"

        return super().write_packet(packet)

    def write_details(self):
        result = super().write_details()
        result["target_name"] = self.target_name
        result["packet_name"] = self.packet_name
        return result

    def read_details(self):
        result = super().read_details()
        result["target_name"] = self.target_name
        result["packet_name"] = self.packet_name
        return result
