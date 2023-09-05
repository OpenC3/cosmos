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
from openc3.interfaces.protocols.terminated_protocol import TerminatedProtocol

# This file implements the SLIP protocol as documented in RFC 1055
# https://datatracker.ietf.org/doc/html/rfc1055

# SLIP is a framing protocol and is therefore expected to be used for packet deliniation


class SlipProtocol(TerminatedProtocol):
    # Note: Characters are expected to be given as integers
    # @param start_char   [Integer/nil] Character to place at the start of frames (Defaults to nil)
    # @param read_strip_characters [true/false] Strip off start_char and end_char from reads
    # @param read_enable_escaping [true/false] Whether to enable or disable character escaping on reads
    # @param write_enable_escaping [true/false] Whether to enable or disable character escaping on writes
    # @param end_char     [Integer] Character to place at the end of frames (Defaults to 0xC0)
    # @param esc_char     [Integer] Escape character (Defaults to 0xDB)
    # @param esc_end_char [Integer] Character to Escape End character (Defaults to 0xDC)
    # @param esc_esc_char [Integer] Character to Escape Escape character (Defaults to 0xDD)
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def __init__(
        self,
        start_char=None,
        read_strip_characters=True,
        read_enable_escaping=True,
        write_enable_escaping=True,
        end_char="0xC0",
        esc_char="0xDB",
        esc_end_char="0xDC",
        esc_esc_char="0xDD",
        allow_empty_data=None,
    ):
        self.start_char = ConfigParser.handle_none(start_char)
        if self.start_char is not None:
            try:
                self.start_char = int(start_char, 0).to_bytes(1, byteorder="big")
            except ValueError:
                raise ValueError(f"invalid value {start_char} for start_char")
        self.end_char = int(end_char, 0).to_bytes(1, byteorder="big")
        self.esc_char = int(esc_char, 0).to_bytes(1, byteorder="big")
        self.esc_esc_char = int(esc_esc_char, 0).to_bytes(1, byteorder="big")
        self.esc_end_char = int(esc_end_char, 0).to_bytes(1, byteorder="big")
        self.replace_end = self.esc_char + self.esc_end_char
        self.replace_esc = self.esc_char + self.esc_esc_char
        self.read_strip_characters = ConfigParser.handle_true_false(
            read_strip_characters
        )
        if (
            self.read_strip_characters is not True
            and self.read_strip_characters is not False
        ):
            raise RuntimeError("read_strip_characters must be True or False")
        self.read_enable_escaping = ConfigParser.handle_true_false(read_enable_escaping)
        if (
            self.read_enable_escaping is not True
            and self.read_enable_escaping is not False
        ):
            raise RuntimeError("read_enable_escaping must be True or False")
        self.write_enable_escaping = ConfigParser.handle_true_false(
            write_enable_escaping
        )
        if (
            self.write_enable_escaping is not True
            and self.write_enable_escaping is not False
        ):
            raise RuntimeError("write_enable_escaping must be True or False")

        strip_read_termination = False
        discard_leading_bytes = 0
        sync_pattern = None
        if self.start_char:
            sync_pattern = hex(int(start_char, 0))
        fill_fields = False  # Handled in write_data below

        super().__init__(
            "",  # Write termination handled in write_data below
            hex(int(end_char, 0)),  # Expects Hex Character String
            strip_read_termination,
            discard_leading_bytes,
            sync_pattern,
            fill_fields,
            allow_empty_data,
        )

    def read_data(self, data, extra=None):
        data, extra = super().read_data(data, extra)
        if len(data) <= 0 or type(data) is str:
            return (data, extra)

        if self.read_strip_characters:
            if self.start_char:
                data = data[1:]
            data = data[0:-1]

        if self.read_enable_escaping:
            data = data.replace(self.replace_end, self.end_char).replace(
                self.replace_esc, self.esc_char
            )

        return (data, extra)

    def write_data(self, data, extra=None):
        # Intentionally not calling super()

        if self.write_enable_escaping:
            data = data.replace(self.esc_char, self.replace_esc).replace(
                self.end_char, self.replace_end
            )

        if self.start_char:
            data = self.start_char + data

        data += self.end_char

        return (data, extra)

    def reduce_to_single_packet(self, extra=None):
        if len(self.data) <= 0:
            return ("STOP", extra)
        index = None
        if self.start_char is not None:
            try:
                index = self.data[1:].index(self.read_termination_characters)
                index = index + 1
            except ValueError:
                pass
        else:
            try:
                index = self.data.index(self.read_termination_characters)
            except ValueError:
                pass

        # Reduce to packet data and setup current_data for next packet
        if index is not None:
            if index > 0:
                packet_data = self.data[
                    0 : (index + len(self.read_termination_characters))
                ]
            else:  # self.data begins with the termination characters
                packet_data = self.data[0 : (len(self.read_termination_characters))]
            self.data = self.data[(index + len(self.read_termination_characters)) :]
            return (packet_data, extra)
        else:
            return ("STOP", extra)
