#!/usr/bin/env python3

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

import sys
import struct
from .accessor import Accessor


class BinaryAccessor(Accessor):
    # Constants for python struct packing directives
    PACK_8_BIT_INT = "b"
    PACK_8_BIT_UINT = "B"
    PACK_BIG_ENDIAN_16_BIT_INT = ">h"
    PACK_LITTLE_ENDIAN_16_BIT_INT = "<h"
    PACK_BIG_ENDIAN_16_BIT_UINT = ">H"
    PACK_LITTLE_ENDIAN_16_BIT_UINT = "<H"
    PACK_BIG_ENDIAN_32_BIT_INT = ">i"
    PACK_LITTLE_ENDIAN_32_BIT_INT = "<i"
    PACK_NATIVE_32_BIT_UINT = "=I"
    PACK_BIG_ENDIAN_32_BIT_UINT = ">I"
    PACK_LITTLE_ENDIAN_32_BIT_UINT = "<I"
    PACK_BIG_ENDIAN_64_BIT_INT = ">q"
    PACK_LITTLE_ENDIAN_64_BIT_INT = "<q"
    PACK_BIG_ENDIAN_64_BIT_UINT = ">Q"
    PACK_LITTLE_ENDIAN_64_BIT_UINT = "<Q"
    PACK_BIG_ENDIAN_32_BIT_FLOAT = ">f"
    PACK_LITTLE_ENDIAN_32_BIT_FLOAT = "<f"
    PACK_BIG_ENDIAN_64_BIT_FLOAT = ">d"
    PACK_LITTLE_ENDIAN_64_BIT_FLOAT = "<d"
    MIN_INT8 = -128
    MAX_INT8 = 127
    MAX_UINT8 = 255
    MIN_INT16 = -32768
    MAX_INT16 = 32767
    MAX_UINT16 = 65535
    MIN_INT32 = -(2**31)
    MAX_INT32 = (2**31) - 1
    MAX_UINT32 = (2**32) - 1
    MIN_INT64 = -(2**63)
    MAX_INT64 = (2**63) - 1
    MAX_UINT64 = (2**64) - 1

    # Additional Constants
    ZERO_STRING = "\000"

    # Valid data types
    DATA_TYPES = ["INT", "UINT", "FLOAT", "STRING", "BLOCK"]

    # Valid overflow types
    OVERFLOW_TYPES = ["TRUNCATE", "SATURATE", "ERROR", "ERROR_ALLOW_HEX"]

    # Determines the endianness of the host running this code
    #
    # This method is protected to force the use of the constant
    # HOST_ENDIANNESS rather than this method
    #
    # @return [Symbol] 'BIG_ENDIAN' or 'LITTLE_ENDIAN'
    @classmethod
    def get_host_endianness(cls):
        value = 0x01020304
        packed = struct.pack(BinaryAccessor.PACK_NATIVE_32_BIT_UINT, value)
        unpacked = struct.unpack(BinaryAccessor.PACK_LITTLE_ENDIAN_32_BIT_UINT, packed)
        if unpacked == value:
            return "LITTLE_ENDIAN"
        else:
            return "BIG_ENDIAN"

    @classmethod
    def raise_buffer_error(
        cls, read_write, buffer, data_type, given_bit_offset, given_bit_size
    ):
        raise AttributeError(
            f"{len(buffer)} byte buffer insufficient to {read_write} {data_type} at bit_offset {given_bit_offset} with bit_size {given_bit_size}"
        )

    # Valid endianess
    ENDIANNESS = ["BIG_ENDIAN", "LITTLE_ENDIAN"]

    @classmethod
    def read_item(cls, item, buffer):
        if item.data_type == "DERIVED":
            return None
        if item.array_size:
            return cls.read_array(
                item.bit_offset,
                item.bit_size,
                item.data_type,
                item.array_size,
                buffer,
                item.endianness,
            )
        else:
            return cls.read(
                item.bit_offset, item.bit_size, item.data_type, buffer, item.endianness
            )

    @classmethod
    def write_item(cls, item, value, buffer):
        if item.data_type == "DERIVED":
            return None
        if item.array_size:
            return cls.write_array(
                value,
                item.bit_offset,
                item.bit_size,
                item.data_type,
                item.array_size,
                buffer,
                item.endianness,
                item.overflow,
            )
        else:
            return cls.write(
                value,
                item.bit_offset,
                item.bit_size,
                item.data_type,
                buffer,
                item.endianness,
                item.overflow,
            )

    # Reads binary data of any data type from a buffer
    #
    # @param bit_offset [Integer] Bit offset to the start of the item. A
    #   negative number means to offset from the  of the buffer.
    # @param bit_size [Integer] Size of the item in bits
    # @param data_type [Symbol] {DATA_TYPES}
    # @param buffer [String] Binary string buffer to read from
    # @param endianness [Symbol] {ENDIANNESS}
    # @return [Integer] value read from the buffer
    @classmethod
    def read(cls, bit_offset, bit_size, data_type, buffer, endianness):
        given_bit_offset = bit_offset
        given_bit_size = bit_size

        bit_offset = cls.check_bit_offset_and_size(
            "read", given_bit_offset, given_bit_size, data_type, buffer
        )

        # If passed a negative bit size with strings or blocks
        # recalculate based on the buffer length
        if (bit_size <= 0) and ((data_type == "STRING") or (data_type == "BLOCK")):
            bit_size = (len(buffer) * 8) - bit_offset + bit_size
            if bit_size == 0:
                return ""
            elif bit_size < 0:
                cls.raise_buffer_error(
                    "read", buffer, data_type, given_bit_offset, given_bit_size
                )

        result, lower_bound, upper_bound = cls.check_bounds_and_buffer_size(
            bit_offset, bit_size, len(buffer), endianness, data_type
        )
        if not result:
            cls.raise_buffer_error(
                "read", buffer, data_type, given_bit_offset, given_bit_size
            )

        if (data_type == "STRING") or (data_type == "BLOCK"):
            #######################################
            # Handle 'STRING' and 'BLOCK' data types
            #######################################

            if cls.byte_aligned(bit_offset):
                if data_type == "STRING":
                    buffer = buffer[lower_bound : (upper_bound + 1)]
                    try:
                        return buffer[: buffer.index(b"\00")]
                    except ValueError:
                        return buffer
                else:  # BLOCK
                    return buffer[lower_bound : upper_bound + 1]

            else:
                raise AttributeError(
                    f"bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"
                )

        elif (data_type == "INT") or (data_type == "UINT"):
            ###################################
            # Handle 'INT' and 'UINT' data types
            ###################################

            if cls.byte_aligned(bit_offset) and cls.even_bit_size(bit_size):
                if data_type == "INT":
                    ###########################################################
                    # Handle byte-aligned 8, 16, 32, and 64 bit 'INT'
                    ###########################################################

                    match bit_size:
                        case 8:
                            return struct.unpack(
                                BinaryAccessor.PACK_8_BIT_INT,
                                buffer[lower_bound : lower_bound + 1],
                            )[0]
                        case 16:
                            if endianness == "BIG_ENDIAN":
                                return struct.unpack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_16_BIT_INT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]
                            else:  # endianness == 'LITTLE_ENDIAN'
                                return struct.unpack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_16_BIT_INT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]

                        case 32:
                            if endianness == "BIG_ENDIAN":
                                return struct.unpack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_32_BIT_INT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]
                            else:  # endianness == 'LITTLE_ENDIAN'
                                return struct.unpack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_32_BIT_INT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]

                        case 64:
                            if endianness == "BIG_ENDIAN":
                                return struct.unpack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_64_BIT_INT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]
                            else:  # endianness == 'LITTLE_ENDIAN'
                                return struct.unpack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_64_BIT_INT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]

                else:  # data_type == 'UINT'
                    ###########################################################
                    # Handle byte-aligned 8, 16, 32, and 64 bit 'UINT'
                    ###########################################################

                    match bit_size:
                        case 8:
                            return struct.unpack(
                                BinaryAccessor.PACK_8_BIT_UINT,
                                buffer[lower_bound : lower_bound + 1],
                            )[0]
                        case 16:
                            if endianness == "BIG_ENDIAN":
                                return struct.unpack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_16_BIT_UINT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]
                            else:  # endianness == 'LITTLE_ENDIAN'
                                return struct.unpack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_16_BIT_UINT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]

                        case 32:
                            if endianness == "BIG_ENDIAN":
                                return struct.unpack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_32_BIT_UINT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]
                            else:  # endianness == 'LITTLE_ENDIAN'
                                return struct.unpack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_32_BIT_UINT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]

                        case 64:
                            if endianness == "BIG_ENDIAN":
                                return struct.unpack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_64_BIT_UINT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]
                            else:  # endianness == 'LITTLE_ENDIAN'
                                return struct.unpack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_64_BIT_UINT,
                                    buffer[lower_bound : upper_bound + 1],
                                )[0]

            else:
                ##########################
                # Handle 'INT' and 'UINT' Bitfields
                ##########################

                # Extract Data for Bitfield
                if endianness == "LITTLE_ENDIAN":
                    # Bitoffset always refers to the most significant bit of a bitfield
                    num_bytes = int((((bit_offset % 8) + bit_size - 1) / 8) + 1)
                    upper_bound = int(bit_offset / 8)
                    lower_bound = upper_bound - num_bytes + 1

                    if lower_bound < 0:
                        raise AttributeError(
                            f"LITTLE_ENDIAN bitfield with bit_offset {given_bit_offset} and bit_size {given_bit_size} is invalid"
                        )
                    temp_lower = lower_bound - 1 if lower_bound > 0 else lower_bound
                    temp_data = buffer[upper_bound : temp_lower or None : -1]
                else:
                    temp_data = buffer[lower_bound : upper_bound + 1]

                # Determine temp upper bound
                temp_upper = upper_bound - lower_bound

                # Handle Bitfield
                start_bits = bit_offset % 8
                start_mask = ~(0xFF << (8 - start_bits))
                total_bits = (temp_upper + 1) * 8
                right_shift = total_bits - start_bits - bit_size

                # Mask off unwanted bits at beginning
                temp = temp_data[0] & start_mask

                if upper_bound > lower_bound:
                    # Combine bytes into a FixNum
                    for temp_value in temp_data[1 : (temp_upper + 1)]:
                        temp = temp << 8
                        temp = temp + temp_value

                # Shift off unwanted bits at end
                temp = temp >> right_shift
                if data_type == "INT":
                    # Convert to negative if necessary
                    if (bit_size > 1) and (temp & (1 << (bit_size - 1))):
                        temp = -((1 << bit_size) - temp)
                return temp

        elif data_type == "FLOAT":
            ##########################
            # Handle 'FLOAT' data type
            ##########################

            if cls.byte_aligned(bit_offset):
                match bit_size:
                    case 32:
                        if endianness == "BIG_ENDIAN":
                            return struct.unpack(
                                BinaryAccessor.PACK_BIG_ENDIAN_32_BIT_FLOAT,
                                buffer[lower_bound : upper_bound + 1],
                            )[0]
                        else:  # endianness == 'LITTLE_ENDIAN'
                            return struct.unpack(
                                BinaryAccessor.PACK_LITTLE_ENDIAN_32_BIT_FLOAT,
                                buffer[lower_bound : upper_bound + 1],
                            )[0]

                    case 64:
                        if endianness == "BIG_ENDIAN":
                            return struct.unpack(
                                BinaryAccessor.PACK_BIG_ENDIAN_64_BIT_FLOAT,
                                buffer[lower_bound : upper_bound + 1],
                            )[0]
                        else:  # endianness == 'LITTLE_ENDIAN'
                            return struct.unpack(
                                BinaryAccessor.PACK_LITTLE_ENDIAN_64_BIT_FLOAT,
                                buffer[lower_bound : upper_bound + 1],
                            )[0]

                    case _:
                        raise AttributeError(
                            f"bit_size is {given_bit_size} but must be 32 or 64 for data_type {data_type}"
                        )

            else:
                raise AttributeError(
                    f"bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"
                )

        else:
            ############################
            # Handle Unknown data types
            ############################
            raise AttributeError(f"data_type {data_type} is not recognized")

    # Writes binary data of any data type to a buffer
    #
    # @param value [Varies] Value to write into the buffer
    # @param bit_offset [Integer] Bit offset to the start of the item. A
    #   negative number means to offset from the  of the buffer.
    # @param bit_size [Integer] Size of the item in bits
    # @param data_type [Symbol] {DATA_TYPES}
    # @param buffer [String] Binary string buffer to write to
    # @param endianness [Symbol] {ENDIANNESS}
    # @param overflow [Symbol] {OVERFLOW_TYPES}
    # @return [Integer] value passed in as a parameter
    @classmethod
    def write(
        cls, value, bit_offset, bit_size, data_type, buffer, endianness, overflow
    ):
        given_bit_offset = bit_offset
        given_bit_size = bit_size

        bit_offset = cls.check_bit_offset_and_size(
            "write", given_bit_offset, given_bit_size, data_type, buffer
        )

        # If passed a negative bit size with strings or blocks
        # recalculate based on the value length in bytes
        if (bit_size <= 0) and ((data_type == "STRING") or (data_type == "BLOCK")):
            bit_size = len(value) * 8

        result, lower_bound, upper_bound = cls.check_bounds_and_buffer_size(
            bit_offset, bit_size, len(buffer), endianness, data_type
        )
        if not result and (given_bit_size > 0):
            cls.raise_buffer_error(
                "write", buffer, data_type, given_bit_offset, given_bit_size
            )

        # Check overflow type
        if (
            (overflow != "TRUNCATE")
            and (overflow != "SATURATE")
            and (overflow != "ERROR")
            and (overflow != "ERROR_ALLOW_HEX")
        ):
            raise AttributeError(f"unknown overflow type {overflow}")

        if (data_type == "STRING") or (data_type == "BLOCK"):
            #######################################
            # Handle 'STRING' and 'BLOCK' data types
            #######################################

            if cls.byte_aligned(bit_offset):
                temp = value
                if given_bit_size <= 0:
                    end_bytes = -int(given_bit_size / 8)
                    old_upper_bound = len(buffer) - 1 - end_bytes
                    # Lower bound + end_bytes can never be more than 1 byte outside of the given buffer
                    if (lower_bound + end_bytes) > len(buffer):
                        cls.raise_buffer_error(
                            "write", buffer, data_type, given_bit_offset, given_bit_size
                        )

                    if old_upper_bound < lower_bound:
                        # String was completely empty
                        if end_bytes > 0:
                            # Preserve bytes at end of buffer
                            buffer += b"\00" * len(value)
                            lower_index = lower_bound + len(value)
                            buffer[lower_index : lower_index + end_bytes] = buffer[
                                lower_bound : lower_bound + end_bytes
                            ]

                    elif bit_size == 0:
                        # Remove entire string
                        buffer[lower_bound : old_upper_bound + 1] = bytearray(b"")
                    elif upper_bound < old_upper_bound:
                        # Remove extra bytes from old string
                        buffer[upper_bound + 1 : old_upper_bound + 1] = bytearray(b"")
                    elif (upper_bound > old_upper_bound) and (end_bytes > 0):
                        # Preserve bytes at end of buffer
                        diff = upper_bound - old_upper_bound
                        buffer += b"\00" * diff
                        buffer[upper_bound + 1 : upper_bound + 1 + end_bytes] = buffer[
                            old_upper_bound + 1 : old_upper_bound + 1 + end_bytes
                        ]

                else:  # given_bit_size > 0
                    byte_size = int(bit_size / 8)
                    if len(value) < byte_size:
                        # Pad the requested size with zeros
                        temp = value.ljust(byte_size, b"\00")
                    elif len(value) > byte_size:
                        if overflow == "TRUNCATE":
                            # Resize the value to fit the field
                            temp = value[0:byte_size]
                        else:
                            raise AttributeError(
                                f"value of {len(value)} bytes does not fit into {byte_size} bytes for data_type {data_type}"
                            )

                if bit_size != 0:
                    buffer[lower_bound : lower_bound + len(temp)] = temp
            else:
                raise AttributeError(
                    f"bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"
                )

        elif (data_type == "INT") or (data_type == "UINT"):
            ###################################
            # Handle 'INT' data type
            ###################################
            value = int(value)
            min_value, max_value, hex_max_value = cls.get_check_overflow_ranges(
                bit_size, data_type
            )
            value = cls.check_overflow(
                value,
                min_value,
                max_value,
                hex_max_value,
                bit_size,
                data_type,
                overflow,
            )

            if cls.byte_aligned(bit_offset) and cls.even_bit_size(bit_size):
                ###########################################################
                # Handle byte-aligned 8, 16, 32, and 64 bit
                ###########################################################

                if data_type == "INT":
                    ###########################################################
                    # Handle byte-aligned 8, 16, 32, and 64 bit 'INT'
                    ###########################################################
                    match bit_size:
                        case 8:
                            buffer[lower_bound : lower_bound + 1] = struct.pack(
                                BinaryAccessor.PACK_8_BIT_INT,
                                value,
                            )
                        case 16:
                            if endianness == "BIG_ENDIAN":
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_16_BIT_INT,
                                    value,
                                )
                            else:  # endianness == 'LITTLE_ENDIAN'
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_16_BIT_INT,
                                    value,
                                )
                        case 32:
                            if endianness == "BIG_ENDIAN":
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_32_BIT_INT,
                                    value,
                                )
                            else:  # endianness == 'LITTLE_ENDIAN'
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_32_BIT_INT,
                                    value,
                                )

                        case 64:
                            if endianness == "BIG_ENDIAN":
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_64_BIT_INT,
                                    value,
                                )
                            else:  # endianness == 'LITTLE_ENDIAN'
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_64_BIT_INT,
                                    value,
                                )

                else:  # data_type == 'UINT'
                    ###########################################################
                    # Handle byte-aligned 8, 16, 32, and 64 bit 'UINT'
                    ###########################################################

                    match bit_size:
                        case 8:
                            buffer[lower_bound : lower_bound + 1] = struct.pack(
                                BinaryAccessor.PACK_8_BIT_UINT,
                                value,
                            )
                            # TODO: Equivalent:?
                            # buffer[lower_bound] = value
                        case 16:
                            if endianness == "BIG_ENDIAN":
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_16_BIT_UINT,
                                    value,
                                )
                            else:  # endianness == 'LITTLE_ENDIAN'
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_16_BIT_UINT,
                                    value,
                                )

                        case 32:
                            if endianness == "BIG_ENDIAN":
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_32_BIT_UINT,
                                    value,
                                )
                            else:  # endianness == 'LITTLE_ENDIAN'
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_32_BIT_UINT,
                                    value,
                                )

                        case 64:
                            if endianness == "BIG_ENDIAN":
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_BIG_ENDIAN_64_BIT_UINT,
                                    value,
                                )
                            else:  # endianness == 'LITTLE_ENDIAN'
                                buffer[lower_bound : upper_bound + 1] = struct.pack(
                                    BinaryAccessor.PACK_LITTLE_ENDIAN_64_BIT_UINT,
                                    value,
                                )

            else:
                ###########################################################
                # Handle bit fields
                ###########################################################

                # Extract Existing Data
                if endianness == "LITTLE_ENDIAN":
                    # Bitoffset always refers to the most significant bit of a bitfield
                    num_bytes = int(((bit_offset % 8) + bit_size - 1) / 8) + 1
                    upper_bound = int(bit_offset / 8)
                    lower_bound = upper_bound - num_bytes + 1
                    if lower_bound < 0:
                        raise AttributeError(
                            f"LITTLE_ENDIAN bitfield with bit_offset {given_bit_offset} and bit_size {given_bit_size} is invalid"
                        )

                    temp_lower = lower_bound - 1 if lower_bound > 0 else lower_bound
                    temp_data = buffer[upper_bound : temp_lower or None : -1]
                else:
                    temp_data = buffer[lower_bound : upper_bound + 1]

                # Determine temp upper bound
                temp_upper = upper_bound - lower_bound

                # Determine Values needed to Handle Bitfield
                start_bits = bit_offset % 8
                start_mask = 0xFF << (8 - start_bits)
                total_bits = (temp_upper + 1) * 8
                end_bits = total_bits - start_bits - bit_size
                end_mask = ~(0xFF << end_bits)

                # Add in Start Bits
                temp = int.from_bytes(temp_data[0:1], sys.byteorder) & start_mask

                # Adjust value to correct number of bits
                temp_mask = (2**bit_size) - 1
                temp_value = value & temp_mask

                shift = bit_size - (8 - start_bits)
                # Add in New Data
                if shift < 0:
                    temp = (temp >> -shift) + temp_value
                else:
                    temp = (temp << shift) + temp_value

                # Add in Remainder of Existing Data
                temp = (temp << end_bits) + (temp_data[temp_upper] & end_mask)

                # Extract into an array of bytes
                temp_array = bytearray()
                for _ in range(0, temp_upper + 1):
                    temp_array.insert(0, (temp & 0xFF))
                    temp = temp >> 8

                # Store into data
                if endianness == "LITTLE_ENDIAN":
                    temp_lower = lower_bound - 1 if lower_bound > 0 else lower_bound
                    temp_array.reverse()
                    # buffer[upper_bound : temp_lower or None : -1] = struct.pack(
                    buffer[lower_bound : upper_bound + 1] = struct.pack(
                        f"{len(temp_array)}{BinaryAccessor.PACK_8_BIT_UINT}",
                        *temp_array,
                    )
                else:
                    buffer[lower_bound : upper_bound + 1] = struct.pack(
                        f"{len(temp_array)}{BinaryAccessor.PACK_8_BIT_UINT}",
                        *temp_array,
                    )

        elif data_type == "FLOAT":
            ##########################
            # Handle 'FLOAT' data type
            ##########################
            value = float(value)

            if cls.byte_aligned(bit_offset):
                match bit_size:
                    case 32:
                        if endianness == "BIG_ENDIAN":
                            buffer[lower_bound:upper_bound] = struct.pack(
                                BinaryAccessor.PACK_BIG_ENDIAN_32_BIT_FLOAT, value
                            )
                        else:  # endianness == 'LITTLE_ENDIAN'
                            buffer[lower_bound:upper_bound] = struct.pack(
                                BinaryAccessor.PACK_LITTLE_ENDIAN_32_BIT_FLOAT, value
                            )
                    case 64:
                        if endianness == "BIG_ENDIAN":
                            buffer[lower_bound:upper_bound] = struct.pack(
                                BinaryAccessor.PACK_BIG_ENDIAN_64_BIT_FLOAT, value
                            )
                        else:  # endianness == 'LITTLE_ENDIAN'
                            buffer[lower_bound:upper_bound] = struct.pack(
                                BinaryAccessor.PACK_LITTLE_ENDIAN_64_BIT_FLOAT, value
                            )
                    case _:
                        raise AttributeError(
                            f"bit_size is {given_bit_size} but must be 32 or 64 for data_type {data_type}"
                        )
            else:
                raise AttributeError(
                    f"bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"
                )

        else:
            ############################
            # Handle Unknown data types
            ############################

            raise AttributeError(f"data_type {data_type} is not recognized")

        return value

    # Check the bit size and bit offset for problems. Recalulate the bit offset
    # and return back through the passed in pointer.
    @classmethod
    def check_bit_offset_and_size(
        cls, read_or_write, given_bit_offset, given_bit_size, data_type, buffer
    ):
        bit_offset = given_bit_offset

        if (given_bit_size <= 0) and (data_type != "STRING") and (data_type != "BLOCK"):
            raise AttributeError(
                f"bit_size {given_bit_size} must be positive for data types other than 'STRING' and 'BLOCK'"
            )

        if (given_bit_size <= 0) and (given_bit_offset < 0):
            raise AttributeError(
                f"negative or zero bit_sizes ({given_bit_size}) cannot be given with negative bit_offsets ({given_bit_offset})"
            )

        if given_bit_offset < 0:
            bit_offset = (len(buffer) * 8) + bit_offset
            if bit_offset < 0:
                cls.raise_buffer_error(
                    read_or_write, buffer, data_type, given_bit_offset, given_bit_size
                )

        return bit_offset

    # Calculate the bounds of the string to access the item based on the bit_offset and bit_size.
    # Also determine if the buffer size is sufficient.
    @classmethod
    def check_bounds_and_buffer_size(
        cls, bit_offset, bit_size, buffer_length, endianness, data_type
    ):
        result = True  # Assume ok

        # Define bounds of string to access this item
        lower_bound = int(bit_offset / 8)
        upper_bound = int((bit_offset + bit_size - 1) / 8)

        # Sanity check buffer size
        if upper_bound >= buffer_length:
            # If it's not the special match of little endian bit field then we fail and return false
            if not (
                (endianness == "LITTLE_ENDIAN")
                and ((data_type == "INT") or (data_type == "UINT"))
                and (
                    # Not byte aligned with an even bit size
                    not (
                        (cls.byte_aligned(bit_offset)) and (cls.even_bit_size(bit_size))
                    )
                )
                and (lower_bound < buffer_length)
            ):
                result = False

        return result, lower_bound, upper_bound

    @classmethod
    def get_check_overflow_ranges(cls, bit_size, data_type):
        min_value = 0  # Default for UINT cases

        match bit_size:
            case 8:
                hex_max_value = BinaryAccessor.MAX_UINT8
                if data_type == "INT":
                    min_value = BinaryAccessor.MIN_INT8
                    max_value = BinaryAccessor.MAX_INT8
                else:
                    max_value = BinaryAccessor.MAX_UINT8

            case 16:
                hex_max_value = BinaryAccessor.MAX_UINT16
                if data_type == "INT":
                    min_value = BinaryAccessor.MIN_INT16
                    max_value = BinaryAccessor.MAX_INT16
                else:
                    max_value = BinaryAccessor.MAX_UINT16

            case 32:
                hex_max_value = BinaryAccessor.MAX_UINT32
                if data_type == "INT":
                    min_value = BinaryAccessor.MIN_INT32
                    max_value = BinaryAccessor.MAX_INT32
                else:
                    max_value = BinaryAccessor.MAX_UINT32

            case 64:
                hex_max_value = BinaryAccessor.MAX_UINT64
                if data_type == "INT":
                    min_value = BinaryAccessor.MIN_INT64
                    max_value = BinaryAccessor.MAX_INT64
                else:
                    max_value = BinaryAccessor.MAX_UINT64

            case _:  # Bitfield
                if data_type == "INT":
                    # Note signed integers must allow up to the maximum unsigned value to support values given in hex
                    if bit_size > 1:
                        max_value = 2 ** (bit_size - 1)
                        # min_value = -(2 ** bit_size - 1)
                        min_value = -max_value
                        # max_value = (2 ** bit_size - 1) - 1
                        max_value -= 1
                        # hex_max_value = (2 ** bit_size) - 1
                        hex_max_value = (2**bit_size) - 1
                    else:  # 1-bit signed
                        min_value = -1
                        max_value = 1
                        hex_max_value = 1

                else:
                    max_value = (2**bit_size) - 1
                    hex_max_value = max_value

        return min_value, max_value, hex_max_value

    @classmethod
    def byte_aligned(cls, value):
        return (value % 8) == 0

    @classmethod
    def even_bit_size(cls, bit_size):
        return (
            (bit_size == 8) or (bit_size == 16) or (bit_size == 32) or (bit_size == 64)
        )

    #   # Reads an array of binary data of any data type from a buffer
    #   #
    #   # @param bit_offset [Integer] Bit offset to the start of the array. A
    #   #   negative number means to offset from the  of the buffer.
    #   # @param bit_size [Integer] Size of each item in the array in bits
    #   # @param data_type [Symbol] {DATA_TYPES}
    #   # @param array_size [Integer] Size in bits of the array. 0 or negative means
    #   #   fill the array with as many bit_size number of items that exist (negative
    #   #   means excluding the final X number of bits).
    #   # @param buffer [String] Binary string buffer to read from
    #   # @param endianness [Symbol] {ENDIANNESS}
    #   # @return [Array] Array created from reading the buffer
    #   def self.read_array(bit_offset, bit_size, data_type, array_size, buffer, endianness)
    #     # Save given values of bit offset, bit size, and array_size
    #     given_bit_offset = bit_offset
    #     given_bit_size = bit_size
    #     given_array_size = array_size

    #     # Handle negative and zero bit sizes
    #     raise ArgumentError, "bit_size {given_bit_size} must be positive for arrays" if bit_size <= 0

    #     # Handle negative bit offsets
    #     if bit_offset < 0
    #       bit_offset = ((len(buffer) * 8) + bit_offset)
    #       raise_buffer_error('read', buffer, data_type, given_bit_offset, given_bit_size) if bit_offset < 0

    #     # Handle negative and zero array sizes
    #     if array_size <= 0
    #       if given_bit_offset < 0
    #         raise ArgumentError, "negative or zero array_size ({given_array_size}) cannot be given with negative bit_offset ({given_bit_offset})"
    #       else:
    #         array_size = ((len(buffer) * 8) - bit_offset + array_size)
    #         if array_size == 0
    #           return []
    #         elif array_size < 0
    #           raise_buffer_error('read', buffer, data_type, given_bit_offset, given_bit_size)

    #     # Calculate number of items in the array
    #     # If there is a remainder then we have a problem
    #     raise ArgumentError, "array_size {given_array_size} not a multiple of bit_size {given_bit_size}" if array_size % bit_size != 0

    #     num_items = array_size / bit_size

    #     # Define bounds of string to access this item
    #     lower_bound = bit_offset / 8
    #     upper_bound = (bit_offset + array_size - 1) / 8

    #     # Check for byte alignment
    #     cls.byte_aligned = ((bit_offset % 8) == 0)

    #     match data_type
    #     case 'STRING', 'BLOCK'
    #       #######################################
    #       # Handle 'STRING' and 'BLOCK' data types
    #       #######################################

    #       if cls.byte_aligned
    #         value = []
    #         num_items.times do
    #           value << self.read(bit_offset, bit_size, data_type, buffer, endianness)
    #           bit_offset += bit_size

    #       else:
    #         raise ArgumentError, "bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"

    #     case 'INT', 'UINT'
    #       ###################################
    #       # Handle 'INT' and 'UINT' data types
    #       ###################################

    #       if cls.byte_aligned and (bit_size == 8 or bit_size == 16 or bit_size == 32 or bit_size == 64)
    #         ###########################################################
    #         # Handle byte-aligned 8, 16, 32, and 64 bit 'INT' and 'UINT'
    #         ###########################################################

    #         match bit_size
    #         case 8
    #           if data_type == 'INT'
    #             value = buffer[lower_bound..upper_bound].unpack(PACK_8_BIT_INT_ARRAY)
    #           else: # data_type == 'UINT'
    #             value = buffer[lower_bound..upper_bound].unpack(PACK_8_BIT_UINT_ARRAY)

    #         case 16
    #           if data_type == 'INT'
    #             if endianness == HOST_ENDIANNESS
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_NATIVE_16_BIT_INT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               temp = self.byte_swap_buffer(buffer[lower_bound..upper_bound], 2)
    #               value = temp.to_s.unpack(PACK_NATIVE_16_BIT_INT_ARRAY)

    #           else: # data_type == 'UINT'
    #             if endianness == 'BIG_ENDIAN'
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_BIG_ENDIAN_16_BIT_UINT_ARRAY)
    #             else: # endianness == 'LITTLE_ENDIAN'
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_LITTLE_ENDIAN_16_BIT_UINT_ARRAY)

    #         case 32
    #           if data_type == 'INT'
    #             if endianness == HOST_ENDIANNESS
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_NATIVE_32_BIT_INT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               temp = self.byte_swap_buffer(buffer[lower_bound..upper_bound], 4)
    #               value = temp.to_s.unpack(PACK_NATIVE_32_BIT_INT_ARRAY)

    #           else: # data_type == 'UINT'
    #             if endianness == 'BIG_ENDIAN'
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_BIG_ENDIAN_32_BIT_UINT_ARRAY)
    #             else: # endianness == 'LITTLE_ENDIAN'
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_LITTLE_ENDIAN_32_BIT_UINT_ARRAY)

    #         case 64
    #           if data_type == 'INT'
    #             if endianness == HOST_ENDIANNESS
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_NATIVE_64_BIT_INT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               temp = self.byte_swap_buffer(buffer[lower_bound..upper_bound], 8)
    #               value = temp.to_s.unpack(PACK_NATIVE_64_BIT_INT_ARRAY)

    #           else: # data_type == 'UINT'
    #             if endianness == HOST_ENDIANNESS
    #               value = buffer[lower_bound..upper_bound].unpack(PACK_NATIVE_64_BIT_UINT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               temp = self.byte_swap_buffer(buffer[lower_bound..upper_bound], 8)
    #               value = temp.to_s.unpack(PACK_NATIVE_64_BIT_UINT_ARRAY)

    #       else:
    #         ##################################
    #         # Handle 'INT' and 'UINT' Bitfields
    #         ##################################
    #         raise ArgumentError, "read_array does not support little endian bit fields with bit_size greater than 1-bit" if endianness == 'LITTLE_ENDIAN' and bit_size > 1

    #         value = []
    #         num_items.times do
    #           value << self.read(bit_offset, bit_size, data_type, buffer, endianness)
    #           bit_offset += bit_size

    #     case 'FLOAT'
    #       ##########################
    #       # Handle 'FLOAT' data type
    #       ##########################

    #       if cls.byte_aligned
    #         match bit_size
    #         case 32
    #           if endianness == 'BIG_ENDIAN'
    #             value = buffer[lower_bound..upper_bound].unpack(PACK_BIG_ENDIAN_32_BIT_FLOAT_ARRAY)
    #           else: # endianness == 'LITTLE_ENDIAN'
    #             value = buffer[lower_bound..upper_bound].unpack(PACK_LITTLE_ENDIAN_32_BIT_FLOAT_ARRAY)

    #         case 64
    #           if endianness == 'BIG_ENDIAN'
    #             value = buffer[lower_bound..upper_bound].unpack(PACK_BIG_ENDIAN_64_BIT_FLOAT_ARRAY)
    #           else: # endianness == 'LITTLE_ENDIAN'
    #             value = buffer[lower_bound..upper_bound].unpack(PACK_LITTLE_ENDIAN_64_BIT_FLOAT_ARRAY)

    #         else:
    #           raise ArgumentError, "bit_size is {given_bit_size} but must be 32 or 64 for data_type {data_type}"

    #       else:
    #         raise ArgumentError, "bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"

    #     else:
    #       ############################
    #       # Handle Unknown data types
    #       ############################

    #       raise ArgumentError, "data_type {data_type} is not recognized"

    #     value
    #    # def read_array

    #   # Writes an array of binary data of any data type to a buffer
    #   #
    #   # @param values [Array] Values to write into the buffer
    #   # @param bit_offset [Integer] Bit offset to the start of the array. A
    #   #   negative number means to offset from the  of the buffer.
    #   # @param bit_size [Integer] Size of each item in the array in bits
    #   # @param data_type [Symbol] {DATA_TYPES}
    #   # @param array_size [Integer] Size in bits of the array as represented in the buffer.
    #   #   Size 0 means to fill the buffer with as many bit_size number of items that exist
    #   #   (negative means excluding the final X number of bits).
    #   # @param buffer [String] Binary string buffer to write to
    #   # @param endianness [Symbol] {ENDIANNESS}
    #   # @return [Array] values passed in as a parameter
    #   def self.write_array(values, bit_offset, bit_size, data_type, array_size, buffer, endianness, overflow)
    #     # Save given values of bit offset, bit size, and array_size
    #     given_bit_offset = bit_offset
    #     given_bit_size = bit_size
    #     given_array_size = array_size

    #     # Verify an array was given
    #     raise ArgumentError, "values must be an Array type class is {values.class}" unless values.kind_of? Array

    #     # Handle negative and zero bit sizes
    #     raise ArgumentError, "bit_size {given_bit_size} must be positive for arrays" if bit_size <= 0

    #     # Handle negative bit offsets
    #     if bit_offset < 0
    #       bit_offset = ((len(buffer) * 8) + bit_offset)
    #       raise_buffer_error('write', buffer, data_type, given_bit_offset, given_bit_size) if bit_offset < 0

    #     # Handle negative and zero array sizes
    #     if array_size <= 0
    #       if given_bit_offset < 0
    #         raise ArgumentError, "negative or zero array_size ({given_array_size}) cannot be given with negative bit_offset ({given_bit_offset})"
    #       else:
    #         end_bytes = -(given_array_size / 8)
    #         lower_bound = bit_offset / 8
    #         upper_bound = (bit_offset + (bit_size * len(values)) - 1) / 8
    #         old_upper_bound = len(buffer) - 1 - end_bytes

    #         if upper_bound < old_upper_bound
    #           # Remove extra bytes from old buffer
    #           buffer[(upper_bound + 1)..old_upper_bound] = ''
    #         elif upper_bound > old_upper_bound
    #           # Grow buffer and preserve bytes at  of buffer if necesssary
    #           buffer_length = len(buffer)
    #           diff = upper_bound - old_upper_bound
    #           buffer << ZERO_STRING * diff
    #           if end_bytes > 0
    #             buffer[(upper_bound + 1)..(len(buffer) - 1)] = buffer[(old_upper_bound + 1)..(buffer_length - 1)]

    #         array_size = ((len(buffer) * 8) - bit_offset + array_size)

    #     # Get data bounds for this array
    #     lower_bound = bit_offset / 8
    #     upper_bound = (bit_offset + array_size - 1) / 8
    #     num_bytes   = upper_bound - lower_bound + 1

    #     # Check for byte alignment
    #     cls.byte_aligned = ((bit_offset % 8) == 0)

    #     # Calculate the number of writes
    #     num_writes = array_size / bit_size
    #     # Check for a negative array_size and adjust the number of writes
    #     # to simply be the number of values in the passed in array
    #     if given_array_size <= 0
    #       num_writes = len(values)

    #     # Ensure the buffer has enough room
    #     if bit_offset + num_writes * bit_size > len(buffer) * 8
    #       raise_buffer_error('write', buffer, data_type, given_bit_offset, given_bit_size)

    #     # Ensure the given_array_size is an even multiple of bit_size
    #     raise ArgumentError, "array_size {given_array_size} not a multiple of bit_size {given_bit_size}" if array_size % bit_size != 0

    #     raise ArgumentError, "too many values {len(values)} for given array_size {given_array_size} and bit_size {given_bit_size}" if num_writes < len(values)

    #     # Check overflow type
    #     raise "unknown overflow type {overflow}" unless OVERFLOW_TYPES.include?(overflow)

    #     match data_type
    #     case 'STRING', 'BLOCK'
    #       #######################################
    #       # Handle 'STRING' and 'BLOCK' data types
    #       #######################################

    #       if cls.byte_aligned
    #         num_writes.times do |index|
    #           self.write(values[index], bit_offset, bit_size, data_type, buffer, endianness, overflow)
    #           bit_offset += bit_size

    #       else:
    #         raise ArgumentError, "bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"

    #     case 'INT', 'UINT'
    #       ###################################
    #       # Handle 'INT' and 'UINT' data types
    #       ###################################

    #       if cls.byte_aligned and (bit_size == 8 or bit_size == 16 or bit_size == 32 or bit_size == 64)
    #         ###########################################################
    #         # Handle byte-aligned 8, 16, 32, and 64 bit 'INT' and 'UINT'
    #         ###########################################################

    #         match bit_size
    #         case 8
    #           if data_type == 'INT'
    #             values = self.check_overflow_array(values, MIN_INT8, MAX_INT8, MAX_UINT8, bit_size, data_type, overflow)
    #             packed = values.pack(PACK_8_BIT_INT_ARRAY)
    #           else: # data_type == 'UINT'
    #             values = self.check_overflow_array(values, 0, MAX_UINT8, MAX_UINT8, bit_size, data_type, overflow)
    #             packed = values.pack(PACK_8_BIT_UINT_ARRAY)

    #         case 16
    #           if data_type == 'INT'
    #             values = self.check_overflow_array(values, MIN_INT16, MAX_INT16, MAX_UINT16, bit_size, data_type, overflow)
    #             if endianness == HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_16_BIT_INT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_16_BIT_INT_ARRAY)
    #               self.byte_swap_buffer!(packed, 2)

    #           else: # data_type == 'UINT'
    #             values = self.check_overflow_array(values, 0, MAX_UINT16, MAX_UINT16, bit_size, data_type, overflow)
    #             if endianness == 'BIG_ENDIAN'
    #               packed = values.pack(PACK_BIG_ENDIAN_16_BIT_UINT_ARRAY)
    #             else: # endianness == 'LITTLE_ENDIAN'
    #               packed = values.pack(PACK_LITTLE_ENDIAN_16_BIT_UINT_ARRAY)

    #         case 32
    #           if data_type == 'INT'
    #             values = self.check_overflow_array(values, MIN_INT32, MAX_INT32, MAX_UINT32, bit_size, data_type, overflow)
    #             if endianness == HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_32_BIT_INT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_32_BIT_INT_ARRAY)
    #               self.byte_swap_buffer!(packed, 4)

    #           else: # data_type == 'UINT'
    #             values = self.check_overflow_array(values, 0, MAX_UINT32, MAX_UINT32, bit_size, data_type, overflow)
    #             if endianness == 'BIG_ENDIAN'
    #               packed = values.pack(PACK_BIG_ENDIAN_32_BIT_UINT_ARRAY)
    #             else: # endianness == 'LITTLE_ENDIAN'
    #               packed = values.pack(PACK_LITTLE_ENDIAN_32_BIT_UINT_ARRAY)

    #         case 64
    #           if data_type == 'INT'
    #             values = self.check_overflow_array(values, MIN_INT64, MAX_INT64, MAX_UINT64, bit_size, data_type, overflow)
    #             if endianness == HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_64_BIT_INT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_64_BIT_INT_ARRAY)
    #               self.byte_swap_buffer!(packed, 8)

    #           else: # data_type == 'UINT'
    #             values = self.check_overflow_array(values, 0, MAX_UINT64, MAX_UINT64, bit_size, data_type, overflow)
    #             if endianness == HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_64_BIT_UINT_ARRAY)
    #             else: # endianness != HOST_ENDIANNESS
    #               packed = values.pack(PACK_NATIVE_64_BIT_UINT_ARRAY)
    #               self.byte_swap_buffer!(packed, 8)

    #         # Adjust packed size to hold number of items written
    #         buffer[lower_bound..upper_bound] = adjust_packed_size(num_bytes, packed) if num_bytes > 0

    #       else:
    #         ##################################
    #         # Handle 'INT' and 'UINT' Bitfields
    #         ##################################

    #         raise ArgumentError, "write_array does not support little endian bit fields with bit_size greater than 1-bit" if endianness == 'LITTLE_ENDIAN' and bit_size > 1

    #         num_writes.times do |index|
    #           self.write(values[index], bit_offset, bit_size, data_type, buffer, endianness, overflow)
    #           bit_offset += bit_size

    #     case 'FLOAT'
    #       ##########################
    #       # Handle 'FLOAT' data type
    #       ##########################

    #       if cls.byte_aligned
    #         match bit_size
    #         case 32
    #           if endianness == 'BIG_ENDIAN'
    #             packed = values.pack(PACK_BIG_ENDIAN_32_BIT_FLOAT_ARRAY)
    #           else: # endianness == 'LITTLE_ENDIAN'
    #             packed = values.pack(PACK_LITTLE_ENDIAN_32_BIT_FLOAT_ARRAY)

    #         case 64
    #           if endianness == 'BIG_ENDIAN'
    #             packed = values.pack(PACK_BIG_ENDIAN_64_BIT_FLOAT_ARRAY)
    #           else: # endianness == 'LITTLE_ENDIAN'
    #             packed = values.pack(PACK_LITTLE_ENDIAN_64_BIT_FLOAT_ARRAY)

    #         else:
    #           raise ArgumentError, "bit_size is {given_bit_size} but must be 32 or 64 for data_type {data_type}"

    #         # Adjust packed size to hold number of items written
    #         buffer[lower_bound..upper_bound] = adjust_packed_size(num_bytes, packed) if num_bytes > 0

    #       else:
    #         raise ArgumentError, "bit_offset {given_bit_offset} is not byte aligned for data_type {data_type}"

    #     else:
    #       ############################
    #       # Handle Unknown data types
    #       ############################
    #       raise ArgumentError, "data_type {data_type} is not recognized"
    #      # match data_type

    #     values
    #    # def write_array

    #   # Adjusts the packed array to be the given number of bytes
    #   #
    #   # @param num_bytes [Integer] The desired number of bytes
    #   # @param packed [Array] The packed data buffer
    #   def self.adjust_packed_size(num_bytes, packed)
    #     difference = num_bytes - len(packed)
    #     if difference > 0
    #       packed << (ZERO_STRING * difference)
    #     elif difference < 0
    #       packed = packed[0..(len(packed) - 1 + difference)]

    #     packed

    #   # Byte swaps every X bytes of data in a buffer overwriting the buffer
    #   #
    #   # @param buffer [String] Buffer to modify
    #   # @param num_bytes_per_word [Integer] Number of bytes per word that will be swapped
    #   # @return [String] buffer passed in as a parameter
    #   def self.byte_swap_buffer!(buffer, num_bytes_per_word)
    #     num_swaps = len(buffer) / num_bytes_per_word
    #     index = 0
    #     num_swaps.times do
    #       range = index..(index + num_bytes_per_word - 1)
    #       buffer[range] = buffer[range].reverse
    #       index += num_bytes_per_word

    #     buffer

    #   # Byte swaps every X bytes of data in a buffer into a new buffer
    #   #
    #   # @param buffer [String] Buffer that will be copied then modified
    #   # @param num_bytes_per_word [Integer] Number of bytes per word that will be swapped
    #   # @return [String] modified buffer
    #   def self.byte_swap_buffer(buffer, num_bytes_per_word)
    #     buffer = buffer.clone
    #     self.byte_swap_buffer!(buffer, num_bytes_per_word)

    # Checks for overflow of an integer data type
    #
    # @param value [Integer] Value to write into the buffer
    # @param min_value [Integer] Minimum allowed value
    # @param max_value [Integer] Maximum allowed value
    # @param hex_max_value [Integer] Maximum allowed value if specified in hex
    # @param bit_size [Integer] Size of the item in bits
    # @param data_type [Symbol] {DATA_TYPES}
    # @param overflow [Symbol] {OVERFLOW_TYPES}
    # @return [Integer] Potentially modified value
    @classmethod
    def check_overflow(
        cls, value, min_value, max_value, hex_max_value, bit_size, data_type, overflow
    ):
        if overflow == "TRUNCATE":
            # Note this will always convert to unsigned equivalent for signed integers. A little weird but it matches the Ruby implementation.
            value = value % (hex_max_value + 1)
            if value > max_value:
                value = min_value
        else:
            if value > max_value:
                if overflow == "SATURATE":
                    value = max_value
                elif overflow == "ERROR" or value > hex_max_value:
                    raise AttributeError(
                        f"value of {value} invalid for {bit_size}-bit {data_type}"
                    )
            elif value < min_value:
                if overflow == "SATURATE":
                    value = min_value
                else:
                    raise AttributeError(
                        f"value of {value} invalid for {bit_size}-bit {data_type}"
                    )
        return value


#   # Checks for overflow of an array of integer data types
#   #
#   # @param values [Array[Integer]] Values to write into the buffer
#   # @param min_value [Integer] Minimum allowed value
#   # @param max_value [Integer] Maximum allowed value
#   # @param hex_max_value [Integer] Maximum allowed value if specified in hex
#   # @param bit_size [Integer] Size of the item in bits
#   # @param data_type [Symbol] {DATA_TYPES}
#   # @param overflow [Symbol] {OVERFLOW_TYPES}
#   # @return [Array[Integer]] Potentially modified values
#   def self.check_overflow_array(values, min_value, max_value, hex_max_value, bit_size, data_type, overflow)
#     if overflow != :TRUNCATE
#       values.each_with_index do |value, index|
#         values[index] = check_overflow(value, min_value, max_value, hex_max_value, bit_size, data_type, overflow)
#     return values


# Store the host endianness so that it only has to be determined once
BinaryAccessor.HOST_ENDIANNESS = BinaryAccessor.get_host_endianness()
