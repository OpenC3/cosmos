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

from openc3.config.config_parser import ConfigParser
from openc3.interfaces.protocols.burst_protocol import BurstProtocol
from openc3.utilities.extract import hex_to_byte_string


# Protocol which delineates packets using termination characters at
# the end of the data.
class TerminatedProtocol(BurstProtocol):
    # self.param write_termination_characters [String] The characters to write
    #   after writing the Packet buffer. Must be given as a
    #   hexadecimal string such as '0xABCD'.
    # self.param read_termination_characters [String] The characters at the end of
    #   the data which delineate the end of a Packet. Must be given as a
    #   hexadecimal string such as '0xABCD'.
    # self.param strip_read_termination [Boolean] Whether to remove the
    #   read_termination_characters before turning the data into a
    #   Packet.
    # self.param discard_leading_bytes (see BurstProtocol#initialize)
    # self.param sync_pattern (see BurstProtocol#initialize)
    # self.param fill_fields (see BurstProtocol#initialize)
    # self.param allow_empty_data [True/False/None] See Protocol#initialize
    def __init__(
        self,
        write_termination_characters,
        read_termination_characters,
        strip_read_termination=True,
        discard_leading_bytes=0,
        sync_pattern=None,
        fill_fields=False,
        allow_empty_data=None,
    ):
        self.write_termination_characters = hex_to_byte_string(write_termination_characters)
        self.read_termination_characters = hex_to_byte_string(read_termination_characters)
        self.strip_read_termination = ConfigParser.handle_true_false(strip_read_termination)
        if self.strip_read_termination is not True and self.strip_read_termination is not False:
            raise RuntimeError("strip_read_termination must be True or False")

        super().__init__(discard_leading_bytes, sync_pattern, fill_fields, allow_empty_data)

    def write_data(self, data, extra):
        try:
            data.index(self.write_termination_characters)
            raise RuntimeError("Packet contains termination characters!")
        except ValueError:  # no index
            pass

        data, extra = super().write_data(data, extra)
        for byte in self.write_termination_characters:
            data.append(byte)
        return (data, extra)

    def reduce_to_single_packet(self, extra=None):
        try:
            index = self.data.index(self.read_termination_characters)

            # Reduce to packet data and setup current_data for next packet
            if index > 0:
                if self.strip_read_termination:
                    packet_data = self.data[0:index]
                else:
                    packet_data = self.data[0 : (index + len(self.read_termination_characters))]
            else:  # self.data begins with the termination characters
                if self.strip_read_termination:
                    packet_data = b""
                else:  # Keep everything
                    packet_data = self.data[0 : (len(self.read_termination_characters))]
            self.data = self.data[(index + len(self.read_termination_characters)) :]
            return (packet_data, extra)
        except ValueError:  # sync_index = None
            return ("STOP", extra)
