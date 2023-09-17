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

from openc3.interfaces.protocols.terminated_protocol import TerminatedProtocol

# This file implements the COBS protocol as here=
# https=//en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing
# http=//www.stuartcheshire.org/papers/COBSforToN.pdf

# COBS is a framing protocol and is therefore expected to be used for packet deliniation

# Usage in plugin.txt=
#
# INTERFACE ...
#   PROTOCOL READ_WRITE CobsProtocol


class CobsProtocol(TerminatedProtocol):
    # self.param allow_empty_data [True/False/None] See Protocol#initialize
    def __init__(self, allow_empty_data=None):
        strip_read_termination = True
        discard_leading_bytes = 0
        sync_pattern = None
        fill_fields = False  # Handled in write_data below

        super().__init__(
            "",  # Write termination handled in write_data below
            "00",
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

        result_data = b""
        while len(data) > 1:
            # Read the offset to the next zero byte
            # Note: This may be off the end of the data. If so, the packet is over
            zero_offset = data[0]
            if zero_offset == 0xFF:  # No zeros in this segment
                result_data += data[1:255]
                data = data[255:]
            elif zero_offset <= 1:  # End of data or 1 zero
                result_data += b"\x00"
                data = data[1:]
            else:  # Mid range zero or end of packet
                result_data += data[1:zero_offset]
                data = data[zero_offset:]
                if len(data) >= 1:
                    result_data += b"\x00"

        return (result_data, extra)

    def write_data(self, data, extra=None):
        # Intentionally not calling super()

        need_insert = False
        result_data = b""
        while len(data) > 0:
            try:
                index = data.index(b"\x00")
                if index > 253:
                    result_data += b"\xFF"
                    result_data += data[0:254]
                    data = data[254:]
                    need_insert = False
                elif index <= 253:
                    result_data += (index + 1).to_bytes(1, byteorder="big")
                    if index >= 1:
                        result_data += data[0:index]
                    data = data[(index + 1) :]
                    need_insert = True
            except ValueError:  # index not found
                if len(data) >= 254:
                    result_data += b"\xFF"
                    result_data += data[0:254]
                    data = data[254:]
                    need_insert = False
                else:
                    result_data += (len(data) + 1).to_bytes(1, byteorder="big")
                    result_data += data
                    data = b""
                    need_insert = False

        # Handle a zero at the end of the packet
        if need_insert:
            result_data += b"\x01"

        # Terminate message with 0x00
        result_data += b"\x00"

        return (result_data, extra)
