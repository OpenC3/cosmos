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
from openc3.interfaces.protocols.protocol import Protocol
from openc3.accessors.binary_accessor import BinaryAccessor
from openc3.packets.packet import Packet
from openc3.utilities.logger import Logger
from openc3.utilities.extract import hex_to_byte_string


# Reads all data available on the interface and creates a packet
# with that data.
class BurstProtocol(Protocol):
    # self.param discard_leading_bytes [Integer] The number of bytes to discard
    #   from the binary data after reading. Note that this is often
    #   used to remove a sync pattern from the final packet data.
    # self.param sync_pattern [String] String representing a hex number ("0x1234")
    #   that will be searched for in the raw data. Bytes encountered before
    #   this pattern is found are discarded.
    # self.param fill_fields [Boolean] Fill any required fields when writing packets
    # self.param allow_empty_data [True/False/None] See Protocol#initialize
    def __init__(
        self,
        discard_leading_bytes=0,
        sync_pattern=None,
        fill_fields=False,
        allow_empty_data=None,
    ):
        super().__init__(allow_empty_data)
        self.discard_leading_bytes = int(discard_leading_bytes)
        self.sync_pattern = ConfigParser.handle_none(sync_pattern)
        if self.sync_pattern:
            self.sync_pattern = hex_to_byte_string(self.sync_pattern)
        self.fill_fields = ConfigParser.handle_true_false(fill_fields)

    def reset(self):
        super().reset()
        self.data = b""
        # self.data.force_encoding('ASCII-8BIT')
        self.sync_state = "SEARCHING"

    # Reads from the interface. It can look for a sync pattern before
    # creating a Packet. It can discard a set number of bytes at the try:ning
    # before creating the Packet.
    #
    # Note= On the first call to this from any interface read(), data will contain a blank
    # string. Blank string is an opportunity for protocols to return any queued up packets.
    # If they have no queued up packets, they should pass the blank string down to chained
    # protocols giving them the same opportunity.
    #
    # self.return [String|None] Data for a packet consisting of the bytes read
    def read_data(self, data, extra=None):
        self.data += data

        while True:
            control = self.handle_sync_pattern()
            if control and len(data) > 0:  # Only return here if not blank string test
                return (control, extra)

            # Reduce the data to a single packet
            packet_data, extra = self.reduce_to_single_packet(extra)
            if packet_data == "RESYNC":
                self.sync_state = "SEARCHING"
                if len(data) > 0:  # Only immediately resync if not blank string test
                    continue

            # Potentially allow blank string to be sent to other protocols if no packet is ready in this one
            if isinstance(packet_data, str):
                if (len(data) <= 0) and packet_data != "DISCONNECT":
                    # On blank string test, return blank string (if not we had a packet or need disconnect)
                    # The base class handles the special match of returning STOP if on the last protocol in the
                    # chain
                    return super().read_data(data, extra)
                else:
                    return (
                        packet_data,
                        extra,
                    )  # Return any control code if not on blank string test

            self.sync_state = "SEARCHING"

            # Discard leading bytes if necessary
            if self.discard_leading_bytes > 0:
                packet_data = packet_data[self.discard_leading_bytes :]
            return (packet_data, extra)

    # Called to perform modifications on a command packet before it is sent
    #
    # self.param packet [Packet] Original packet
    # self.return [Packet] Potentially modified packet
    def write_packet(self, packet: Packet):
        # If we're filling the sync pattern and the sync pattern is part of the
        # packet (since we're not discarding any leading bytes) then we have to
        # fill the sync pattern in the actual packet so do it here.
        if self.fill_fields and self.sync_pattern and self.discard_leading_bytes == 0:
            # Directly write the packet buffer and fill in the sync pattern
            BinaryAccessor.write(
                self.sync_pattern,
                0,
                len(self.sync_pattern) * 8,
                "BLOCK",
                packet.buffer_no_copy(),
                "BIG_ENDIAN",
                "ERROR",
            )
        return packet

    # Called to perform modifications on write data before sending it to the interface
    #
    # self.param data [String] Raw packet data
    # self.return [String] Potentially modified packet data
    def write_data(self, data, extra=None):
        # If we're filling the sync pattern and discarding the leading bytes
        # during a read then we need to put them back during a write.
        # If we're discarding the bytes then by definition they can't be part
        # of the packet so we just modify the data.
        if self.fill_fields and self.discard_leading_bytes > 0:
            data = bytearray(b"\x00" * self.discard_leading_bytes) + data
            if self.sync_pattern:
                BinaryAccessor.write(
                    self.sync_pattern,
                    0,
                    len(self.sync_pattern) * 8,
                    "BLOCK",
                    data,
                    "BIG_ENDIAN",
                    "ERROR",
                )
        return super().write_data(data, extra)

    # self.return [Boolean] control code (None, 'STOP')
    def handle_sync_pattern(self):
        if self.sync_pattern and self.sync_state == "SEARCHING":
            while True:
                # Make sure we have some data to look for a sync word in
                if len(self.data) < len(self.sync_pattern):
                    return "STOP"

                # Find the beginning of the sync pattern
                try:
                    sync_index = self.data.index(self.sync_pattern[0])
                    # Make sure we have enough data for the whole sync pattern past this index
                    if len(self.data) < (sync_index + len(self.sync_pattern)):
                        return "STOP"

                    # Check for the rest of the sync pattern
                    found = True
                    index = sync_index
                    for byte in self.sync_pattern:
                        if self.data[index] != byte:
                            found = False
                            break
                        index += 1

                    if found:
                        if sync_index != 0:
                            self.log_discard(sync_index, True)
                            # Delete Data Before Sync Pattern
                            self.data = self.data[sync_index:]
                        self.sync_state = "FOUND"
                        return None

                    else:  # not found
                        self.log_discard(sync_index, False)
                        # Delete Data Before and including first character of suspected sync Pattern
                        self.data = self.data[(sync_index + 1) :]
                        continue

                except ValueError:  # sync_index = None
                    self.log_discard(len(self.data), False)
                    self.data = b""
                    return "STOP"
        return None

    def log_discard(self, length, found):
        name = ""
        if self.interface:
            name = self.interface.name
        Logger.error(f"{name}: Sync {'not ' if not found else ''}found. Discarding {length} bytes of data.")
        pdata = self.data
        if len(self.data) < 6:
            pdata = self.data[:]
            pdata += b"\x00\x00\x00\x00\x00\x00"
        Logger.error(
            "Starting 0x%02X 0x%02X 0x%02X 0x%02X 0x%02X 0x%02X\n"
            % (pdata[0], pdata[1], pdata[2], pdata[3], pdata[4], pdata[5])
        )

    def reduce_to_single_packet(self, extra=None):
        if len(self.data) <= 0:
            # Need some data
            return ("STOP", extra)

        # Reduce to packet data and clear data for next packet
        packet_data = self.data[:]
        self.data = b""
        return (packet_data, extra)
