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

import struct
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.accessors.binary_accessor import BinaryAccessor


class TestBinaryAccessorWrite(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        self.baseline_data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )

    def test_complains_about_unknown_data_types(self):
        self.assertRaisesRegex(
            AttributeError,
            "data_type BLOB is not recognized",
            BinaryAccessor.write,
            0,
            0,
            32,
            "BLOB",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_bit_offsets_before_the_beginning_the_buffer(self):
        self.assertRaisesRegex(
            AttributeError,
            f"{len(self.data)} byte buffer insufficient to write STRING at bit_offset {-((len(self.data) * 8) + 8)} with bit_size 32",
            BinaryAccessor.write,
            "",
            -((len(self.data) * 8) + 8),
            32,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_a_negative_bit_offset_and_zero_bit_size(self):
        self.assertRaisesRegex(
            AttributeError,
            r"negative or zero bit_sizes \(0\) cannot be given with negative bit_offsets \(-8\)",
            BinaryAccessor.write,
            "",
            -8,
            0,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_a_negative_bit_offset_and_negative_bit_size(self):
        self.assertRaisesRegex(
            AttributeError,
            r"negative or zero bit_sizes \(-8\) cannot be given with negative bit_offsets \(-8\)",
            BinaryAccessor.write,
            "",
            -8,
            -8,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_negative_or_zero_bit_sizes_with_data_types_other_than_string_and_block(
        self,
    ):
        self.assertRaisesRegex(
            AttributeError,
            "bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.write,
            0,
            0,
            -8,
            "INT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertRaisesRegex(
            AttributeError,
            "bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.write,
            0,
            0,
            -8,
            "UINT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertRaisesRegex(
            AttributeError,
            "bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.write,
            0,
            0,
            -8,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_writes_aligned_strings(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            expected_data = self.baseline_data[:]
            first_byte_index = int(bit_offset / 8)
            if first_byte_index > 0:
                expected_data[0:first_byte_index] = b"\x00" * first_byte_index

            BinaryAccessor.write(
                self.baseline_data[first_byte_index:],
                bit_offset,
                (len(self.data) * 8) - bit_offset,
                "STRING",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, expected_data)

    def test_writes_variable_length_strings_with_a_zero_and_negative_bit_size(self):
        for bit_size in range(0, -(len(self.baseline_data)) * 8, -8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            expected_data = self.baseline_data[:] + bytearray(
                b"\x00" * -int(bit_size / 8)
            )
            BinaryAccessor.write(
                self.baseline_data,
                0,
                bit_size,
                "STRING",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, expected_data)

    def test_writes_strings_with_bit_offsets(self):
        BinaryAccessor.write(
            self.baseline_data[14:16],
            -16,
            16,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, (b"\x00" * 14) + self.baseline_data[14:16])

    def test_complains_about_unaligned_strings(self):
        self.assertRaisesRegex(
            AttributeError,
            "bit_offset 1 is not byte aligned for data_type STRING",
            BinaryAccessor.write,
            "",
            1,
            32,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_writes_aligned_blocks(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            expected_data = self.baseline_data[:]
            first_byte_index = int(bit_offset / 8)
            if first_byte_index > 0:
                expected_data[0:first_byte_index] = b"\x00" * first_byte_index

            BinaryAccessor.write(
                self.baseline_data[first_byte_index:],
                bit_offset,
                (len(self.data) * 8) - bit_offset,
                "BLOCK",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, expected_data)

    def test_writes_variable_length_blocks_with_a_zero_and_negative_bit_size(self):
        for bit_size in range(0, (-len(self.data)) * 8, -8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            expected_data = self.baseline_data[:] + (b"\x00" * -int(bit_size / 8))
            BinaryAccessor.write(
                self.baseline_data,
                0,
                bit_size,
                "BLOCK",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, expected_data)

    def test_writes_a_block_to_an_empty_buffer(self):
        data = bytearray()
        for index in range(512):
            data += struct.pack(">H", index)
        buffer = bytearray()
        self.assertRaisesRegex(
            AttributeError,
            "0 byte buffer insufficient to write BLOCK at bit_offset 0 with bit_size -16",
            BinaryAccessor.write,
            data,
            0,
            -16,
            "BLOCK",
            buffer,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_handles_a_huge_bit_offset_with_small_buffer(self):
        data = bytearray()
        for index in range(512):
            data += struct.pack(">H", index)
        buffer = bytearray()
        self.assertRaisesRegex(
            AttributeError,
            "0 byte buffer insufficient to write BLOCK at bit_offset 1024 with bit_size 0",
            BinaryAccessor.write,
            data,
            1024,
            0,
            "BLOCK",
            buffer,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_handles_an_edge_case_bit_offset(self):
        data = bytearray()
        for index in range(512):
            data += struct.pack(">H", index)
        buffer = bytearray(b"\x00" * 127)
        self.assertRaisesRegex(
            AttributeError,
            "127 byte buffer insufficient to write BLOCK at bit_offset 1024 with bit_size 0",
            BinaryAccessor.write,
            data,
            1024,
            0,
            "BLOCK",
            buffer,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_writes_a_block_to_a_small_buffer_preserving_the_end(self):
        data = bytearray()
        for index in range(512):
            data += struct.pack(">H", index)
        preserve = struct.pack(">H", 0xBEEF)
        buffer = bytearray(preserve[:])  # Should preserve this
        BinaryAccessor.write(data, 0, -16, "BLOCK", buffer, "BIG_ENDIAN", "ERROR")
        self.assertEqual(buffer[0:-2], data)
        self.assertEqual(buffer[-2:], preserve)
        data = BinaryAccessor.read(0, len(data) * 8 + 16, "BLOCK", buffer, "BIG_ENDIAN")
        self.assertEqual(data, buffer)

    def test_writes_a_block_to_another_small_buffer_preserving_the_end(self):
        data = bytearray()
        for index in range(512):
            data += struct.pack(">H", index)
        preserve = struct.pack(">I", 0xBEEF0123)
        buffer = bytearray(b"\x00\x01") + bytearray(preserve[:])  # Should preserve this
        BinaryAccessor.write(data, 16, -32, "BLOCK", buffer, "BIG_ENDIAN", "ERROR")
        self.assertEqual(buffer[0:2], b"\x00\x01")
        self.assertEqual(buffer[2:-4], data)
        self.assertEqual(buffer[-4:], preserve)
        data = BinaryAccessor.read(
            0, 16 + len(data) * 8 + 32, "BLOCK", buffer, "BIG_ENDIAN"
        )
        self.assertEqual(data, buffer)

    def test_writes_a_block_to_a_small_buffer_overwriting_end(self):
        data = bytearray()
        for index in range(512):
            data += struct.pack(">H", index)
        preserve = struct.pack(">H", 0xBEEF)
        buffer = bytearray(struct.pack(">H", 0xDEAD))
        buffer += bytearray(preserve[:])  # Should preserve this
        BinaryAccessor.write(data, 0, -16, "BLOCK", buffer, "BIG_ENDIAN", "ERROR")
        self.assertEqual(buffer[0:-2], data)
        self.assertEqual(buffer[-2:], preserve)
        data = BinaryAccessor.read(0, len(data) * 8 + 16, "BLOCK", buffer, "BIG_ENDIAN")
        self.assertEqual(data, buffer)

    def test_writes_a_smaller_block_in_the_middle_of_a_buffer(self):
        data = bytearray()
        for index in range(256):
            data += struct.pack(">H", index)
        buffer = bytearray()
        for index in range(512):
            buffer += struct.pack(">H", 0xDEAD)
        expected = buffer[:]
        BinaryAccessor.write(
            data, 128 * 8, -128 * 8, "BLOCK", buffer, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(len(buffer), (128 + 512 + 128))
        self.assertEqual(buffer[0:128], expected[0:128])
        self.assertEqual(buffer[128:-128], data)
        self.assertEqual(buffer[-128:], expected[0:128])

    def test_writes_a_larger_block_in_the_middle_of_a_buffer(self):
        data = bytearray()
        for index in range(256):
            data += struct.pack(">H", index)
        buffer = bytearray()
        for index in range(512):
            buffer += struct.pack(">H", 0xDEAD)
        expected = buffer[:]
        BinaryAccessor.write(
            data, 384 * 8, -384 * 8, "BLOCK", buffer, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(len(buffer), (384 + 512 + 384))
        self.assertEqual(buffer[0:384], expected[0:384])
        self.assertEqual(buffer[384:-384], data)
        self.assertEqual(buffer[-384:], expected[0:384])

    def test_complains_when_the_negative_index_exceeds_the_buffer_length(self):
        data = "\x01"
        buffer = bytearray()
        for _ in range(16):
            buffer += struct.pack(">H", 0xDEAD)

        self.assertRaisesRegex(
            AttributeError,
            "32 byte buffer insufficient to write BLOCK at bit_offset 0 with bit_size -16192",
            BinaryAccessor.write,
            data,
            0,
            -2024 * 8,
            "BLOCK",
            buffer,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_writes_blocks_with_negative_bit_offsets(self):
        BinaryAccessor.write(
            self.baseline_data[0:2], -16, 16, "BLOCK", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data[-2:], self.baseline_data[0:2])

    def test_writes_a_blank_string_with_zero_bit_size(self):
        BinaryAccessor.write("", 0, 0, "STRING", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(self.data, b"")

    def test_writes_a_blank_block_with_zero_bit_size(self):
        BinaryAccessor.write("", 0, 0, "BLOCK", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(self.data, b"")

    def test_writes_a_shorter_string_with_zero_bit_size(self):
        BinaryAccessor.write(
            b"\x00\x00\x00\x00\x00\x00\x00\x00",
            0,
            0,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, b"\x00\x00\x00\x00\x00\x00\x00\x00")

    def test_writes_a_shorter_block_with_zero_bit_size(self):
        BinaryAccessor.write(
            b"\x00\x00\x00\x00\x00\x00\x00\x00",
            0,
            0,
            "BLOCK",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, b"\x00\x00\x00\x00\x00\x00\x00\x00")

    def test_writes_a_shorter_string_and_zero_fill_to_the_given_bit_size(self):
        self.data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )
        BinaryAccessor.write(
            b"\x01\x02\x03\x04\x05\x06\x07\x08",
            0,
            128,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x01\x02\x03\x04\x05\x06\x07\x08\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_a_shorter_block_and_zero_fill_to_the_given_bit_size(self):
        self.data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )
        BinaryAccessor.write(
            b"\x01\x02\x03\x04\x05\x06\x07\x08",
            0,
            128,
            "BLOCK",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x01\x02\x03\x04\x05\x06\x07\x08\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_complains_about_unaligned_blocks(self):
        self.assertRaisesRegex(
            AttributeError,
            "bit_offset 7 is not byte aligned for data_type BLOCK",
            BinaryAccessor.write,
            self.baseline_data,
            7,
            16,
            "BLOCK",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_if_write_exceeds_the_size_of_the_buffer(self):
        self.assertRaisesRegex(
            AttributeError,
            "16 byte buffer insufficient to write STRING at bit_offset 8 with bit_size 800",
            BinaryAccessor.write,
            self.baseline_data,
            8,
            800,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_truncates_the_buffer_for_0_bitsize(self):
        self.assertEqual(len(self.data), 16)
        BinaryAccessor.write(
            b"\x01\x02\x03", 8, 0, "BLOCK", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, b"\x00\x01\x02\x03")
        self.assertEqual(len(self.data), 4)

    def test_expands_the_buffer_for_0_bitsize(self):
        self.assertEqual(len(self.data), 16)
        BinaryAccessor.write(
            b"\x01\x02\x03", (14 * 8), 0, "BLOCK", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03",
        )
        self.assertEqual(len(self.data), 17)

    def test_writes_a_frozen_string(self):
        buffer = bytearray(b"BLANKxxxWORLD")
        string = b"HELLO"
        # Specify 3 more bytes than given to exercise the padding logic
        string = BinaryAccessor.write(
            string, 0, (len(string) + 3) * 8, "STRING", buffer, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(buffer, b"HELLO\x00\x00\x00WORLD")
        self.assertEqual(string, b"HELLO")

    def test_writes_aligned_8_bit_unsigned_integers(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            byte_index = int(bit_offset / 8)
            BinaryAccessor.write(
                self.baseline_data[byte_index],
                bit_offset,
                8,
                "UINT",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(
                self.data[byte_index : byte_index + 1],
                self.baseline_data[byte_index : byte_index + 1],
            )

    def test_writes_aligned_8_bit_signed_integers(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            byte_index = int(bit_offset / 8)
            value = self.baseline_data[byte_index]
            if value >= 128:
                value = value - 256
            BinaryAccessor.write(
                value, bit_offset, 8, "INT", self.data, "BIG_ENDIAN", "ERROR"
            )
            self.assertEqual(
                self.data[byte_index : byte_index + 1],
                self.baseline_data[byte_index : byte_index + 1],
            )

    def test_converts_floats_when_writing_integers(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(1.0, 0, 8, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write(2.5, 8, 8, "INT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write(4.99, 16, 8, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x01\x02\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_converts_integer_strings_when_writing_integers(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write("1", 0, 8, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write("2", 8, 8, "INT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write("4", 16, 8, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x01\x02\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_complains_about_non_integer_strings_when_writing_integers(self):
        self.assertRaises(
            ValueError,
            BinaryAccessor.write,
            "1.0",
            0,
            8,
            "UINT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertRaises(
            ValueError,
            BinaryAccessor.write,
            "abc123",
            0,
            8,
            "UINT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )


class TestBinaryAccessorWriteBigEndian(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        self.baseline_data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )

    def test_writes_1_bit_unsigned_integers(self):
        BinaryAccessor.write(0x1, 8, 1, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write(0x0, 9, 1, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write(0x1, 10, 1, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\xA0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_1_bit_signed_integers(self):
        self.data[1:2] = b"\x55"
        BinaryAccessor.write(0x1, 8, 1, "INT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write(0x0, 9, 1, "INT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write(0x1, 10, 1, "INT", self.data, "BIG_ENDIAN", "ERROR")
        BinaryAccessor.write(0x0, 11, 1, "INT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\xA5\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_7_bit_unsigned_integers(self):
        BinaryAccessor.write(0x40, 8, 7, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(0x20, 3, 7, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_7_bit_signed_integers(self):
        BinaryAccessor.write(-64, 8, 7, "INT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(32, 3, 7, "INT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_13_bit_unsigned_integers(self):
        BinaryAccessor.write(0x1C24, 30, 13, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x00\x00\x03\x84\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(0x0020, 1, 13, "UINT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_13_bit_signed_integers(self):
        BinaryAccessor.write(-988, 30, 13, "INT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x00\x00\x03\x84\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(32, 1, 13, "INT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_aligned_16_bit_unsigned_integers(self):
        expected_array = [
            0x8081,
            0x8283,
            0x8485,
            0x8687,
            0x0009,
            0x0A0B,
            0x0C0D,
            0x0E0F,
        ]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 16):
            BinaryAccessor.write(
                expected_array[index],
                bit_offset,
                16,
                "UINT",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_16_bit_signed_integers(self):
        expected_array = [
            0x8081,
            0x8283,
            0x8485,
            0x8687,
            0x0009,
            0x0A0B,
            0x0C0D,
            0x0E0F,
        ]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 16):
            expected = expected_array[index]
            if expected >= 2**15:
                expected = expected - 2**16
            BinaryAccessor.write(
                expected, bit_offset, 16, "INT", self.data, "BIG_ENDIAN", "ERROR"
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_unsigned_integers(self):
        expected_array = [0x80818283, 0x84858687, 0x00090A0B, 0x0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            BinaryAccessor.write(
                expected_array[index],
                bit_offset,
                32,
                "UINT",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_signed_integers(self):
        expected_array = [0x80818283, 0x84858687, 0x00090A0B, 0x0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            expected = expected_array[index]
            if expected >= 2**31:
                expected = expected - 2**32
            BinaryAccessor.write(
                expected,
                bit_offset,
                32,
                "INT",
                self.data,
                "BIG_ENDIAN",
                "ERROR_ALLOW_HEX",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_negative_integers(self):
        BinaryAccessor.write(
            -2147483648, 0, 32, "INT", self.data, "BIG_ENDIAN", "ERROR_ALLOW_HEX"
        )
        self.assertEqual(
            self.data,
            b"\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_aligned_32_bit_floats(self):
        expected_array = [-1.189360e-038, -3.139169e-036, 8.301067e-040, 1.086646e-031]
        BinaryAccessor.write(
            expected_array[0], 0, 32, "FLOAT", self.data, "BIG_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[1], 32, 32, "FLOAT", self.data, "BIG_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[2], 64, 32, "FLOAT", self.data, "BIG_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[3], 96, 32, "FLOAT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[0],
            38,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(32, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[1],
            36,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[2],
            40,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(96, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[3],
            31,
        )

    def test_writes_37_bit_unsigned_integers(self):
        BinaryAccessor.write(
            0x8182838485 >> 3, 8, 37, "UINT", self.data, "BIG_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            0x00090A0B0C, 67, 37, "UINT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x81\x82\x83\x84\x80\x00\x00\x00\x09\x0A\x0B\x0C\x00\x00\x00",
        )

    def test_writes_37_bit_signed_integers(self):
        BinaryAccessor.write(
            (0x8182838485 >> 3) - 2**37,
            8,
            37,
            "INT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        BinaryAccessor.write(
            0x00090A0B0C, 67, 37, "INT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x81\x82\x83\x84\x80\x00\x00\x00\x09\x0A\x0B\x0C\x00\x00\x00",
        )

    def test_writes_63_bit_unsigned_integers(self):
        self.data[-1:] = b"\xFF"
        BinaryAccessor.write(
            0x8081828384858687 >> 1, 0, 63, "UINT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x80\x81\x82\x83\x84\x85\x86\x86\x00\x00\x00\x00\x00\x00\x00\xFF",
        )
        self.data[0:1] = b"\xFF"
        BinaryAccessor.write(
            0x08090A0B0C0D0E0F, 65, 63, "UINT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\xFF\x81\x82\x83\x84\x85\x86\x86\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F",
        )

    def test_writes_63_bit_signed_integers(self):
        BinaryAccessor.write(
            (0x8081828384858687 >> 1) - 2**63,
            0,
            63,
            "INT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        BinaryAccessor.write(
            0x00090A0B0C0D0E0F, 65, 63, "INT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x80\x81\x82\x83\x84\x85\x86\x86\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F",
        )

    def test_writes_67_bit_unsigned_integers(self):
        BinaryAccessor.write(
            0x8081828384858687FF >> 5, 0, 67, "UINT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x80\x81\x82\x83\x84\x85\x86\x87\xE0\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_67_bit_signed_integers(self):
        BinaryAccessor.write(
            (0x8081828384858687FF >> 5) - 2**67,
            0,
            67,
            "INT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x80\x81\x82\x83\x84\x85\x86\x87\xE0\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_aligned_64_bit_unsigned_integers(self):
        expected_array = [0x8081828384858687, 0x00090A0B0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            BinaryAccessor.write(
                expected_array[index],
                bit_offset,
                64,
                "UINT",
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_signed_integers(self):
        expected_array = [0x8081828384858687, 0x00090A0B0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            expected = expected_array[index]
            if expected >= 2**63:
                expected = expected - 2**64
            BinaryAccessor.write(
                expected,
                bit_offset,
                64,
                "INT",
                self.data,
                "BIG_ENDIAN",
                "ERROR_ALLOW_HEX",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_floats(self):
        expected_array = [-3.116851e-306, 1.257060e-308]
        BinaryAccessor.write(
            expected_array[0], 0, 64, "FLOAT", self.data, "BIG_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[1], 64, 64, "FLOAT", self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 64, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[0],
            306,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 64, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[1],
            308,
        )

    def test_converts_integers_to_floats(self):
        BinaryAccessor.write(1, 0, 32, "FLOAT", self.data, "BIG_ENDIAN", "ERROR")
        value = BinaryAccessor.read(0, 32, "FLOAT", self.data, "BIG_ENDIAN")
        self.assertEqual(value, 1.0)
        BinaryAccessor.write(4, 32, 64, "FLOAT", self.data, "BIG_ENDIAN", "ERROR")
        value = BinaryAccessor.read(32, 64, "FLOAT", self.data, "BIG_ENDIAN")
        self.assertEqual(value, 4.0)

    def test_converts_strings_when_writing_floats(self):
        BinaryAccessor.write("1", 0, 32, "FLOAT", self.data, "BIG_ENDIAN", "ERROR")
        value = BinaryAccessor.read(0, 32, "FLOAT", self.data, "BIG_ENDIAN")
        self.assertEqual(value, 1.0)
        BinaryAccessor.write("4.5", 32, 64, "FLOAT", self.data, "BIG_ENDIAN", "ERROR")
        value = BinaryAccessor.read(32, 64, "FLOAT", self.data, "BIG_ENDIAN")
        self.assertEqual(value, 4.5)

    def test_complains_about_non_float_strings_when_writing_floats(self):
        self.assertRaises(
            ValueError,
            BinaryAccessor.write,
            "abc123",
            0,
            32,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_unaligned_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            "bit_offset 17 is not byte aligned for data_type FLOAT",
            BinaryAccessor.write,
            0.0,
            17,
            32,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )

    def test_complains_about_mis_sized_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            "bit_size is 33 but must be 32 or 64 for data_type FLOAT",
            BinaryAccessor.write,
            0.0,
            0,
            33,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )


class TestBinaryAccessorWriteLittleEndian(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        self.baseline_data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )

    def test_complains_about_ill_defined_little_endian_bitfields(self):
        self.assertRaisesRegex(
            AttributeError,
            "LITTLE_ENDIAN bitfield with bit_offset 3 and bit_size 7 is invalid",
            BinaryAccessor.write,
            0x1,
            3,
            7,
            "UINT",
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )

    def test_writes_1_bit_unsigned_integers(self):
        self.data[1:2] = b"\x55"
        BinaryAccessor.write(0x1, 8, 1, "UINT", self.data, "LITTLE_ENDIAN", "ERROR")
        BinaryAccessor.write(0x0, 9, 1, "UINT", self.data, "LITTLE_ENDIAN", "ERROR")
        BinaryAccessor.write(0x1, 10, 1, "UINT", self.data, "LITTLE_ENDIAN", "ERROR")
        BinaryAccessor.write(0x0, 11, 1, "INT", self.data, "BIG_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\xA5\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_1_bit_signed_integers(self):
        BinaryAccessor.write(0x1, 8, 1, "INT", self.data, "LITTLE_ENDIAN", "ERROR")
        BinaryAccessor.write(0x0, 9, 1, "INT", self.data, "LITTLE_ENDIAN", "ERROR")
        BinaryAccessor.write(0x1, 10, 1, "INT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\xA0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_7_bit_unsigned_integers(self):
        BinaryAccessor.write(0x40, 8, 7, "UINT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(0x7F, 11, 7, "UINT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\xC0\x1F\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_7_bit_signed_integers(self):
        BinaryAccessor.write(-64, 8, 7, "INT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(32, 11, 7, "INT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_13_bit_unsigned_integers(self):
        BinaryAccessor.write(
            0x1C24, 30, 13, "UINT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x80\x84\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(0x0020, 9, 13, "UINT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_13_bit_signed_integers(self):
        BinaryAccessor.write(-988, 30, 13, "INT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x00\x80\x84\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        BinaryAccessor.write(32, 9, 13, "INT", self.data, "LITTLE_ENDIAN", "ERROR")
        self.assertEqual(
            self.data,
            b"\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_aligned_16_bit_unsigned_integers(self):
        expected_array = [
            0x8180,
            0x8382,
            0x8584,
            0x8786,
            0x0900,
            0x0B0A,
            0x0D0C,
            0x0F0E,
        ]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 16):
            BinaryAccessor.write(
                expected_array[index],
                bit_offset,
                16,
                "UINT",
                self.data,
                "LITTLE_ENDIAN",
                "ERROR",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_16_bit_signed_integers(self):
        expected_array = [
            0x8180,
            0x8382,
            0x8584,
            0x8786,
            0x0900,
            0x0B0A,
            0x0D0C,
            0x0F0E,
        ]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 16):
            expected = expected_array[index]
            if expected >= 2**15:
                expected = expected - 2**16
            BinaryAccessor.write(
                expected, bit_offset, 16, "INT", self.data, "LITTLE_ENDIAN", "ERROR"
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_unsigned_integers(self):
        expected_array = [0x83828180, 0x87868584, 0x0B0A0900, 0x0F0E0D0C]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            BinaryAccessor.write(
                expected_array[index],
                bit_offset,
                32,
                "UINT",
                self.data,
                "LITTLE_ENDIAN",
                "ERROR",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_signed_integers(self):
        expected_array = [0x83828180, 0x87868584, 0x0B0A0900, 0x0F0E0D0C]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            expected = expected_array[index]
            if expected >= 2**31:
                expected = expected - 2**32
            BinaryAccessor.write(
                expected,
                bit_offset,
                32,
                "INT",
                self.data,
                "LITTLE_ENDIAN",
                "ERROR_ALLOW_HEX",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_floats(self):
        expected_array = [-7.670445e-037, -2.024055e-034, 2.658460e-032, 7.003653e-030]
        BinaryAccessor.write(
            expected_array[0], 0, 32, "FLOAT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[1], 32, 32, "FLOAT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[2], 64, 32, "FLOAT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[3], 96, 32, "FLOAT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[0],
            37,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(32, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[1],
            34,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[2],
            32,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(96, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[3],
            30,
        )

    def test_writes_37_bit_unsigned_integers(self):
        BinaryAccessor.write(
            0x1584838281, 43, 37, "UINT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            0x0C0B0A0900 >> 3, 96, 37, "UINT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x81\x82\x83\x84\x15\x00\x00\x00\x09\x0A\x0B\x0C\x00\x00\x00",
        )

    def test_writes_37_bit_signed_integers(self):
        BinaryAccessor.write(
            0x1584838281 - 2**37, 43, 37, "INT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            0x0C0B0A0900 >> 3, 96, 37, "INT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x81\x82\x83\x84\x15\x00\x00\x00\x09\x0A\x0B\x0C\x00\x00\x00",
        )

    def test_writes_63_bit_unsigned_integers(self):
        BinaryAccessor.write(
            0x4786858483828180, 57, 63, "UINT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            0x0F0E0D0C0B0A0900 >> 1,
            120,
            63,
            "UINT",
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x80\x81\x82\x83\x84\x85\x86\x47\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F",
        )

    def test_writes_63_bit_signed_integers(self):
        BinaryAccessor.write(
            0x4786858483828180 - 2**63,
            57,
            63,
            "INT",
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )
        BinaryAccessor.write(
            0x0F0E0D0C0B0A0900 >> 1, 120, 63, "INT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x80\x81\x82\x83\x84\x85\x86\x47\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F",
        )

    def test_writes_67_bit_unsigned_integers(self):
        BinaryAccessor.write(
            0x0F0E0D0C0B0A0900FF >> 5,
            120,
            67,
            "UINT",
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x00\x00\x00\x00\x00\x00\x00\xE0\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F",
        )

    def test_writes_67_bit_signed_integers(self):
        BinaryAccessor.write(
            0x0F0E0D0C0B0A0900FF >> 5,
            120,
            67,
            "INT",
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x00\x00\x00\x00\x00\x00\x00\xE0\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F",
        )

    def test_writes_aligned_64_bit_unsigned_integers(self):
        expected_array = [0x8786858483828180, 0x0F0E0D0C0B0A0900]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            BinaryAccessor.write(
                expected_array[index],
                bit_offset,
                64,
                "UINT",
                self.data,
                "LITTLE_ENDIAN",
                "ERROR",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_signed_integers(self):
        expected_array = [0x8786858483828180, 0x0F0E0D0C0B0A0900]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            expected = expected_array[index]
            if expected >= 2**63:
                expected = expected - 2**64
            BinaryAccessor.write(
                expected,
                bit_offset,
                64,
                "INT",
                self.data,
                "LITTLE_ENDIAN",
                "ERROR_ALLOW_HEX",
            )
            index += 1
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_floats(self):
        expected_array = [-2.081577e-272, 3.691916e-236]
        BinaryAccessor.write(
            expected_array[0], 0, 64, "FLOAT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        BinaryAccessor.write(
            expected_array[1], 64, 64, "FLOAT", self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 64, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[0],
            272,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 64, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[1],
            236,
        )

    def test_le_complains_about_unaligned_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            "bit_offset 1 is not byte aligned for data_type FLOAT",
            BinaryAccessor.write,
            0.0,
            1,
            32,
            "FLOAT",
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )

    def test_complains_about_mis_sized_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            "bit_size is 65 but must be 32 or 64 for data_type FLOAT",
            BinaryAccessor.write,
            0.0,
            0,
            65,
            "FLOAT",
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )


class TestBinaryAccessorOverflow(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )

    def test_handles_invalid_overflow_types(self):
        self.assertRaisesRegex(
            AttributeError,
            "unknown overflow type OTHER",
            BinaryAccessor.write,
            b"abcde",
            0,
            32,
            "STRING",
            self.data,
            "BIG_ENDIAN",
            "OTHER",
        )

    def test_prevents_overflow_of_string_and_block(self):
        for type in ["BLOCK", "STRING"]:
            self.assertRaisesRegex(
                AttributeError,
                f"value of 5 bytes does not fit into 4 bytes for data_type {type}",
                BinaryAccessor.write,
                "abcde",
                0,
                32,
                type,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_ints(self):
        for bit_size in [3, 8, 16, 32, 64]:
            for data_type in ["INT", "UINT"]:
                if data_type == "INT":
                    value = 2 ** (bit_size - 1)
                else:
                    value = 2**bit_size
                self.assertRaisesRegex(
                    AttributeError,
                    f"value of {value} invalid for {bit_size}-bit {data_type}",
                    BinaryAccessor.write,
                    value,
                    0,
                    bit_size,
                    data_type,
                    self.data,
                    "BIG_ENDIAN",
                    "ERROR",
                )
                value = -(value + 1)
                self.assertRaisesRegex(
                    AttributeError,
                    f"value of {value} invalid for {bit_size}-bit {data_type}",
                    BinaryAccessor.write,
                    value,
                    0,
                    bit_size,
                    data_type,
                    self.data,
                    "BIG_ENDIAN",
                    "ERROR",
                )

    def test_truncates_string(self):
        BinaryAccessor.write(
            b"abcde", 0, 32, "STRING", self.data, "BIG_ENDIAN", "TRUNCATE"
        )
        self.assertEqual(self.data[0:5], b"abcd\x00")

    def test_truncates_block(self):
        BinaryAccessor.write(
            b"abcde", 0, 32, "BLOCK", self.data, "BIG_ENDIAN", "TRUNCATE"
        )
        self.assertEqual(self.data[0:5], b"abcd\x00")

    def test_truncates_ints(self):
        for bit_size in [3, 5, 8, 16, 32, 64]:
            data_type = "INT"
            value = 2 ** (bit_size - 1)
            truncated_value = -value
            BinaryAccessor.write(
                value, 0, bit_size, data_type, self.data, "BIG_ENDIAN", "TRUNCATE"
            )
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, data_type, self.data, "BIG_ENDIAN"),
                truncated_value,
            )

    def test_truncates_uints(self):
        for bit_size in [3, 5, 8, 16, 32, 64]:
            data_type = "UINT"
            value = 2**bit_size + 1
            truncated_value = 1
            BinaryAccessor.write(
                value, 0, bit_size, data_type, self.data, "BIG_ENDIAN", "TRUNCATE"
            )
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, data_type, self.data, "BIG_ENDIAN"),
                truncated_value,
            )

    def test_saturates_ints(self):
        for bit_size in [3, 5, 8, 16, 32, 64]:
            for data_type in ["INT", "UINT"]:
                if data_type == "UINT":
                    value = 2**bit_size
                else:
                    value = 2 ** (bit_size - 1)
                saturated_value = value - 1
                BinaryAccessor.write(
                    value, 0, bit_size, data_type, self.data, "BIG_ENDIAN", "SATURATE"
                )
                self.assertEqual(
                    BinaryAccessor.read(
                        0, bit_size, data_type, self.data, "BIG_ENDIAN"
                    ),
                    saturated_value,
                )
                if data_type == "UINT":
                    value = -1
                    saturated_value = 0
                else:
                    value = -(value + 1)
                    saturated_value = value + 1
                BinaryAccessor.write(
                    value, 0, bit_size, data_type, self.data, "BIG_ENDIAN", "SATURATE"
                )
                self.assertEqual(
                    BinaryAccessor.read(
                        0, bit_size, data_type, self.data, "BIG_ENDIAN"
                    ),
                    saturated_value,
                )

    # TODO: Is the necessary? This throws struct.error: byte format
    # def test_allows_hex_value_entry_of_int(self):
    #     for bit_size in [3, 5, 8, 16, 32, 64]:
    #         data_type = "INT"
    #         value = 2**bit_size - 1
    #         allowed_value = -1
    #         BinaryAccessor.write(
    #             value,
    #             0,
    #             bit_size,
    #             data_type,
    #             self.data,
    #             "BIG_ENDIAN",
    #             "ERROR_ALLOW_HEX",
    #         )
    #         self.assertEqual(
    #             BinaryAccessor.read(0, bit_size, data_type, self.data, "BIG_ENDIAN"),
    #             allowed_value,
    #         )


class TestBinaryAccessorWriteArray(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        self.data_array = []
        for i in range(len(self.data)):
            self.data_array.append(self.data[i])
        self.baseline_data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )
        self.baseline_data_array = []
        for i in range(len(self.baseline_data)):
            self.baseline_data_array.append(self.baseline_data[i])

    def test_complains_about_value_other_than_array(self):
        with self.assertRaisesRegex(AttributeError, "values must be a list but is str"):
            BinaryAccessor.write_array(
                "", 0, 32, "STRING", 0, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_complains_about_unknown_data_types(self):
        with self.assertRaisesRegex(AttributeError, "data_type BLOB is not recognized"):
            BinaryAccessor.write_array(
                [0], 0, 32, "BLOB", 0, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_complains_about_bit_offsets_before_the_beginning_of_the_buffer(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"{len(self.data)} byte buffer insufficient to write STRING at bit_offset {-((len(self.data) * 8) + 8)} with bit_size 32",
        ):
            BinaryAccessor.write_array(
                [""],
                -((len(self.data) * 8) + 8),
                32,
                "STRING",
                0,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_writes_if_a_negative_bit_offset_is_equal_to_length_of_buffer(self):
        BinaryAccessor.write_array(
            self.baseline_data_array,
            -(len(self.data) * 8),
            8,
            "BLOCK",
            len(self.baseline_data_array) * 8,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_complains_about_a_negative_or_zero_bit_size(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_size 0 must be positive for arrays"
        ):
            BinaryAccessor.write_array(
                [""], 0, 0, "STRING", 0, self.data, "BIG_ENDIAN", "ERROR"
            )
        with self.assertRaisesRegex(
            AttributeError, "bit_size -8 must be positive for arrays"
        ):
            BinaryAccessor.write_array(
                [""], 0, -8, "STRING", 0, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_writes_aligned_strings_with_fixed_array_size(self):
        data = self.data[:]
        BinaryAccessor.write_array(
            self.baseline_data_array,
            0,
            8,
            "STRING",
            len(self.baseline_data_array) * 8,
            data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(data, self.baseline_data)

    def test_writes_aligned_strings_with_zero_array_size(self):
        BinaryAccessor.write_array(
            self.baseline_data_array,
            0,
            8,
            "STRING",
            0,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_strings_with_negative_bit_offsets(self):
        BinaryAccessor.write_array(
            self.baseline_data_array[14:16],
            -16,
            8,
            "STRING",
            16,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, (b"\x00" * 14) + self.baseline_data[14:16])

    def test_complains_about_unaligned_strings(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_offset 1 is not byte aligned for data_type STRING"
        ):
            BinaryAccessor.write_array(
                [], 1, 32, "STRING", 32, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_complains_if_pass_more_values_than_the_given_array_size_can_hold(self):
        with self.assertRaisesRegex(
            AttributeError,
            f"too many values {len(self.baseline_data_array)} for given array_size 32 and bit_size 8",
        ):
            BinaryAccessor.write_array(
                self.baseline_data_array,
                0,
                8,
                "BLOCK",
                32,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_writes_blocks_with_fixed_array_size(self):
        BinaryAccessor.write_array(
            self.baseline_data_array,
            0,
            8,
            "BLOCK",
            len(self.baseline_data_array) * 8,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, self.baseline_data)

    # def test_zeros_fill_if_array_size_greater_number_of_values_passed(self):
    #     data = self.baseline_data[:]
    #     BinaryAccessor.write_array(
    #         [b"\x01", b"\x02", b"\x03", b"\x04"],
    #         0,
    #         8,
    #         "BLOCK",
    #         64,
    #         self.baseline_data,
    #         "BIG_ENDIAN",
    #         "ERROR",
    #     )
    #     self.assertEqual(
    #         self.baseline_data, b"\x01\x02\x03\x04" + (b"\x00" * 4) + data[8:]
    #     )

    # def test_writes_blocks_with_fixed_array_size_at_non_zero_offset(self):
    #     BinaryAccessor.write_array(
    #         self.baseline_data_array[0:-6],
    #         32,
    #         8,
    #         "BLOCK",
    #         len(self.baseline_data_array) * 8 - 32,
    #         self.data,
    #         "BIG_ENDIAN",
    #         "ERROR",
    #     )
    #     self.assertEqual(self.data, (b"\x00" * 4) + self.baseline_data[0:-6])

    def test_writes_blocks_with_zero_array_size(self):
        BinaryAccessor.write_array(
            self.baseline_data_array, 0, 8, "BLOCK", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_blocks_with_negative_bit_offsets(self):
        BinaryAccessor.write_array(
            [b"\x80\x81", b"\x82\x83"],
            -32,
            16,
            "BLOCK",
            32,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, (b"\x00" * 12) + self.baseline_data[0:4])

    def test_complains_with_a_pos_array_size_not_a_multiple_of_bit_size(self):
        with self.assertRaisesRegex(
            AttributeError, "array_size 10 not a multiple of bit_size 8"
        ):
            BinaryAccessor.write_array(
                [1, 2], 0, 8, "UINT", 10, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_complains_with_a_neg_array_size_not_a_multiple_of_bit_size(self):
        with self.assertRaisesRegex(
            AttributeError, "array_size -10 not a multiple of bit_size 8"
        ):
            BinaryAccessor.write_array(
                [1, 2], 0, 8, "UINT", -10, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_excludes_the_remaining_bits_if_array_size_is_negative(self):
        data = self.data[:]
        BinaryAccessor.write_array(
            self.baseline_data_array[0:-4],
            0,
            8,
            "BLOCK",
            -32,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, self.baseline_data[0:-4] + data[-4:])

    def test_does_not_write_if_the_offset_equals_the_negative_array_size(self):
        data = self.data[:]
        BinaryAccessor.write_array(
            [],
            len(self.data) * 8 - 32,
            8,
            "BLOCK",
            -32,
            self.data,
            "LITTLE_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, data)

    def test_expands_the_buffer_to_handle_negative_array_size(self):
        self.data = bytearray(b"\x00\x01\x02\x00\x03")
        BinaryAccessor.write_array(
            [1, 2, 3, 4], 0, 32, "UINT", -8, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00\x04\x03",
        )

    def test_shrinks_the_buffer_when_handling_negative_array_size(self):
        # Start with one array item
        self.data = bytearray(b"\x00\x01\x02\x00\x03")
        # Goto 4 array items array item
        BinaryAccessor.write_array(
            [1, 2, 3, 4], 0, 32, "UINT", -8, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00\x04\x03",
        )
        # Goto 2 array items
        BinaryAccessor.write_array(
            [1, 2], 0, 32, "UINT", -8, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, b"\x00\x00\x00\x01\x00\x00\x00\x02\x03")
        # Goto 0 array items
        BinaryAccessor.write_array(
            [], 0, 32, "UINT", -8, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, b"\x03")
        # Go back to 1 array items
        BinaryAccessor.write_array(
            [1], 0, 32, "UINT", -8, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, b"\x00\x00\x00\x01\x03")

    def test_complain_when_passed_a_zero_length_buffer(self):
        with self.assertRaises(AttributeError):
            BinaryAccessor.write_array(
                [1, 2, 3], 0, 8, "UINT", 32, b"", "LITTLE_ENDIAN", "ERROR"
            )

    def test_expands_the_buffer_if_the_offset_is_greater_than_the_negative_array_size(
        self,
    ):
        offset = len(self.data) * 8 - 16
        data = self.data[:]
        BinaryAccessor.write_array(
            [1, 2], offset, 8, "UINT", -32, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, data[0:-2] + b"\x01\x02" + data[-4:])

    def test_complains_with_negative_bit_offset_and_zero_array_size(self):
        with self.assertRaisesRegex(
            AttributeError,
            r"negative or zero array_size \(0\) cannot be given with negative bit_offset \(-32\)",
        ):
            BinaryAccessor.write_array(
                [1, 2], -32, 8, "UINT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
            )

    def test_complains_with_negative_array_size(self):
        with self.assertRaisesRegex(
            AttributeError,
            r"negative or zero array_size \(-8\) cannot be given with negative bit_offset \(-32\)",
        ):
            BinaryAccessor.write_array(
                [1, 2], -32, 8, "UINT", -8, self.data, "LITTLE_ENDIAN", "ERROR"
            )

    def test_writes_a_shorter_string_and_zero_fill_to_the_given_bit_size(self):
        self.data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )
        BinaryAccessor.write_array(
            [b"\x01\x02", b"\x01\x02", b"\x01\x02", b"\x01\x02"],
            0,
            32,
            "STRING",
            128,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x01\x02\x00\x00\x01\x02\x00\x00\x01\x02\x00\x00\x01\x02\x00\x00",
        )

    def test_writes_a_shorter_block_and_zero_fill_to_the_given_bit_size(self):
        self.data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )
        BinaryAccessor.write_array(
            [b"\x01\x02", b"\x01\x02", b"\x01\x02", b"\x01\x02"],
            0,
            32,
            "BLOCK",
            128,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.data,
            b"\x01\x02\x00\x00\x01\x02\x00\x00\x01\x02\x00\x00\x01\x02\x00\x00",
        )

    def test_complains_about_unaligned_blocks(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_offset 7 is not byte aligned for data_type BLOCK"
        ):
            BinaryAccessor.write_array(
                self.baseline_data_array[0:2],
                7,
                16,
                "BLOCK",
                32,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_complains_if_write_exceeds_the_size_of_the_buffer(self):
        with self.assertRaisesRegex(
            AttributeError,
            "16 byte buffer insufficient to write STRING at bit_offset 8 with bit_size 800",
        ):
            BinaryAccessor.write_array(
                [], 8, 800, "STRING", 800, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_writes_aligned_8_bit_unsigned_integers(self):
        BinaryAccessor.write_array(
            [0, 1, 2, 3, 4, 5, 255, 255],
            0,
            8,
            "UINT",
            0,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, b"\x00\x01\x02\x03\x04\x05\xFF\xFF")

    def test_writes_aligned_8_bit_signed_integers(self):
        BinaryAccessor.write_array(
            [0, 1, 2, 3, 4, 5, -1, 127],
            0,
            8,
            "INT",
            0,
            self.data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(self.data, b"\x00\x01\x02\x03\x04\x05\xFF\x7F")

    def test_complains_about_unaligned_strings_bin(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_offset 1 is not byte aligned for data_type STRING"
        ):
            BinaryAccessor.write_array(
                [b"X"], 1, 32, "STRING", 32, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_writes_string_items(self):
        BinaryAccessor.write_array(
            [b"a"], 0, 64, "STRING", 0, self.baseline_data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.baseline_data, b"a\x00\x00\x00\x00\x00\x00\x00")

    def test_writes_block_items(self):
        BinaryAccessor.write_array(
            [b"\x01", b"\x02", b"\x03", b"\x04"],
            0,
            32,
            "BLOCK",
            0,
            self.baseline_data,
            "BIG_ENDIAN",
            "ERROR",
        )
        self.assertEqual(
            self.baseline_data,
            b"\x01\x00\x00\x00\x02\x00\x00\x00\x03\x00\x00\x00\x04\x00\x00\x00",
        )

    def test_writes_variable_length_arrays_with_a_zero_and_negative_array_size(self):
        baseline_data_array_uint8 = []
        for i in range(len(self.baseline_data)):
            baseline_data_array_uint8.append(self.baseline_data[i])  # .ord
        for array_size in range(0, -(len(self.baseline_data) * 8), -8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            self.expected_data = self.baseline_data[:] + (
                b"\x00" * -int(array_size / 8)
            )
            BinaryAccessor.write_array(
                baseline_data_array_uint8,
                0,
                8,
                "UINT",
                array_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, self.expected_data)

    def test_writes_variable_length_arrays_or_32_bit_uints_with_a_zero_and_negative_array_size(
        self,
    ):
        baseline_data = bytearray(
            b"\x01\x01\x01\x01\x02\x02\x02\x02\x03\x03\x03\x03\x04\x04\x04\x04"
        )
        data_array_uint32 = [0x01010101, 0x02020202, 0x03030303, 0x04040404]
        for array_size in range(0, -(len(self.baseline_data) * 8), -8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            self.expected_data = baseline_data[:] + (b"\x00" * -int(array_size / 8))
            BinaryAccessor.write_array(
                data_array_uint32,
                0,
                32,
                "UINT",
                array_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, self.expected_data)

    def test_writes_variable_length_arrays_of_32_bit_uints_with_a_zero_and_negative_array_size_and_non_zero_bit_offset(
        self,
    ):
        baseline_data = bytearray(
            b"\x01\x01\x01\x01\x02\x02\x02\x02\x03\x03\x03\x03\x04\x04\x04\x04"
        )
        data_array_uint32 = [0x01010101, 0x02020202, 0x03030303, 0x04040404]
        for array_size in range(0, -(len(self.baseline_data) * 8), -8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            self.expected_data = (
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
                + baseline_data[:]
                + (b"\x00" * -int(array_size / 8))
            )
            BinaryAccessor.write_array(
                data_array_uint32,
                128,
                32,
                "UINT",
                array_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, self.expected_data)

    def test_writes_variable_length_arrays_of_32_bit_uints_with_a_zero_and_negative_array_size_and_non_zero_bit_offset_and_grow_the_buffer(
        self,
    ):
        baseline_data = bytearray(
            b"\x01\x01\x01\x01\x02\x02\x02\x02\x03\x03\x03\x03\x04\x04\x04\x04"
        )
        data_array_uint32 = [0x01010101, 0x02020202, 0x03030303, 0x04040404]
        for array_size in range(0, -(len(self.baseline_data) * 8), -8):
            self.data = bytearray(
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
            )
            self.expected_data = (
                b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
                + baseline_data[:]
                + (b"\x00" * -int(array_size / 8))
            )
            BinaryAccessor.write_array(
                data_array_uint32,
                128,
                32,
                "UINT",
                array_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )
            self.assertEqual(self.data, self.expected_data)

    def test_writes_1_bit_unsigned_integers(self):
        BinaryAccessor.write_array(
            [1, 0, 1], 8, 1, "UINT", 3, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\xA0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_1_bit_signed_integers(self):
        BinaryAccessor.write_array(
            [1, 0, 1], 8, 1, "INT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, b"\x00\xA0")

    def test_writes_7_bit_unsigned_integers(self):
        BinaryAccessor.write_array(
            [0x40, 0x60, 0x50], 8, 7, "UINT", 21, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\x81\x82\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_aligned_16_bit_unsigned_integers(self):
        data = [0x8081, 0x8283, 0x8485, 0x8687, 0x0009, 0x0A0B, 0x0C0D, 0x0E0F]
        BinaryAccessor.write_array(
            data, 0, 16, "UINT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_16_bit_signed_integers(self):
        data = [0x8081, 0x8283, 0x8485, 0x8687, 0x0009, 0x0A0B, 0x0C0D, 0x0E0F]
        data = [(x & ~(1 << 15)) - (x & (1 << 15)) for x in data]
        BinaryAccessor.write_array(
            data, 0, 16, "INT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_unsigned_integers(self):
        data = [0x80818283, 0x84858687, 0x00090A0B, 0x0C0D0E0F]
        BinaryAccessor.write_array(
            data, 0, 32, "UINT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_signed_integers(self):
        data = [0x80818283, 0x84858687, 0x00090A0B, 0x0C0D0E0F]
        data = [(x & ~(1 << 31)) - (x & (1 << 31)) for x in data]
        BinaryAccessor.write_array(
            data, 0, 32, "INT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_small_32_bit_floats(self):
        data = [-1.189360e-038, -3.139169e-036, 8.301067e-040, 1.086646e-031]
        BinaryAccessor.write_array(
            data, 0, 32, "FLOAT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[0], 38
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(32, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[1], 36
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[2], 40
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(96, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[3], 31
        )

    def test_writes_aligned_normal_32_bit_floats(self):
        data = [5.5, 6.6, 7.7, 8.8]
        BinaryAccessor.write_array(
            data, 0, 32, "FLOAT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[0], 5
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(32, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[1], 5
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[2], 5
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(96, 32, "FLOAT", self.data, "BIG_ENDIAN"), data[3], 5
        )

    def test_writes_aligned_64_bit_unsigned_integers(self):
        data = [0x8081828384858687, 0x00090A0B0C0D0E0F]
        BinaryAccessor.write_array(
            data, 0, 64, "UINT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_signed_integers(self):
        data = [0x8081828384858687, 0x00090A0B0C0D0E0F]
        data = [(x & ~(1 << 63)) - (x & (1 << 63)) for x in data]
        BinaryAccessor.write_array(
            data, 0, 64, "INT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_floats(self):
        data = [-3.116851e-306, 1.257060e-308]
        BinaryAccessor.write_array(
            data, 0, 64, "FLOAT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 64, "FLOAT", self.data, "BIG_ENDIAN"), data[0], 306
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 64, "FLOAT", self.data, "BIG_ENDIAN"), data[1], 308
        )

    def test_writes_normal_aligned_64_bit_floats(self):
        data = [3.14159, 12.3456789]
        BinaryAccessor.write_array(
            data, 0, 64, "FLOAT", 0, self.data, "BIG_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 64, "FLOAT", self.data, "BIG_ENDIAN"), data[0]
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 64, "FLOAT", self.data, "BIG_ENDIAN"), data[1]
        )

    def test_complains_about_unaligned_floats(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_offset 17 is not byte aligned for data_type FLOAT"
        ):
            BinaryAccessor.write_array(
                [0.0], 17, 32, "FLOAT", 32, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_complains_about_mis_sized_floats(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_size is 33 but must be 32 or 64 for data_type FLOAT"
        ):
            BinaryAccessor.write_array(
                [0.0], 0, 33, "FLOAT", 33, self.data, "BIG_ENDIAN", "ERROR"
            )


class TestBinaryAccessorWriteArrayLittleEndian(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )
        self.data_array = []
        for i in range(len(self.data)):
            self.data_array.append(self.data[i])
        self.baseline_data = bytearray(
            b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        )
        self.baseline_data_array = []
        for i in range(len(self.baseline_data)):
            self.baseline_data_array.append(self.baseline_data[i])

    def test_writes_1_bit_unsigned_integers(self):
        BinaryAccessor.write_array(
            [1, 0, 1], 8, 1, "UINT", 3, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(
            self.data,
            b"\x00\xA0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
        )

    def test_writes_1_bit_signed_integers(self):
        BinaryAccessor.write_array(
            [1, 0, 1], 8, 1, "INT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, b"\x00\xA0")

    def test_complains_about_little_endian_bit_fields_greater_than_1_bit(self):
        with self.assertRaisesRegex(
            AttributeError,
            "write_array does not support little endian bit fields with bit_size greater than 1-bit",
        ):
            BinaryAccessor.write_array(
                [0x40, 0x60, 0x50],
                8,
                7,
                "UINT",
                21,
                self.data,
                "LITTLE_ENDIAN",
                "ERROR",
            )

    def test_writes_aligned_16_bit_unsigned_integers(self):
        data = [0x8180, 0x8382, 0x8584, 0x8786, 0x0900, 0x0B0A, 0x0D0C, 0x0F0E]
        BinaryAccessor.write_array(
            data, 0, 16, "UINT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_16_bit_signed_integers(self):
        data = [0x8180, 0x8382, 0x8584, 0x8786, 0x0900, 0x0B0A, 0x0D0C, 0x0F0E]
        data = [(x & ~(1 << 15)) - (x & (1 << 15)) for x in data]
        BinaryAccessor.write_array(
            data, 0, 16, "INT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_unsigned_integers(self):
        data = [0x83828180, 0x87868584, 0x0B0A0900, 0x0F0E0D0C]
        BinaryAccessor.write_array(
            data, 0, 32, "UINT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_signed_integers(self):
        data = [0x83828180, 0x87868584, 0x0B0A0900, 0x0F0E0D0C]
        data = [(x & ~(1 << 31)) - (x & (1 << 31)) for x in data]
        BinaryAccessor.write_array(
            data, 0, 32, "INT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_32_bit_floats(self):
        data = [-7.670445e-037, -2.024055e-034, 2.658460e-032, 7.003653e-030]
        BinaryAccessor.write_array(
            data, 0, 32, "FLOAT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 32, "FLOAT", self.data, "LITTLE_ENDIAN"), data[0], 37
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(32, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            data[1],
            34,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            data[2],
            32,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(96, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            data[3],
            30,
        )

    def test_writes_aligned_64_bit_unsigned_integers(self):
        data = [0x8786858483828180, 0x0F0E0D0C0B0A0900]
        BinaryAccessor.write_array(
            data, 0, 64, "UINT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_signed_integers(self):
        data = [0x8786858483828180, 0x0F0E0D0C0B0A0900]
        data = [(x & ~(1 << 63)) - (x & (1 << 63)) for x in data]
        BinaryAccessor.write_array(
            data, 0, 64, "INT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertEqual(self.data, self.baseline_data)

    def test_writes_aligned_64_bit_floats(self):
        data = [-2.081577e-272, 3.691916e-236]
        BinaryAccessor.write_array(
            data, 0, 64, "FLOAT", 0, self.data, "LITTLE_ENDIAN", "ERROR"
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 64, "FLOAT", self.data, "LITTLE_ENDIAN"),
            data[0],
            272,
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 64, "FLOAT", self.data, "LITTLE_ENDIAN"),
            data[1],
            236,
        )

    def test_complains_about_unaligned_floats(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_offset 1 is not byte aligned for data_type FLOAT"
        ):
            BinaryAccessor.write_array(
                [0.0], 1, 32, "FLOAT", 32, self.data, "LITTLE_ENDIAN", "ERROR"
            )

    def test_complains_about_mis_sized_floats(self):
        with self.assertRaisesRegex(
            AttributeError, "bit_size is 65 but must be 32 or 64 for data_type FLOAT"
        ):
            BinaryAccessor.write_array(
                [0.0], 0, 65, "FLOAT", 65, self.data, "LITTLE_ENDIAN", "ERROR"
            )


class TestBinaryAccessorWriteOverflow(unittest.TestCase):
    def setUp(self):
        self.data = bytearray(
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
        )

    def test_prevents_overflow_of_string(self):
        with self.assertRaisesRegex(
            AttributeError,
            "value of 5 bytes does not fit into 4 bytes for data_type STRING",
        ):
            BinaryAccessor.write_array(
                ["abcde"], 0, 32, "STRING", 32, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_prevents_overflow_of_block(self):
        with self.assertRaisesRegex(
            AttributeError,
            "value of 5 bytes does not fit into 4 bytes for data_type BLOCK",
        ):
            BinaryAccessor.write_array(
                ["abcde"], 0, 32, "BLOCK", 32, self.data, "BIG_ENDIAN", "ERROR"
            )

    def test_prevents_overflow_of_8_bit_int(self):
        bit_size = 8
        data_type = "INT"
        value = 2 ** (bit_size - 1)
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_16_bit_int(self):
        bit_size = 16
        data_type = "INT"
        value = 2 ** (bit_size - 1)
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_32_bit_int(self):
        bit_size = 32
        data_type = "INT"
        value = 2 ** (bit_size - 1)
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_64_bit_int(self):
        bit_size = 64
        data_type = "INT"
        value = 2 ** (bit_size - 1)
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_3_bit_int(self):
        bit_size = 3
        data_type = "INT"
        value = 2 ** (bit_size - 1)
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_8_bit_uint(self):
        bit_size = 8
        data_type = "UINT"
        value = 2**bit_size
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_16_bit_uint(self):
        bit_size = 16
        data_type = "UINT"
        value = 2**bit_size
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_32_bit_uint(self):
        bit_size = 32
        data_type = "UINT"
        value = 2**bit_size
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_64_bit_uint(self):
        bit_size = 64
        data_type = "UINT"
        value = 2**bit_size
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_prevents_overflow_of_3_bit_uint(self):
        bit_size = 3
        data_type = "UINT"
        value = 2**bit_size
        with self.assertRaisesRegex(
            AttributeError, f"value of {value} invalid for {bit_size}-bit {data_type}"
        ):
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "ERROR",
            )

    def test_truncates_string(self):
        BinaryAccessor.write_array(
            [b"abcde"], 0, 32, "STRING", 32, self.data, "BIG_ENDIAN", "TRUNCATE"
        )
        self.assertEqual(self.data[0:5], b"abcd\x00")

    def test_truncates_block(self):
        BinaryAccessor.write_array(
            [b"abcde"], 0, 32, "BLOCK", 32, self.data, "BIG_ENDIAN", "TRUNCATE"
        )
        self.assertEqual(self.data[0:5], b"abcd\x00")

    def test_truncates_ints(self):
        for bit_size in [3, 5, 8, 16, 32, 64]:
            data_type = "INT"
            value = 2 ** (bit_size - 1)
            truncated_value = -value
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "TRUNCATE",
            )
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, data_type, self.data, "BIG_ENDIAN"),
                truncated_value,
            )

    def test_truncates_uints(self):
        for bit_size in [3, 5, 8, 16, 32, 64]:
            data_type = "INT"
            value = 2**bit_size + 1
            truncated_value = 1
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "TRUNCATE",
            )
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, data_type, self.data, "BIG_ENDIAN"),
                truncated_value,
            )

    def test_saturates_ints(self):
        for bit_size in [3, 5, 8, 16, 32, 64]:
            data_type = "INT"
            value = 2 ** (bit_size - 1)
            saturated_value = value - 1
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "SATURATE",
            )
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, data_type, self.data, "BIG_ENDIAN"),
                saturated_value,
            )

    def test_saturates_uints(self):
        for bit_size in [3, 5, 8, 16, 32, 64]:
            data_type = "UINT"
            value = 2**bit_size
            saturated_value = value - 1
            BinaryAccessor.write_array(
                [value],
                0,
                bit_size,
                data_type,
                bit_size,
                self.data,
                "BIG_ENDIAN",
                "SATURATE",
            )
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, data_type, self.data, "BIG_ENDIAN"),
                saturated_value,
            )


# TODO: Do we need these?
#     def test_allows_hex_value_entry_of_8_bit_int(self):
#           bit_size = 8; data_type = 'INT'; value = 2**bit_size - 1; allowed_value = -1
#           BinaryAccessor.write_array([value], 0, bit_size, data_type, bit_size, self.data, 'BIG_ENDIAN', 'ERROR_ALLOW_HEX')
#           self.assertEqual(BinaryAccessor.read(0, bit_size, data_type, self.data, 'BIG_ENDIAN'), allowed_value)

#     def test_allows_hex_value_entry_of_16_bit_int(self):
#           bit_size = 16; data_type = 'INT'; value = 2**bit_size - 1; allowed_value = -1
#           BinaryAccessor.write_array([value], 0, bit_size, data_type, bit_size, self.data, 'BIG_ENDIAN', 'ERROR_ALLOW_HEX')
#           self.assertEqual(BinaryAccessor.read(0, bit_size, data_type, self.data, 'BIG_ENDIAN'), allowed_value)

#     def test_allows_hex_value_entry_of_32_bit_int(self):
#           bit_size = 32; data_type = 'INT'; value = 2**bit_size - 1; allowed_value = -1
#           BinaryAccessor.write_array([value], 0, bit_size, data_type, bit_size, self.data, 'BIG_ENDIAN', 'ERROR_ALLOW_HEX')
#           self.assertEqual(BinaryAccessor.read(0, bit_size, data_type, self.data, 'BIG_ENDIAN'), allowed_value)

#     def test_allows_hex_value_entry_of_64_bit_int(self):
#           bit_size = 64; data_type = 'INT'; value = 2**bit_size - 1; allowed_value = -1
#           BinaryAccessor.write_array([value], 0, bit_size, data_type, bit_size, self.data, 'BIG_ENDIAN', 'ERROR_ALLOW_HEX')
#           self.assertEqual(BinaryAccessor.read(0, bit_size, data_type, self.data, 'BIG_ENDIAN'), allowed_value)

#     def test_allows_hex_value_entry_of_3_bit_int(self):
#           bit_size = 3; data_type = 'INT'; value = 2**bit_size - 1; allowed_value = -1
#           BinaryAccessor.write_array([value], 0, bit_size, data_type, bit_size, self.data, 'BIG_ENDIAN', 'ERROR_ALLOW_HEX')
#           self.assertEqual(BinaryAccessor.read(0, bit_size, data_type, self.data, 'BIG_ENDIAN'), allowed_value)
