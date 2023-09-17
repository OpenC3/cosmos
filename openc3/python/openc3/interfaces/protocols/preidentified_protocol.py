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

import math
import json
import struct
import datetime
from openc3.config.config_parser import ConfigParser
from openc3.interfaces.protocols.burst_protocol import BurstProtocol


# Delineates packets using the OpenC3 preidentification system
class PreidentifiedProtocol(BurstProtocol):
    COSMOS4_STORED_FLAG_MASK = 0x80
    COSMOS4_EXTRA_FLAG_MASK = 0x40

    # @param sync_pattern (see BurstProtocol#initialize)
    # @param max_length [Integer] The maximum allowed value of the length field
    # @param allow_empty_data [true/false/nil] See Protocol#initialize
    def __init__(
        self, sync_pattern=None, max_length=None, mode=4, allow_empty_data=None
    ):
        super().__init__(0, sync_pattern, False, allow_empty_data)
        self.max_length = ConfigParser.handle_none(max_length)
        if self.max_length:
            self.max_length = int(self.max_length)
        self.mode = int(mode)

    def reset(self):
        super().reset()
        self.reduction_state = "START"

    def read_packet(self, packet):
        packet.received_time = self.read_received_time
        packet.target_name = self.read_target_name.decode(encoding="ascii")
        packet.packet_name = self.read_packet_name.decode(encoding="ascii")
        if self.mode == 4:  # COSMOS4.3+ Protocol
            packet.stored = self.read_stored
            if packet.extra and self.read_extra:
                packet.extra.merge(self.read_extra)
            else:
                packet.extra = self.read_extra
        return packet

    def write_packet(self, packet):
        received_time = packet.received_time
        if not received_time:
            received_time = datetime.datetime.now()
        tv_usec, tv_sec = math.modf(received_time.timestamp())
        self.write_time_seconds = struct.pack(">I", int(tv_sec))  # UINT32
        self.write_time_microseconds = struct.pack(
            ">I", int(tv_usec * 1_000_000)
        )  # UINT32
        self.write_target_name = packet.target_name
        if not self.write_target_name:
            self.write_target_name = "UNKNOWN"
        self.write_packet_name = packet.packet_name
        if not self.write_packet_name:
            self.write_packet_name = "UNKNOWN"
        if self.mode == 4:  # COSMOS4.3+ Protocol
            self.write_flags = 0
            if packet.stored:
                self.write_flags |= PreidentifiedProtocol.COSMOS4_STORED_FLAG_MASK
            self.write_extra = None
            if packet.extra:
                self.write_flags |= PreidentifiedProtocol.COSMOS4_EXTRA_FLAG_MASK
                self.write_extra = json.dumps(packet.extra)
        return packet

    def write_data(self, data, extra=None):
        data_length = struct.pack(">I", len(data))  # UINT32
        data_to_send = b""
        if self.sync_pattern:
            data_to_send += self.sync_pattern
        if self.mode == 4:  # COSMOS4.3+ Protocol
            data_to_send += self.write_flags.to_bytes(1, byteorder="big")
            if self.write_extra:
                data_to_send += struct.pack(">I", len(self.write_extra))
                data_to_send += bytes(self.write_extra, "ascii")
        data_to_send += self.write_time_seconds
        data_to_send += self.write_time_microseconds
        data_to_send += struct.pack(">B", len(self.write_target_name))
        data_to_send += bytes(self.write_target_name, "ascii")
        data_to_send += struct.pack(">B", len(self.write_packet_name))
        data_to_send += bytes(self.write_packet_name, "ascii")
        data_to_send += data_length
        data_to_send += data
        return (data_to_send, extra)

    def read_length_field_followed_by_string(self, length_num_bytes):
        # Read bytes for string length
        if len(self.data) < length_num_bytes:
            return "STOP"

        string_length = self.data[0:length_num_bytes]

        match length_num_bytes:
            case 1:
                string_length = struct.unpack(">B", string_length)[0]  # UINT8
            case 2:
                string_length = struct.unpack(">H", string_length)[0]  # UINT16
            case 4:
                string_length = struct.unpack(">I", string_length)[0]  # UINT32
                if self.max_length and string_length > self.max_length:
                    raise RuntimeError(
                        f"Length value received larger than max_length: {string_length} > {self.max_length}"
                    )
            case _:
                raise RuntimeError(
                    f"Unsupported length given to read_length_field_followed_by_string: {length_num_bytes}"
                )

        # Read String
        if len(self.data) < (string_length + length_num_bytes):
            return "STOP"

        next_index = string_length + length_num_bytes
        string = self.data[length_num_bytes:next_index]

        # Remove data from current_data
        self.data = self.data[next_index:]

        return string

    def reduce_to_single_packet(self, extra=None):
        # Discard sync pattern if present
        if self.sync_pattern:
            if self.reduction_state == "START":
                if len(self.data) < len(self.sync_pattern):
                    return ("STOP", extra)

                self.data = self.data[(len(self.sync_pattern)) :]
                self.reduction_state = "SYNC_REMOVED"
        elif self.reduction_state == "START":
            self.reduction_state = "SYNC_REMOVED"

        if self.reduction_state == "SYNC_REMOVED" and self.mode == 4:
            # Read and remove flags
            if len(self.data) < 1:
                return ("STOP", extra)

            flags = self.data[0]  # struct.unpack(">B", self.data[0])  # byte
            self.data = self.data[1:]
            self.read_stored = False
            if (flags & PreidentifiedProtocol.COSMOS4_STORED_FLAG_MASK) != 0:
                self.read_stored = True
            self.read_extra = None
            if (flags & PreidentifiedProtocol.COSMOS4_EXTRA_FLAG_MASK) != 0:
                self.reduction_state = "NEED_EXTRA"
            else:
                self.reduction_state = "FLAGS_REMOVED"

        if self.reduction_state == "NEED_EXTRA":
            # Read and remove extra
            self.read_extra = self.read_length_field_followed_by_string(4)
            if self.read_extra == "STOP":
                return ("STOP", extra)

            self.read_extra = json.loads(self.read_extra)
            self.reduction_state = "FLAGS_REMOVED"

        if self.reduction_state == "FLAGS_REMOVED" or (
            self.reduction_state == "SYNC_REMOVED" and self.mode != 4
        ):
            # Read and remove packet received time
            if len(self.data) < 8:
                return ("STOP", extra)

            time_seconds = struct.unpack(">I", self.data[0:4])[0]  # UINT32
            time_microseconds = struct.unpack(">I", self.data[4:8])[0]  # UINT32
            self.read_received_time = datetime.datetime.fromtimestamp(
                time_seconds + time_microseconds / 1_000_000, datetime.timezone.utc
            )
            self.data = self.data[8:]
            self.reduction_state = "TIME_REMOVED"

        if self.reduction_state == "TIME_REMOVED":
            # Read and remove the target name
            self.read_target_name = self.read_length_field_followed_by_string(1)
            if self.read_target_name == "STOP":
                return ("STOP", extra)

            self.reduction_state = "TARGET_NAME_REMOVED"

        if self.reduction_state == "TARGET_NAME_REMOVED":
            # Read and remove the packet name
            self.read_packet_name = self.read_length_field_followed_by_string(1)
            if self.read_packet_name == "STOP":
                return ("STOP", extra)

            self.reduction_state = "PACKET_NAME_REMOVED"

        if self.reduction_state == "PACKET_NAME_REMOVED":
            # Read packet data and return
            packet_data = self.read_length_field_followed_by_string(4)
            if packet_data == "STOP":
                return ("STOP", extra)

            self.reduction_state = "START"
            return (packet_data, extra)

        raise RuntimeError(
            f"Error should never reach end of method {self.reduction_state}"
        )
