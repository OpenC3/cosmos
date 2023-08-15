#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
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
from openc3.packets.structure_item import StructureItem


class TestStructureItem(unittest.TestCase):
    def test_name_creates_new_structure_items(self):
        self.assertEqual(
            StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None).name, "TEST"
        )

    def test_name_complains_about_non_string_names(self):
        self.assertRaisesRegex(
            AttributeError,
            "name must be a String but is a NoneType",
            StructureItem,
            None,
            0,
            8,
            "UINT",
            "BIG_ENDIAN",
            None,
        )
        self.assertRaisesRegex(
            AttributeError,
            "name must be a String but is a float",
            StructureItem,
            5.1,
            0,
            8,
            "UINT",
            "BIG_ENDIAN",
            None,
        )

    def test_complains_about_blank_names(self):
        self.assertRaisesRegex(
            AttributeError,
            "name must contain at least one character",
            StructureItem,
            "",
            0,
            8,
            "UINT",
            "BIG_ENDIAN",
            None,
        )

    def test_endian_accepts_big_and_little(self):
        self.assertEqual(
            StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None).endianness,
            "BIG_ENDIAN",
        )
        self.assertEqual(
            StructureItem("test", 0, 8, "UINT", "LITTLE_ENDIAN", None).endianness,
            "LITTLE_ENDIAN",
        )

    def test_complains_about_bad_endianness(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: unknown endianness: BLAH - Must be 'BIG_ENDIAN' or 'LITTLE_ENDIAN'",
            StructureItem,
            "TEST",
            0,
            8,
            "UINT",
            "BLAH",
            None,
        )

    def test_accepts_data_types(self):
        for type in ["INT", "UINT", "FLOAT", "STRING", "BLOCK"]:
            self.assertEqual(
                StructureItem("test", 0, 32, type, "BIG_ENDIAN", None).data_type, type
            )

        self.assertEqual(
            StructureItem("test", 0, 0, "DERIVED", "BIG_ENDIAN", None).data_type,
            "DERIVED",
        )

    def test_complains_about_bad_data_type(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: unknown data_type: UNKNOWN - Must be 'INT', 'UINT', 'FLOAT', 'STRING', 'BLOCK', or 'DERIVED'",
            StructureItem,
            "TEST",
            0,
            0,
            "UNKNOWN",
            "BIG_ENDIAN",
            None,
        )

    def test_accepts_overflow_types(self):
        for type in ["ERROR", "ERROR_ALLOW_HEX", "TRUNCATE", "SATURATE"]:
            self.assertEqual(
                StructureItem("test", 0, 32, "INT", "BIG_ENDIAN", None, type).overflow,
                type,
            )

    def test_complains_about_bad_overflow_types(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: unknown overflow type: UNKNOWN - Must be 'ERROR', 'ERROR_ALLOW_HEX', 'TRUNCATE', or 'SATURATE'",
            StructureItem,
            "TEST",
            0,
            32,
            "INT",
            "BIG_ENDIAN",
            None,
            "UNKNOWN",
        )

    def test_complains_about_bad_bit_offsets_types(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: bit_offset must be an Integer",
            StructureItem,
            "TEST",
            None,
            8,
            "UINT",
            "BIG_ENDIAN",
            None,
        )

    def test_complains_about_unaligned_bit_offsets(self):
        for type in ["FLOAT", "STRING", "BLOCK"]:
            self.assertRaisesRegex(
                AttributeError,
                "TEST: bit_offset for 'FLOAT', 'STRING', and 'BLOCK' items must be byte aligned",
                StructureItem,
                "TEST",
                1,
                32,
                type,
                "BIG_ENDIAN",
                None,
            )

    def test_complains_about_non_zero_derived_bit_offsets(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: DERIVED items must have bit_offset of zero",
            StructureItem,
            "TEST",
            8,
            0,
            "DERIVED",
            "BIG_ENDIAN",
            None,
        )

    def test_complains_about_bad_bit_sizes_types(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: bit_size must be an Integer",
            StructureItem,
            "TEST",
            0,
            None,
            "UINT",
            "BIG_ENDIAN",
            None,
        )

    def test_complains_about_0_size_int_uint_and_float(self):
        for type in ["INT", "UINT", "FLOAT"]:
            self.assertRaisesRegex(
                AttributeError,
                "TEST: bit_size cannot be negative or zero for 'INT', 'UINT', and 'FLOAT' items: 0",
                StructureItem,
                "TEST",
                0,
                0,
                type,
                "BIG_ENDIAN",
                None,
            )

    def test_complains_about_bad_float_bit_sizes(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: bit_size for FLOAT items must be 32 or 64. Given: 8",
            StructureItem,
            "TEST",
            0,
            8,
            "FLOAT",
            "BIG_ENDIAN",
            None,
        )

    def test_creates_32_and_64_bit_floats(self):
        self.assertEqual(
            StructureItem("test", 0, 32, "FLOAT", "BIG_ENDIAN", None).bit_size, 32
        )
        self.assertEqual(
            StructureItem("test", 0, 64, "FLOAT", "BIG_ENDIAN", None).bit_size, 64
        )

    def test_complains_about_non_zero_derived_bit_sizes(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: DERIVED items must have bit_size of zero",
            StructureItem,
            "TEST",
            0,
            8,
            "DERIVED",
            "BIG_ENDIAN",
            None,
        )

    def test_complains_about_bad_array_size_types(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: array_size must be an Integer",
            StructureItem,
            "TEST",
            0,
            8,
            "UINT",
            "BIG_ENDIAN",
            "",
        )

    def test_complains_about_array_size_not_multiple_of_bit_size(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST: array_size must be a multiple of bit_size",
            StructureItem,
            "TEST",
            0,
            8,
            "UINT",
            "BIG_ENDIAN",
            10,
        )

    def test_does_not_complain_about_array_size_not_multiple_of_bit_size_with_negative_array_size(
        self,
    ):
        si = StructureItem("TEST", 0, 32, "UINT", "BIG_ENDIAN", -8)
        self.assertIsNotNone(si)

    def test_sorts_items_according_to_positive_bit_offset(self):
        si1 = StructureItem("si1", 0, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 8, 8, "UINT", "BIG_ENDIAN", None)
        self.assertTrue(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertFalse(si1 > si2)

        si2 = StructureItem("si2", 0, 8, "UINT", "BIG_ENDIAN", None)
        self.assertTrue(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertFalse(si1 > si2)

    def test_sorts_items_with_0_bit_offset_according_to_bit_size(self):
        si1 = StructureItem("si1", 0, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 0, "BLOCK", "BIG_ENDIAN", None)
        self.assertFalse(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertTrue(si1 > si2)

    def test_sorts_items_according_to_negative_bit_offset(self):
        si1 = StructureItem("si1", -8, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", -16, 8, "UINT", "BIG_ENDIAN", None)
        self.assertFalse(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertTrue(si1 > si2)

        si2 = StructureItem("si2", -8, 8, "UINT", "BIG_ENDIAN", None)
        self.assertTrue(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertFalse(si1 > si2)

    def test_sorts_items_according_to_mixed_bit_offset(self):
        si1 = StructureItem("si1", 16, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", -8, 8, "UINT", "BIG_ENDIAN", None)
        self.assertTrue(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertFalse(si1 > si2)

    def test_duplicates_the_entire_structure_item(self):
        si1 = StructureItem("si1", -8, 1, "UINT", "LITTLE_ENDIAN", None)
        si2 = si1.clone()
        self.assertTrue(si1 < si2)

    def test_creates_a_hash(self):
        item = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", 16)
        hash = item.as_json()
        self.assertEqual(len(hash.keys()), 8)
        self.assertListEqual(
            list(hash.keys()),
            [
                "name",
                "key",
                "bit_offset",
                "bit_size",
                "data_type",
                "endianness",
                "array_size",
                "overflow",
            ],
        )
        self.assertEqual(hash["name"], "TEST")
        self.assertEqual(hash["key"], "test")
        self.assertEqual(hash["bit_offset"], 0)
        self.assertEqual(hash["bit_size"], 8)
        self.assertEqual(hash["data_type"], "UINT")
        self.assertEqual(hash["endianness"], "BIG_ENDIAN")
        self.assertEqual(hash["array_size"], 16)
        self.assertEqual(hash["overflow"], "ERROR")

    def test_creates_structure_item_from_hash(self):
        item = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", 16)
        new_item = StructureItem.from_json(item.as_json())
        self.assertEqual(new_item.name, item.name)
        self.assertEqual(new_item.bit_offset, item.bit_offset)
        self.assertEqual(new_item.bit_size, item.bit_size)
        self.assertEqual(new_item.data_type, item.data_type)
        self.assertEqual(new_item.endianness, item.endianness)
        self.assertEqual(new_item.array_size, item.array_size)
        self.assertEqual(new_item.overflow, item.overflow)
