# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *

from openc3.packets.structure_item import StructureItem
from test.test_helper import *


class TestStructureItem(unittest.TestCase):
    def test_name_creates_new_structure_items(self):
        self.assertEqual(StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None).name, "TEST")

    def test_name_complains_about_non_string_names(self):
        self.assertRaisesRegex(
            TypeError,
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
            TypeError,
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
            ValueError,
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
            ValueError,
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
            self.assertEqual(StructureItem("test", 0, 32, type, "BIG_ENDIAN", None).data_type, type)

        self.assertEqual(
            StructureItem("test", 0, 0, "DERIVED", "BIG_ENDIAN", None).data_type,
            "DERIVED",
        )

    def test_complains_about_bad_data_type(self):
        self.assertRaisesRegex(
            ValueError,
            "TEST: unknown data_type: UNKNOWN - Must be INT, UINT, FLOAT, STRING, BLOCK, BOOL, OBJECT, ARRAY, ANY, DERIVED",
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
            ValueError,
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
            TypeError,
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
                ValueError,
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
            ValueError,
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
            TypeError,
            "TEST: bit_size must be an Integer",
            StructureItem,
            "TEST",
            0,
            None,
            "UINT",
            "BIG_ENDIAN",
            None,
        )

    def test_complains_about_0_size_floats(self):
        self.assertRaisesRegex(
            ValueError,
            "TEST: bit_size cannot be negative or zero for 'FLOAT' items: 0",
            StructureItem,
            "TEST",
            0,
            0,
            "FLOAT",
            "BIG_ENDIAN",
            None,
        )

    def test_complains_about_bad_float_bit_sizes(self):
        self.assertRaisesRegex(
            ValueError,
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
        self.assertEqual(StructureItem("test", 0, 32, "FLOAT", "BIG_ENDIAN", None).bit_size, 32)
        self.assertEqual(StructureItem("test", 0, 64, "FLOAT", "BIG_ENDIAN", None).bit_size, 64)

    def test_complains_about_non_zero_derived_bit_sizes(self):
        self.assertRaisesRegex(
            ValueError,
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
            TypeError,
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
            ValueError,
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

    def test_sorts_items_with_same_bit_offset_according_to_create_index(self):
        # Items with same bit_offset are sorted by create_index (creation order)
        si1 = StructureItem("si1", 0, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 0, "BLOCK", "BIG_ENDIAN", None)
        # si1 was created first (lower create_index), so si1 < si2
        self.assertTrue(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertFalse(si1 > si2)

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

    def test_creates_a_dict(self):
        item = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", 16).as_json()
        self.assertEqual(len(item.keys()), 11)
        self.assertListEqual(
            list(item.keys()),
            [
                "name",
                "key",
                "bit_offset",
                "bit_size",
                "data_type",
                "endianness",
                "overflow",
                "overlap",
                "create_index",
                "hidden",
                "array_size",
            ],
        )

        self.assertEqual(item["name"], "TEST")
        self.assertEqual(item["key"], "test")
        self.assertEqual(item["bit_offset"], 0)
        self.assertEqual(item["bit_size"], 8)
        self.assertEqual(item["data_type"], "UINT")
        self.assertEqual(item["endianness"], "BIG_ENDIAN")
        self.assertEqual(item["overflow"], "ERROR")
        self.assertEqual(item["overlap"], False)
        self.assertEqual(item["hidden"], False)
        self.assertEqual(item["array_size"], 16)

    def test_key_setter_complains_about_non_string_key(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        with self.assertRaisesRegex(TypeError, "key must be a String but is a int"):
            si.key = 123

    def test_key_setter_complains_about_empty_key(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        with self.assertRaisesRegex(ValueError, "key must contain at least one character"):
            si.key = ""

    def test_key_setter_allows_none(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        si.key = None
        self.assertIsNone(si.key)

    def test_endianness_complains_about_non_string(self):
        self.assertRaisesRegex(
            TypeError,
            "TEST: endianness must be a String but is a int",
            StructureItem,
            "TEST",
            0,
            8,
            "UINT",
            123,
            None,
        )

    def test_data_type_complains_about_non_string(self):
        self.assertRaisesRegex(
            TypeError,
            "TEST: data_type must be a str but 123 is a int",
            StructureItem,
            "TEST",
            0,
            8,
            123,
            "BIG_ENDIAN",
            None,
        )

    def test_overflow_complains_about_non_string(self):
        self.assertRaisesRegex(
            TypeError,
            "TEST: overflow type must be a String",
            StructureItem,
            "TEST",
            0,
            8,
            "UINT",
            "BIG_ENDIAN",
            None,
            123,
        )

    def test_string_bit_size_must_be_byte_multiple(self):
        self.assertRaisesRegex(
            ValueError,
            "TEST: bit_size for STRING and BLOCK items must be byte multiples",
            StructureItem,
            "TEST",
            0,
            10,
            "STRING",
            "BIG_ENDIAN",
            None,
        )

    def test_variable_bit_size_setter_validates_dict(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        with self.assertRaisesRegex(TypeError, "TEST: variable_bit_size must be a dict"):
            si.variable_bit_size = "not a dict"

    def test_variable_bit_size_setter_validates_length_item_name(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        with self.assertRaisesRegex(
            TypeError,
            "TEST: variable_bit_size\\['length_item_name'\\] must be a String",
        ):
            si.variable_bit_size = {
                "length_item_name": 123,
                "length_value_bit_offset": 0,
                "length_bits_per_count": 8,
            }

    def test_variable_bit_size_setter_validates_length_value_bit_offset(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        with self.assertRaisesRegex(
            ValueError,
            "TEST: variable_bit_size\\['length_value_bit_offset'\\] must be an Integer",
        ):
            si.variable_bit_size = {
                "length_item_name": "LENGTH",
                "length_value_bit_offset": "not int",
                "length_bits_per_count": 8,
            }

    def test_variable_bit_size_setter_validates_length_bits_per_count(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        with self.assertRaisesRegex(
            ValueError,
            "TEST: variable_bit_size\\['length_bits_per_count'\\] must be an Integer",
        ):
            si.variable_bit_size = {
                "length_item_name": "LENGTH",
                "length_value_bit_offset": 0,
                "length_bits_per_count": "not int",
            }

    def test_variable_bit_size_setter_accepts_valid_dict(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        si.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        self.assertEqual(si.variable_bit_size["length_item_name"], "LENGTH")

    def test_eq_with_derived_items(self):
        si1 = StructureItem("si1", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        # DERIVED items are compared by create_index, not equal since different create_index
        self.assertFalse(si1 == si2)
        # Same item should be equal to itself
        self.assertTrue(si1 == si1)

    def test_eq_derived_vs_non_derived(self):
        si1 = StructureItem("si1", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 8, "UINT", "BIG_ENDIAN", None)
        # DERIVED is never equal to non-DERIVED
        self.assertFalse(si1 == si2)
        self.assertFalse(si2 == si1)

    def test_lt_with_derived_items(self):
        si1 = StructureItem("si1", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        # DERIVED items are sorted by create_index
        self.assertTrue(si1 < si2)
        self.assertFalse(si2 < si1)

    def test_lt_derived_vs_non_derived(self):
        si1 = StructureItem("si1", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 8, "UINT", "BIG_ENDIAN", None)
        # DERIVED comes before non-DERIVED
        self.assertTrue(si1 < si2)
        self.assertFalse(si2 < si1)

    def test_lt_with_variable_bit_size_same_offset(self):
        si1 = StructureItem("si1", 0, 8, "UINT", "BIG_ENDIAN", None)
        si1.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        si2 = StructureItem("si2", 0, 8, "UINT", "BIG_ENDIAN", None)
        # Variable bit size items come before regular items at same offset
        self.assertTrue(si1 < si2)

    def test_lt_both_variable_bit_size_same_offset(self):
        si1 = StructureItem("si1", 0, 8, "UINT", "BIG_ENDIAN", None)
        si1.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        si2 = StructureItem("si2", 0, 8, "UINT", "BIG_ENDIAN", None)
        si2.variable_bit_size = {
            "length_item_name": "LENGTH2",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        # Both have variable_bit_size, sorted by create_index
        self.assertTrue(si1 < si2)

    def test_little_endian_bit_field_returns_false_for_big_endian(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        self.assertFalse(si.little_endian_bit_field())

    def test_little_endian_bit_field_returns_false_for_non_int_types(self):
        si = StructureItem("test", 0, 32, "FLOAT", "LITTLE_ENDIAN", None)
        self.assertFalse(si.little_endian_bit_field())

    def test_little_endian_bit_field_returns_true_for_non_byte_aligned(self):
        si = StructureItem("test", 4, 4, "UINT", "LITTLE_ENDIAN", None)
        self.assertTrue(si.little_endian_bit_field())

    def test_little_endian_bit_field_returns_true_for_non_byte_multiple(self):
        # Use bit_offset of 8 so it's byte-aligned but bit_size is not a byte multiple
        si = StructureItem("test", 8, 12, "UINT", "LITTLE_ENDIAN", None)
        self.assertTrue(si.little_endian_bit_field())

    def test_little_endian_bit_field_returns_false_for_byte_aligned_byte_multiple(self):
        si = StructureItem("test", 0, 16, "UINT", "LITTLE_ENDIAN", None)
        self.assertFalse(si.little_endian_bit_field())

    def test_verify_overall_little_endian_bit_field_error(self):
        # Create a little-endian bit field that would have a negative lower bound
        self.assertRaisesRegex(
            ValueError,
            "TEST: LITTLE_ENDIAN bitfield with bit_offset 4 and bit_size 12 is invalid",
            StructureItem,
            "TEST",
            4,
            12,
            "UINT",
            "LITTLE_ENDIAN",
            None,
        )

    def test_as_json_with_variable_bit_size(self):
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        si.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        result = si.as_json()
        self.assertIn("variable_bit_size", result)
        self.assertEqual(result["variable_bit_size"]["length_item_name"], "LENGTH")

    def test_as_json_with_parent_item(self):
        parent = StructureItem("parent", 0, 32, "BLOCK", "BIG_ENDIAN", None)
        child = StructureItem("child", 0, 8, "UINT", "BIG_ENDIAN", None)
        child.parent_item = "PARENT"
        result = child.as_json()
        self.assertIn("parent_item", result)
        self.assertEqual(result["parent_item"], "PARENT")

    def test_as_json_with_structure(self):
        from openc3.packets.packet import Packet

        p = Packet("TGT", "PKT")
        si = StructureItem("test", 0, 8, "UINT", "BIG_ENDIAN", None)
        si.structure = p
        result = si.as_json()
        self.assertIn("structure", result)

    def test_sorts_items_with_derived_first(self):
        si1 = StructureItem("si1", 0, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        # DERIVED items should come before non-DERIVED
        self.assertFalse(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertTrue(si1 > si2)

    def test_sorts_variable_sized_items_before_fixed_at_same_offset(self):
        si1 = StructureItem("si1", 8, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 8, 0, "UINT", "BIG_ENDIAN", None)
        si2.variable_bit_size = {
            "length_item_name": "item1_length",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        # Variable bit size items should come before fixed at same offset
        self.assertFalse(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertTrue(si1 > si2)

        # Now test the opposite
        si1 = StructureItem("si1", 8, 0, "UINT", "BIG_ENDIAN", None)
        si1.variable_bit_size = {
            "length_item_name": "item1_length",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        si2 = StructureItem("si2", 8, 8, "UINT", "BIG_ENDIAN", None)
        self.assertTrue(si1 < si2)
        self.assertFalse(si1 == si2)
        self.assertFalse(si1 > si2)
