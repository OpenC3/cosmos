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

from openc3.packets.packet import Packet
from openc3.utilities.logger import Logger


class PacketParser:
    @classmethod
    def parse_command(cls, parser, target_name, commands, warnings):
        parser = PacketParser(parser)
        parser.verify_parameters()
        return parser.create_command(target_name, commands, warnings)

    @classmethod
    def parse_telemetry(cls, parser, target_name, telemetry, latest_data, warnings):
        parser = PacketParser(parser)
        parser.verify_parameters()
        return parser.create_telemetry(target_name, telemetry, latest_data, warnings)

    @classmethod
    def check_item_data_types(cls, packet):
        try:
            for item in packet.sorted_items:
                item.check_default_and_range_data_types()

        except TypeError as error:
            # Add the target name and packet name to the error message so the user
            # can debug where the error occurred
            raise TypeError(f"{packet.target_name} {packet.packet_name} {error}") from error

    @classmethod
    def _check_for_duplicate(cls, type, list, packet):
        msg = None
        if list.get(packet.target_name):
            if list[packet.target_name].get(packet.packet_name):
                msg = f"{type} Packet {packet.target_name} {packet.packet_name} redefined."
                Logger.warn(msg)
        return msg

    @classmethod
    def _finish_create_command(cls, packet, commands, warnings):
        warning = PacketParser._check_for_duplicate("Command", commands, packet)
        if warning:
            warnings.append(warning)
        packet.define_reserved_items()
        if not commands.get(packet.target_name):
            commands[packet.target_name] = {}
        return packet

    @classmethod
    def _finish_create_telemetry(cls, packet, telemetry, latest_data, warnings):
        warning = PacketParser._check_for_duplicate("Telemetry", telemetry, packet)
        if warning:
            warnings.append(warning)
        packet.define_reserved_items()

        if not telemetry.get(packet.target_name):
            telemetry[packet.target_name] = {}
            latest_data[packet.target_name] = {}
        return packet

    def __init__(self, parser):
        self.parser = parser

    def verify_parameters(self):
        self.usage = f"{self.parser.keyword} <TARGET NAME> <PACKET NAME> <ENDIANNESS: BIG_ENDIAN/LITTLE_ENDIAN> <DESCRIPTION (Optional)>"
        self.parser.verify_num_parameters(3, 4, self.usage)
        self.parser.verify_parameter_naming(2)  # Packet name is the 2nd parameter

    def create_command(self, target_name, commands, warnings):
        packet = self._create_packet(target_name)
        return PacketParser._finish_create_command(packet, commands, warnings)

    def create_telemetry(self, target_name, telemetry, latest_data, warnings):
        packet = self._create_packet(target_name)
        return PacketParser._finish_create_telemetry(packet, telemetry, latest_data, warnings)

    def _create_packet(self, target_name):
        params = self.parser.parameters
        if target_name == "SYSTEM":
            target_name = params[0].upper()
        packet_name = params[1].upper()
        endianness = params[2].upper()
        # description is optional
        description = None
        if len(params) > 3:
            description = params[3]
        if endianness != "BIG_ENDIAN" and endianness != "LITTLE_ENDIAN":
            raise self.parser.error(
                f"Invalid endianness {params[2]}. Must be BIG_ENDIAN or LITTLE_ENDIAN.",
                self.usage,
            )
        return Packet(target_name, packet_name, endianness, description)
