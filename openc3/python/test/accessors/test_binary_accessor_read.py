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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.accessors.binary_accessor import BinaryAccessor


class TestBinaryAccessorRead(unittest.TestCase):
    def setUp(self):
        self.data = b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"

    # def test_get_host_endianness(self):
    #     endianness = BinaryAccessor.get_host_endianness()
    #     print(f"Host endianness:{endianness}")

    def test_complains_about_unknown_data_types(self):
        self.assertRaisesRegex(
            AttributeError,
            f"data_type BLOB is not recognized",
            BinaryAccessor.read,
            0,
            32,
            "BLOB",
            self.data,
            "BIG_ENDIAN",
        )

    def test_complains_about_bit_offsets_before_the_beginning_of_the_buffer(self):
        self.assertRaisesRegex(
            AttributeError,
            f"{len(self.data)} byte buffer insufficient to read STRING at bit_offset {-((len(self.data) * 8) + 8)} with bit_size 32",
            BinaryAccessor.read,
            -(len(self.data) * 8 + 8),
            32,
            "STRING",
            self.data,
            "BIG_ENDIAN",
        )

    def test_complains_about_a_negative_bit_offset_and_zero_bit_size(self):
        self.assertRaisesRegex(
            AttributeError,
            r"negative or zero bit_sizes \(0\) cannot be given with negative bit_offsets \(-8\)",
            BinaryAccessor.read,
            -8,
            0,
            "STRING",
            self.data,
            "BIG_ENDIAN",
        )

    def test_complains_about_a_negative_bit_offset_and_negative_bit_size(self):
        self.assertRaisesRegex(
            AttributeError,
            r"negative or zero bit_sizes \(-8\) cannot be given with negative bit_offsets \(-8\)",
            BinaryAccessor.read,
            -8,
            -8,
            "STRING",
            self.data,
            "BIG_ENDIAN",
        )

    def test_complains_about_negative_bit_sizes_larger_than_the_size_of_the_buffer(
        self,
    ):
        self.assertRaisesRegex(
            AttributeError,
            # TODO: WHat's up with this not matching
            f"{len(self.data)} byte buffer insufficient to read STRING at bit_offset 0 with bit_size {-((len(self.data) * 8) + 8)}",
            BinaryAccessor.read,
            0,
            -((len(self.data) * 8) + 8),
            "STRING",
            self.data,
            "BIG_ENDIAN",
        )

    def test_complains_about_negative_or_zero_bit_sizes_with_data_types_other_than_string_and_block(
        self,
    ):
        self.assertRaisesRegex(
            AttributeError,
            # TODO: WHat's up with this not matching
            f"bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.read,
            0,
            -8,
            "INT",
            self.data,
            "BIG_ENDIAN",
        )
        self.assertRaisesRegex(
            AttributeError,
            # TODO: WHat's up with this not matching
            f"bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.read,
            0,
            -8,
            "UINT",
            self.data,
            "BIG_ENDIAN",
        )
        self.assertRaisesRegex(
            AttributeError,
            # TODO: WHat's up with this not matching
            f"bit_size -8 must be positive for data types other than 'STRING' and 'BLOCK'",
            BinaryAccessor.read,
            0,
            -8,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
        )

    def test_reads_aligned_strings(self):
        for bit_offset in range(0, len(self.data) - 1, 8):
            if (bit_offset / 8) <= 7:
                self.assertEqual(
                    BinaryAccessor.read(
                        bit_offset,
                        (len(self.data) * 8) - bit_offset,
                        "STRING",
                        self.data,
                        "BIG_ENDIAN",
                    ),
                    self.data[int(bit_offset / 8) : 8],
                )
            elif (bit_offset / 8) == 8:
                self.assertEqual(
                    BinaryAccessor.read(
                        bit_offset,
                        (len(self.data) * 8) - bit_offset,
                        "STRING",
                        self.data,
                        "BIG_ENDIAN",
                    ),
                    "",
                )
            else:
                self.assertEqual(
                    BinaryAccessor.read(
                        bit_offset,
                        (len(self.data) * 8) - bit_offset,
                        "STRING",
                        self.data,
                        "BIG_ENDIAN",
                    ),
                    self.data[(bit_offset / 8) : -1],
                )

    def test_reads_variable_length_strings_with_a_zero_and_negative_bit_size(self):
        for bit_size in range(0, -len(self.data) * 8, -8):
            if (bit_size / 8) >= -8:
                self.assertEqual(
                    BinaryAccessor.read(0, bit_size, "STRING", self.data, "BIG_ENDIAN"),
                    self.data[0:8],
                )
            else:
                self.assertEqual(
                    BinaryAccessor.read(0, bit_size, "STRING", self.data, "BIG_ENDIAN"),
                    self.data[0 : int(bit_size / 8)],
                )

    def test_reads_strings_with_negative_bit_offsets(self):
        self.assertEqual(
            BinaryAccessor.read(-16, 16, "STRING", self.data, "BIG_ENDIAN"),
            self.data[-2:],
        )

    def test_complains_about_unaligned_strings(self):
        self.assertRaisesRegex(
            AttributeError,
            f"bit_offset 1 is not byte aligned for data_type STRING",
            BinaryAccessor.read,
            1,
            32,
            "STRING",
            self.data,
            "BIG_ENDIAN",
        )

    def test_reads_aligned_blocks(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            self.assertEqual(
                BinaryAccessor.read(
                    bit_offset,
                    (len(self.data) * 8) - bit_offset,
                    "BLOCK",
                    self.data,
                    "BIG_ENDIAN",
                ),
                self.data[int(bit_offset / 8) : -1],
            )

    def test_reads_variable_length_blocks_with_a_zero_and_negative_bit_size(self):
        for bit_size in range(0, -len(self.data) * 8, -8):
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, "BLOCK", self.data, "BIG_ENDIAN"),
                self.data[0 : int(bit_size / 8) - 1],
            )

    def test_reads_blocks_with_negative_bit_offsets(self):
        self.assertEqual(
            BinaryAccessor.read(-16, 16, "BLOCK", self.data, "BIG_ENDIAN"),
            self.data[-2:-1],
        )

    def test_complains_about_unaligned_blocks(self):
        self.assertRaisesRegex(
            AttributeError,
            f"bit_offset 7 is not byte aligned for data_type BLOCK",
            BinaryAccessor.read,
            7,
            16,
            "BLOCK",
            self.data,
            "BIG_ENDIAN",
        )

    def test_complains_if_read_exceeds_the_size_of_the_buffer(self):
        self.assertRaisesRegex(
            AttributeError,
            f"16 byte buffer insufficient to read STRING at bit_offset 8 with bit_size 800",
            BinaryAccessor.read,
            8,
            800,
            "STRING",
            self.data,
            "BIG_ENDIAN",
        )

    def test_reads_aligned_8_bit_unsigned_integers(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 8, "UINT", self.data, "BIG_ENDIAN"),
                self.data[int(bit_offset / 8)],
            )

    def test_reads_aligned_8_bit_signed_integers(self):
        for bit_offset in range(0, (len(self.data) - 1) * 8, 8):
            expected = self.data[int(bit_offset / 8)]
            if expected >= 128:
                expected = expected - 256
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 8, "INT", self.data, "BIG_ENDIAN"),
                expected,
            )


class TestBinaryAccessorReadBigEndian(unittest.TestCase):
    def setUp(self):
        self.data = b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"

    def test_reads_1_bit_unsigned_integers(self):
        expected = [0x1, 0x0]
        bit_size = 1
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(9, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_1_bit_signed_integers(self):
        expected = [0x1, 0x0]
        bit_size = 1
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(9, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_7_bit_unsigned_integers(self):
        expected = [0x40, 0x02]
        bit_size = 7
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(3, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_7_bit_signed_integers(self):
        expected = [0x40, 0x02]
        bit_size = 7
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(3, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_13_bit_unsigned_integers(self):
        expected = [0x1C24, 0x20]
        bit_size = 13
        self.assertEqual(
            BinaryAccessor.read(30, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(1, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_13_bit_signed_integers(self):
        expected = [0x1C24, 0x20]
        bit_size = 13
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
        self.assertEqual(
            BinaryAccessor.read(30, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(1, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_aligned_16_bit_unsigned_integers(self):
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
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 16, "UINT", self.data, "BIG_ENDIAN"),
                expected_array[index],
            )
            index += 1

    def test_reads_aligned_16_bit_signed_integers(self):
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
                expected -= 2**16
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 16, "INT", self.data, "BIG_ENDIAN"),
                expected,
            )
            index += 1

    def test_reads_aligned_32_bit_unsigned_integers(self):
        expected_array = [0x80818283, 0x84858687, 0x00090A0B, 0x0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 32, "UINT", self.data, "BIG_ENDIAN"),
                expected_array[index],
            )
            index += 1

    def test_reads_aligned_32_bit_signed_integers(self):
        expected_array = [0x80818283, 0x84858687, 0x00090A0B, 0x0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            expected = expected_array[index]
            if expected >= 2**31:
                expected = expected - 2**32
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 32, "INT", self.data, "BIG_ENDIAN"),
                expected,
            )
            index += 1

    def test_reads_aligned_32_bit_floats(self):
        expected_array = [-1.189360e-38, -3.139169e-36, 8.301067e-40, 1.086646e-31]
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[0],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(32, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[1],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[2],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(96, 32, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[3],
        )

    def test_reads_37_bit_unsigned_integers(self):
        expected = [0x8182838485 >> 3, 0x00090A0B0C]
        bit_size = 37
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(67, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_37_bit_signed_integers(self):
        expected = [0x8182838485 >> 3, 0x00090A0B0C]
        bit_size = 37
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(67, bit_size, "INT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_63_bit_unsigned_integers(self):
        expected = [0x8081828384858687 >> 1, 0x00090A0B0C0D0E0F]
        bit_size = 63
        self.assertEqual(
            BinaryAccessor.read(0, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(65, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_63_bit_signed_integers(self):
        expected = [0x8081828384858687 >> 1, 0x00090A0B0C0D0E0F]
        bit_size = 63
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, "INT", self.data, "BIG_ENDIAN"),
                expected[0],
            )
            self.assertEqual(
                BinaryAccessor.read(65, bit_size, "INT", self.data, "BIG_ENDIAN"),
                expected[1],
            )

    def test_reads_67_bit_unsigned_integers(self):
        expected = [0x808182838485868700 >> 5, 0x8700090A0B0C0D0E0F >> 5]
        bit_size = 67
        self.assertEqual(
            BinaryAccessor.read(0, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(56, bit_size, "UINT", self.data, "BIG_ENDIAN"),
            expected[1],
        )

    def test_reads_67_bit_signed_integers(self):
        expected = [0x808182838485868700 >> 5, 0x8700090A0B0C0D0E0F >> 5]
        bit_size = 67
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
            self.assertEqual(
                BinaryAccessor.read(0, bit_size, "INT", self.data, "BIG_ENDIAN"),
                expected[0],
            )
            self.assertEqual(
                BinaryAccessor.read(56, bit_size, "INT", self.data, "BIG_ENDIAN"),
                expected[1],
            )

    def test_reads_aligned_64_bit_unsigned_integers(self):
        expected_array = [0x8081828384858687, 0x00090A0B0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 64, "UINT", self.data, "BIG_ENDIAN"),
                expected_array[index],
            )
            index += 1

    def test_reads_aligned_64_bit_signed_integers(self):
        expected_array = [0x8081828384858687, 0x00090A0B0C0D0E0F]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            expected = expected_array[index]
            if expected >= 2**63:
                expected = expected - 2**64
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 64, "INT", self.data, "BIG_ENDIAN"),
                expected,
            )
            index += 1

    def test_reads_aligned_64_bit_floats(self):
        expected_array = [-3.116851e-306, 1.257060e-308]
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 64, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[0],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 64, "FLOAT", self.data, "BIG_ENDIAN"),
            expected_array[1],
        )

    def test_complains_about_unaligned_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            f"bit_offset 17 is not byte aligned for data_type FLOAT",
            BinaryAccessor.read,
            17,
            32,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
        )

    def test_complains_about_mis_sized_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            f"bit_size is 33 but must be 32 or 64 for data_type FLOAT",
            BinaryAccessor.read,
            0,
            33,
            "FLOAT",
            self.data,
            "BIG_ENDIAN",
        )


class TestBinaryAccessorReadLittleEndian(unittest.TestCase):
    def setUp(self):
        self.data = b"\x80\x81\x82\x83\x84\x85\x86\x87\x00\x09\x0A\x0B\x0C\x0D\x0E\x0F"

    def test_complains_about_ill_defined_little_endian_bitfields(self):
        self.assertRaisesRegex(
            AttributeError,
            f"LITTLE_ENDIAN bitfield with bit_offset 3 and bit_size 7 is invalid",
            BinaryAccessor.read,
            3,
            7,
            "UINT",
            self.data,
            "LITTLE_ENDIAN",
        )

    def test_reads_1_bit_unsigned_integers(self):
        expected = [0x1, 0x0]
        bit_size = 1
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(9, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_1_bit_signed_integers(self):
        expected = [0x1, 0x0]
        bit_size = 1
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(9, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_7_bit_unsigned_integers(self):
        expected = [0x40, 0x60]
        bit_size = 7
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(15, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_7_bit_signed_integers(self):
        expected = [0x40, 0x60]
        bit_size = 7
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
        self.assertEqual(
            BinaryAccessor.read(8, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(15, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_13_bit_unsigned_integers(self):
        expected = [0x038281 >> 5, 0x0180 >> 2]
        bit_size = 13
        self.assertEqual(
            BinaryAccessor.read(30, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(9, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_13_bit_signed_integers(self):
        expected = [0x038281 >> 5, 0x0180 >> 2]
        bit_size = 13
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
            self.assertEqual(
                BinaryAccessor.read(30, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
                expected[0],
            )
            self.assertEqual(
                BinaryAccessor.read(9, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
                expected[1],
            )

    def test_reads_aligned_16_bit_unsigned_integers(self):
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
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 16, "UINT", self.data, "LITTLE_ENDIAN"),
                expected_array[index],
            )
            index += 1

    def test_reads_aligned_16_bit_signed_integers(self):
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
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 16, "INT", self.data, "LITTLE_ENDIAN"),
                expected,
            )
            index += 1

    def test_reads_aligned_32_bit_unsigned_integers(self):
        expected_array = [0x83828180, 0x87868584, 0x0B0A0900, 0x0F0E0D0C]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 32, "UINT", self.data, "LITTLE_ENDIAN"),
                expected_array[index],
            )
            index += 1

    def test_reads_aligned_32_bit_signed_integers(self):
        expected_array = [0x83828180, 0x87868584, 0x0B0A0900, 0x0F0E0D0C]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 32):
            expected = expected_array[index]
            if expected >= 2**31:
                expected = expected - 2**32
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 32, "INT", self.data, "LITTLE_ENDIAN"),
                expected,
            )
            index += 1

    def test_reads_aligned_32_bit_floats(self):
        expected_array = [-7.670445e-037, -2.024055e-034, 2.658460e-032, 7.003653e-030]
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[0],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(32, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[1],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[2],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(96, 32, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[3],
        )

    def test_reads_37_bit_unsigned_integers(self):
        expected = [0x8584838281 >> 3, 0x0F0E0D0C0B]
        bit_size = 37
        self.assertEqual(
            BinaryAccessor.read(40, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(123, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_37_bit_signed_integers(self):
        expected = [0x8584838281 >> 3, 0x0F0E0D0C0B]
        bit_size = 37
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
        self.assertEqual(
            BinaryAccessor.read(40, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(123, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_63_bit_unsigned_integers(self):
        expected = [0x0F0E0D0C0B0A0900 >> 1, 0x0786858483828180]
        bit_size = 63
        self.assertEqual(
            BinaryAccessor.read(120, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )
        self.assertEqual(
            BinaryAccessor.read(57, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[1],
        )

    def test_reads_63_bit_signed_integers(self):
        expected = [0x0F0E0D0C0B0A0900 >> 1, 0x0786858483828180]
        bit_size = 63
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
            self.assertEqual(
                BinaryAccessor.read(120, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
                expected[0],
            )
            self.assertEqual(
                BinaryAccessor.read(57, bit_size, "INT", self.data, "LITTLE_ENDIAN"),
                expected[1],
            )

    def test_reads_67_bit_unsigned_integers(self):
        expected = [0x0F0E0D0C0B0A090087 >> 5]
        bit_size = 67
        self.assertEqual(
            BinaryAccessor.read(120, bit_size, "UINT", self.data, "LITTLE_ENDIAN"),
            expected[0],
        )

    def test_reads_67_bit_signed_integers(self):
        expected = [0x0F0E0D0C0B0A090087 >> 5]
        bit_size = 67
        for value, index in enumerate(expected):
            if value >= 2 ** (bit_size - 1):
                expected[index] = value - 2**bit_size
                self.assertEqual(
                    BinaryAccessor.read(
                        120, bit_size, "INT", self.data, "LITTLE_ENDIAN"
                    ),
                    expected[0],
                )

    def test_reads_aligned_64_bit_unsigned_integers(self):
        expected_array = [0x8786858483828180, 0x0F0E0D0C0B0A0900]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 64, "UINT", self.data, "LITTLE_ENDIAN"),
                expected_array[index],
            )
            index += 1

    def test_reads_aligned_64_bit_signed_integers(self):
        expected_array = [0x8786858483828180, 0x0F0E0D0C0B0A0900]
        index = 0
        for bit_offset in range(0, (len(self.data) - 1) * 8, 64):
            expected = expected_array[index]
            if expected >= 2**63:
                expected = expected - 2**64
            self.assertEqual(
                BinaryAccessor.read(bit_offset, 64, "INT", self.data, "LITTLE_ENDIAN"),
                expected,
            )
            index += 1

    def test_reads_aligned_64_bit_floats(self):
        expected_array = [-2.081577e-272, 3.691916e-236]
        self.assertAlmostEqual(
            BinaryAccessor.read(0, 64, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[0],
        )
        self.assertAlmostEqual(
            BinaryAccessor.read(64, 64, "FLOAT", self.data, "LITTLE_ENDIAN"),
            expected_array[1],
        )

    def test_complains_about_unaligned_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            f"bit_offset 1 is not byte aligned for data_type FLOAT",
            BinaryAccessor.read,
            1,
            32,
            "FLOAT",
            self.data,
            "LITTLE_ENDIAN",
        )

    def test_complains_about_mis_sized_floats(self):
        self.assertRaisesRegex(
            AttributeError,
            f"bit_size is 65 but must be 32 or 64 for data_type FLOAT",
            BinaryAccessor.read,
            0,
            65,
            "FLOAT",
            self.data,
            "LITTLE_ENDIAN",
        )