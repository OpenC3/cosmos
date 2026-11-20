# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.accessors.binary_accessor import BinaryAccessor
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem
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
                cls.resolve_nil_default(item)
                item.check_default_and_range_data_types()

        except TypeError as error:
            # Add the target name and packet name to the error message so the user
            # can debug where the error occurred
            raise TypeError(f"{packet.target_name} {packet.packet_name} {error}") from error

    @classmethod
    def resolve_nil_default(cls, item):
        """Resolve a nil, none, or null default on a REQUIRED parameter to None.

        REQUIRED parameters can use these since their default is never used.
        This is resolved once the packet is complete because REQUIRED comes
        after the PARAMETER line.

        Args:
            item: Command parameter to check

        Raises:
            TypeError: A parameter that isn't REQUIRED uses it as a numeric default
        """
        if not isinstance(item.default, str) or item.default.upper() not in PacketItem.NIL_DEFAULTS:
            return
        if item.required:
            item.default = None
        elif item.data_type not in ("STRING", "BLOCK", "ANY"):
            # STRING, BLOCK, and ANY keep it as a literal value
            raise TypeError(f"{item.name}: default of {item.default} is only allowed for REQUIRED parameters")

    @classmethod
    def check_item_default_sizes(cls, packet):
        """Check that each STRING and BLOCK default fits in its item.

        A default that doesn't fit makes the command impossible to build unless
        the parameter is given.

        Args:
            packet: Command packet to check

        Raises:
            ValueError: A default doesn't fit
        """
        if not isinstance(packet.accessor, BinaryAccessor):
            return

        for item in packet.sorted_items:
            if item.data_type not in ("STRING", "BLOCK"):
                continue
            default = item.default
            if not isinstance(default, str | bytes | bytearray):
                continue
            if item.array_size is not None or item.variable_bit_size or item.parent_item or item.write_conversion:
                continue
            if item.bit_size <= 0 or item.overflow == "TRUNCATE":
                continue

            byte_size = item.bit_size // 8
            default_size = len(default.encode()) if isinstance(default, str) else len(default)
            if default_size > byte_size:
                raise ValueError(
                    f"{packet.target_name} {packet.packet_name} {item.name}: default value of {default_size} bytes does not fit into {byte_size} bytes for data_type {item.data_type}"
                )

    @classmethod
    def _check_for_duplicate(cls, type, list, packet):
        msg = None
        if list.get(packet.target_name) and list[packet.target_name].get(packet.packet_name):
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
