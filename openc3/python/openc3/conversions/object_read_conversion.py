# Copyright 2024 OpenC3, Inc.
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

from openc3.config.config_parser import ConfigParser
from openc3.conversions.conversion import Conversion
from openc3.system.system import System


class ObjectReadConversion(Conversion):
    def __init__(self, cmd_or_tlm, target_name, packet_name):
        super().__init__()
        cmd_or_tlm = ConfigParser.handle_none(cmd_or_tlm)
        if cmd_or_tlm:
            self.cmd_or_tlm = str(cmd_or_tlm).upper()
            if self.cmd_or_tlm not in ["CMD", "TLM", "COMMAND", "TELEMETRY"]:
                raise TypeError(f"Unknown type: {cmd_or_tlm}")
        else:
            # Unknown - Will need to search
            self.cmd_or_tlm = None
        self.target_name = str(target_name).upper()
        self.packet_name = str(packet_name).upper()
        self.converted_type = "OBJECT"
        self.converted_bit_size = 0
        self.params = [self.cmd_or_tlm, self.target_name, self.packet_name]

    def lookup_packet(self):
        if self.cmd_or_tlm:
            if self.cmd_or_tlm == "CMD" or self.cmd_or_tlm == "COMMAND":
                return System.commands.packet(self.target_name, self.packet_name)
            else:
                return System.telemetry.packet(self.target_name, self.packet_name)
        else:
            # Always searches commands first
            try:
                return System.commands.packet(self.target_name, self.packet_name)
            except RuntimeError:
                return System.telemetry.packet(self.target_name, self.packet_name)

    # Perform the conversion on the value.
    def call(self, value, _packet, buffer):
        fill_packet = self.lookup_packet()
        fill_packet.buffer = value
        all = fill_packet.read_all("CONVERTED", buffer, True)
        return {item[0]: item[1] for item in all}

    # @return [String] The conversion class
    def __str__(self):
        return f"{self.__class__.__name__} {self.cmd_or_tlm if self.cmd_or_tlm else 'None'} {self.target_name} {self.packet_name}"

    # @return [String] Config fragment for this conversion
    def to_config(self, read_or_write):
        return f"{read_or_write}_CONVERSION openc3/conversions/object_read_conversion.py {self.cmd_or_tlm if self.cmd_or_tlm else 'None'} {self.target_name} {self.packet_name}\n"
