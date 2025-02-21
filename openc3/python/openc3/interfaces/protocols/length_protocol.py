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
from openc3.accessors.binary_accessor import BinaryAccessor


# Protocol which delineates packets using a length field at a fixed
# location in each packet.
class LengthProtocol(BurstProtocol):
    # self.param length_bit_offset [Integer] The bit offset of the length field
    # self.param length_bit_size [Integer] The size in bits of the length field
    # self.param length_value_offset [Integer] The offset to apply to the length
    #   value once it has been read from the packet. The value in the length
    #   field itself plus the length value offset MUST equal the total bytes
    #   including any discarded bytes.
    #   For example= if your length field really means "length - 1" this value should be 1.:
    # self.param length_bytes_per_count [Integer] The number of bytes per each
    #   length field 'count'. This is used if the units of the length field is:
    #   something other than bytes, for example words.
    # self.param length_endianness [String] The endianness of the length field.
    #   Must be either BIG_ENDIAN or LITTLE_ENDIAN.
    # self.param discard_leading_bytes (see BurstProtocol#initialize)
    # self.param sync_pattern (see BurstProtocol#initialize)
    # self.param max_length [Integer] The maximum allowed value of the length field
    # self.param fill_length_and_sync_pattern [Boolean] Fill the length field and sync
    #    pattern when writing packets
    # self.param allow_empty_data [True/False/None] See Protocol#initialize
    def __init__(
        self,
        length_bit_offset=0,
        length_bit_size=16,
        length_value_offset=0,
        length_bytes_per_count=1,
        length_endianness="BIG_ENDIAN",
        discard_leading_bytes=0,
        sync_pattern=None,
        max_length=None,
        fill_length_and_sync_pattern=False,
        allow_empty_data=None,
    ):
        super().__init__(
            discard_leading_bytes,
            sync_pattern,
            fill_length_and_sync_pattern,
            allow_empty_data,
        )

        # Save length field attributes
        self.length_bit_offset = int(length_bit_offset)
        self.length_bit_size = int(length_bit_size)
        self.length_value_offset = int(length_value_offset)
        self.length_bytes_per_count = int(length_bytes_per_count)

        # Save endianness
        if str(length_endianness).upper() == "LITTLE_ENDIAN":
            self.length_endianness = "LITTLE_ENDIAN"
        else:
            self.length_endianness = "BIG_ENDIAN"

        # Derive number of bytes required to contain entire length field
        if self.length_endianness == "BIG_ENDIAN" or ((self.length_bit_offset % 8) == 0):
            length_bits_needed = self.length_bit_offset + self.length_bit_size
            if (length_bits_needed % 8) != 0:
                length_bits_needed += 8
            self.length_bytes_needed = ((length_bits_needed - 1) / 8) + 1
        else:
            self.length_bytes_needed = (length_bit_offset / 8) + 1

        # Save max length setting
        self.max_length = ConfigParser.handle_none(max_length)
        if self.max_length:
            self.max_length = int(self.max_length)

    # Called to perform modifications on a command packet before it is send
    #
    # self.param packet [Packet] Original packet
    # self.return [Packet] Potentially modified packet
    def write_packet(self, packet):
        if self.fill_fields:
            # If the start of the length field is past what we discard, then the
            # length field is inside the packet
            if self.length_bit_offset >= (self.discard_leading_bytes * 8):
                length = self.calculate_length(len(packet.buffer_no_copy()) + self.discard_leading_bytes)
                # Subtract off the discarded bytes since they haven't been added yet
                # Adding bytes happens in the write_data method
                offset = self.length_bit_offset - (self.discard_leading_bytes * 8)
                # Directly write the packet buffer and fill in the length
                BinaryAccessor.write(
                    length,
                    offset,
                    self.length_bit_size,
                    "UINT",
                    packet.buffer_no_copy(),
                    self.length_endianness,
                    "ERROR",
                )
        return super().write_packet(packet)  # Allow burst_protocol to set the sync if needed:

    # Called to perform modifications on write data before making it into a packet
    #
    # self.param data [String] Raw packet data
    # self.return [String] Potentially modified packet data
    def write_data(self, data, extra=None):
        data, extra = super().write_data(data, extra)
        if self.fill_fields:
            # If the start of the length field is before what we discard, then the
            # length field is outside the packet
            if self.length_bit_offset < (self.discard_leading_bytes * 8):
                BinaryAccessor.write(
                    self.calculate_length(len(data)),
                    self.length_bit_offset,
                    self.length_bit_size,
                    "UINT",
                    data,
                    self.length_endianness,
                    "ERROR",
                )
        return (data, extra)

    def calculate_length(self, buffer_length):
        length = int(buffer_length / self.length_bytes_per_count) - self.length_value_offset
        if self.max_length and length > self.max_length:
            raise ValueError(f"Calculated length {length} larger than max_length {self.max_length}")
        return length

    def reduce_to_single_packet(self, extra=None):
        # Make sure we have at least enough data to reach the length field
        if len(self.data) < self.length_bytes_needed:
            return ("STOP", extra)

        # Determine the packet's length
        length = BinaryAccessor.read(
            self.length_bit_offset,
            self.length_bit_size,
            "UINT",
            self.data,
            self.length_endianness,
        )
        if self.max_length and length > self.max_length:
            raise ValueError(f"Length value received larger than max_length= {length} > {self.max_length}")

        packet_length = (length * self.length_bytes_per_count) + self.length_value_offset
        # Ensure the calculated packet length is long enough to support the location of the length field
        # without overlap into the next packet
        if (packet_length * 8) < (self.length_bit_offset + self.length_bit_size):
            raise ValueError(
                f"Calculated packet length of {packet_length * 8} bits < (offset={self.length_bit_offset} + size={self.length_bit_size})"
            )

        # Make sure we have enough data for the packet
        if len(self.data) < packet_length:
            return ("STOP", extra)

        # Reduce to packet data and setup current_data for next packet
        packet_data = self.data[0:packet_length]
        self.data = self.data[packet_length:]

        return (packet_data, extra)
