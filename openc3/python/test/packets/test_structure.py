# Copyright 2026 OpenC3, Inc.
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
from openc3.packets.structure import Structure
from openc3.packets.structure_item import StructureItem


class TestStructure(unittest.TestCase):
    def setUp(self):
        self.s = Structure()

    def test_complains_about_non_string_buffers(self):
        self.assertRaisesRegex(
            TypeError,
            r"wrong argument type list \(expected bytes\)",
            Structure,
            "BIG_ENDIAN",
            [],
        )

    def test_complains_about_unknown_data_types(self):
        self.assertRaisesRegex(
            ValueError,
            "Unknown endianness 'BLAH', must be 'BIG_ENDIAN' or 'LITTLE_ENDIAN'",
            Structure,
            "BLAH",
        )

    def test_creates_big_endian_structures(self):
        self.assertEqual(Structure("BIG_ENDIAN").default_endianness, "BIG_ENDIAN")

    def test_creates_little_endian_structures(self):
        self.assertEqual(Structure("LITTLE_ENDIAN").default_endianness, "LITTLE_ENDIAN")

    def test_returns_true_if_any_items_have_been_defined(self):
        self.assertFalse(self.s.defined())
        self.s.define_item("test1", 0, 8, "UINT")
        self.assertTrue(self.s.defined())

    def test_renames_a_previously_defined_item(self):
        self.assertIsNone(self.s.items.get("test1"))
        self.assertEqual(len(self.s.sorted_items), 0)
        self.s.define_item("test1", 0, 8, "UINT")
        self.assertIsNotNone(self.s.items["TEST1"])
        self.assertIsNotNone(self.s.sorted_items[0])
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.s.rename_item("TEST1", "TEST2")
        self.assertIsNone(self.s.items.get("TEST1"))
        self.assertIsNotNone(self.s.items["TEST2"])
        self.assertEqual(self.s.sorted_items[0].name, "TEST2")


class TestStructureDefineItem(unittest.TestCase):
    def setUp(self):
        self.s = Structure("BIG_ENDIAN")

    def test_adds_item_to_items_and_sorted_items(self):
        self.assertIsNone(self.s.items.get("test1"))
        self.assertEqual(len(self.s.sorted_items), 0)
        self.s.define_item("test1", 0, 8, "UINT")
        self.assertIsNotNone(self.s.items["TEST1"])
        self.assertIsNotNone(self.s.sorted_items[0])
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.defined_length, 1)
        self.assertTrue(self.s.fixed_size)
        self.assertEqual(self.s.buffer, b"\x00")

    def test_adds_items_with_negative_bit_offsets(self):
        self.s.define_item("test1", -8, 8, "UINT")
        self.assertEqual(self.s.defined_length, 1)
        self.s.define_item("test2", 0, 4, "UINT")
        self.assertEqual(self.s.defined_length, 2)
        self.s.define_item("test3", 4, 4, "UINT")
        self.assertEqual(self.s.defined_length, 2)
        self.s.define_item("test4", 16, 0, "BLOCK")
        self.assertEqual(self.s.defined_length, 3)
        self.s.define_item("test5", -16, 8, "UINT")
        self.assertEqual(self.s.defined_length, 4)
        self.assertFalse(self.s.fixed_size)
        self.s.buffer = b"\x12\x34\x56\x78"
        self.assertEqual(self.s.read("test1"), 0x78)
        self.assertEqual(self.s.read("test2"), 0x1)
        self.assertEqual(self.s.read("test3"), 0x2)
        self.assertEqual(self.s.read("test4"), b"\x56\x78")
        self.assertEqual(self.s.read("test5"), 0x56)

    def test_adds_item_with_negative_offset(self):
        self.assertRaisesRegex(
            ValueError,
            "TEST11: Can't define an item with array_size 128 greater than negative bit_offset -64",
            self.s.define_item,
            "test11",
            -64,
            8,
            "UINT",
            128,
        )
        self.assertRaisesRegex(
            ValueError,
            "TEST10: Can't define an item with negative array_size -64 and negative bit_offset -64",
            self.s.define_item,
            "test10",
            -64,
            8,
            "UINT",
            -64,
        )
        self.assertRaisesRegex(
            ValueError,
            "TEST9: Can't define an item with negative bit_size -64 and negative bit_offset -64",
            self.s.define_item,
            "test9",
            -64,
            -64,
            "BLOCK",
        )
        self.assertRaisesRegex(
            ValueError,
            "TEST8: bit_size cannot be negative or zero for array items",
            self.s.define_item,
            "test8",
            0,
            -32,
            "BLOCK",
            64,
        )
        self.assertRaisesRegex(
            ValueError,
            "TEST7: bit_size cannot be negative or zero for array items",
            self.s.define_item,
            "test7",
            0,
            0,
            "BLOCK",
            64,
        )
        self.assertRaisesRegex(
            ValueError,
            "TEST6: Can't define an item with bit_size 32 greater than negative bit_offset -24",
            self.s.define_item,
            "test6",
            -24,
            32,
            "UINT",
        )
        self.s.define_item("test5", -16, 8, "UINT")
        self.assertEqual(self.s.defined_length, 2)
        self.s.define_item("test1", -8, 8, "UINT")
        self.assertEqual(self.s.defined_length, 2)
        self.s.define_item("test2", 0, 4, "UINT")
        self.assertEqual(self.s.defined_length, 3)
        self.s.define_item("test3", 4, 4, "UINT")
        self.assertEqual(self.s.defined_length, 3)
        self.s.define_item("test4", 8, 0, "BLOCK")
        self.assertEqual(self.s.defined_length, 3)
        self.assertFalse(self.s.fixed_size)
        self.assertEqual(self.s.buffer, b"\x00\x00\x00")

    def test_recalculates_sorted_items_when_adding_multiple_items(self):
        self.s.define_item("test1", 8, 32, "UINT")
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.defined_length, 5)
        self.s.define_item("test2", 0, 8, "UINT")
        self.assertEqual(self.s.sorted_items[0].name, "TEST2")
        self.assertEqual(self.s.defined_length, 5)
        self.s.define_item("test3", 16, 8, "UINT")
        self.assertEqual(self.s.sorted_items[-1].name, "TEST3")
        self.assertEqual(self.s.defined_length, 5)
        self.assertTrue(self.s.fixed_size)
        self.assertEqual(self.s.buffer, b"\x00\x00\x00\x00\x00")

    def test_overwrites_existing_items(self):
        self.s.define_item("test1", 0, 8, "UINT")
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.items["TEST1"].bit_size, 8)
        self.assertEqual(self.s.items["TEST1"].data_type, "UINT")
        self.assertEqual(self.s.defined_length, 1)
        self.s.define_item("test1", 0, 16, "INT")
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.items["TEST1"].bit_size, 16)
        self.assertEqual(self.s.items["TEST1"].data_type, "INT")
        self.assertEqual(self.s.defined_length, 2)
        self.assertTrue(self.s.fixed_size)
        self.assertEqual(self.s.buffer, b"\x00\x00")

    def test_correctly_recalculates_bit_offsets(self):
        self.s.append_item("item1", 8, "UINT")
        self.s.append_item("item2", 2, "UINT")
        item = self.s.append_item("item3", 6, "UINT")
        item.variable_bit_size = {"length_item_name": "item2", "length_bits_per_count": 8, "length_value_bit_offset": 0}
        self.s.append_item("item4", 32, "UINT")
        self.s.append_item("item5", 32, "UINT")
        self.s.append_item("item6", 8, "UINT")
        item = self.s.append_item("item7", 0, "STRING")
        item.variable_bit_size = {"length_item_name": "item6", "length_bits_per_count": 8, "length_value_bit_offset": 0}
        self.s.append_item("item8", 16, "UINT")

        bit_offsets = []
        for item in self.s.sorted_items:
            bit_offsets.append(item.bit_offset)
        self.assertEqual(bit_offsets, [0, 8, 10, 16, 48, 80, 88, 88])

        self.s.buffer = ("\x00" * self.s.defined_length).encode("LATIN-1")

        bit_offsets = []
        for item in self.s.sorted_items:
            bit_offsets.append(item.bit_offset)
        self.assertEqual(bit_offsets, [0, 8, 10, 16, 48, 80, 88, 88])

        self.s.buffer = "\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00".encode("LATIN-1")

        bit_offsets = []
        for item in self.s.sorted_items:
            bit_offsets.append(item.bit_offset)
        self.assertEqual(bit_offsets, [0, 8, 10, 40, 72, 104, 112, 128])

        self.s.buffer = ("\x00" * 13).encode("LATIN-1")

        bit_offsets = []
        for item in self.s.sorted_items:
            bit_offsets.append(item.bit_offset)
        self.assertEqual(bit_offsets, [0, 8, 10, 16, 48, 80, 88, 88])


class TestStructureDefine(unittest.TestCase):
    def setUp(self):
        self.s = Structure()

    def test_adds_the_item_to_items_and_sorted_items(self):
        si = StructureItem("test1", 0, 8, "UINT", "BIG_ENDIAN")
        self.s.define(si)
        self.assertIsNotNone(self.s.items["TEST1"])
        self.assertIsNotNone(self.s.sorted_items[0])
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.defined_length, 1)
        self.assertTrue(self.s.fixed_size)

    def test_allows_items_to_be_defined_on_top_of_each_other(self):
        si = StructureItem("test1", 0, 8, "UINT", "BIG_ENDIAN")
        self.s.define(si)
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.items["TEST1"].bit_offset, 0)
        self.assertEqual(self.s.items["TEST1"].bit_size, 8)
        self.assertEqual(self.s.items["TEST1"].data_type, "UINT")
        self.assertEqual(self.s.defined_length, 1)
        si = StructureItem("test2", 0, 16, "INT", "BIG_ENDIAN")
        self.s.define(si)
        self.assertEqual(self.s.sorted_items[1].name, "TEST2")
        self.assertEqual(self.s.items["TEST2"].bit_offset, 0)
        self.assertEqual(self.s.items["TEST2"].bit_size, 16)
        self.assertEqual(self.s.items["TEST2"].data_type, "INT")
        self.assertEqual(self.s.defined_length, 2)
        buffer = b"\x01\x02"
        self.assertEqual(self.s.read_item(self.s.get_item("test1"), "RAW", buffer), 1)
        self.assertEqual(self.s.read_item(self.s.get_item("test2"), "RAW", buffer), 258)

    def test_overwrites_existing_items(self):
        si = StructureItem("test1", 0, 8, "UINT", "BIG_ENDIAN")
        self.s.define(si)
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.items["TEST1"].bit_size, 8)
        self.assertEqual(self.s.items["TEST1"].data_type, "UINT")
        self.assertEqual(self.s.defined_length, 1)
        si = StructureItem("test1", 0, 16, "INT", "BIG_ENDIAN")
        self.s.define(si)
        self.assertEqual(len(self.s.items), 1)
        self.assertEqual(len(self.s.sorted_items), 1)
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.items["TEST1"].bit_size, 16)
        self.assertEqual(self.s.items["TEST1"].data_type, "INT")
        self.assertEqual(self.s.defined_length, 2)
        self.assertTrue(self.s.fixed_size)


class TestStructureAppendItem(unittest.TestCase):
    def setUp(self):
        self.s = Structure()

    def test_appends_an_item_to_items(self):
        self.s.define_item("test1", 0, 8, "UINT")
        self.s.append_item("test2", 16, "UINT")
        self.assertEqual(self.s.items["TEST2"].bit_size, 16)
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.sorted_items[1].name, "TEST2")
        self.assertEqual(self.s.defined_length, 3)

    def test_appends_an_item_after_an_array_item(self):
        self.s.define_item("test1", 0, 8, "UINT", 16)
        self.assertEqual(self.s.items["TEST1"].bit_size, 8)
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(len(self.s.sorted_items), 1)
        self.assertEqual(self.s.defined_length, 2)
        self.s.append_item("test2", 16, "UINT")
        self.assertEqual(self.s.items["TEST2"].bit_size, 16)
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.sorted_items[1].name, "TEST2")
        self.assertEqual(self.s.defined_length, 4)


class TestStructureAppend(unittest.TestCase):
    def setUp(self):
        self.s = Structure()

    def test_appends_an_item_to_the_structure(self):
        self.s.define_item("test1", 0, 8, "UINT")
        item = StructureItem("test2", 0, 16, "UINT", "BIG_ENDIAN")
        self.s.append(item)
        # Bit offset should change because we appended the item
        self.assertEqual(self.s.items["TEST2"].bit_offset, 8)
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.sorted_items[1].name, "TEST2")
        self.assertEqual(self.s.defined_length, 3)


class TestStructureGetItem(unittest.TestCase):
    def setUp(self):
        self.s = Structure()
        self.s.define_item("test1", 0, 8, "UINT")

    def test_returns_a_defined_item(self):
        self.assertIsNotNone(self.s.get_item("test1"))

    def test_complains_if_an_item_doesnt_exist(self):
        self.assertRaisesRegex(ValueError, "Unknown item: test2", self.s.get_item, "test2")


class TestStructureSetItem(unittest.TestCase):
    def setUp(self):
        self.s = Structure()
        self.s.define_item("test1", 0, 8, "UINT")

    def test_sets_a_defined_item(self):
        item = self.s.get_item("test1")
        self.assertEqual(item.bit_size, 8)
        item.bit_size = 16
        self.s.set_item(item)
        self.assertEqual(self.s.get_item("test1").bit_size, 16)

    def test_complains_if_an_item_doesnt_exist(self):
        item = self.s.get_item("test1")
        item.name = "TEST2"
        self.assertRaisesRegex(
            ValueError,
            "Unknown item: TEST2 - Ensure item name is uppercase",
            self.s.set_item,
            item,
        )


class TestStructureDeleteItem(unittest.TestCase):
    def setUp(self):
        self.s = Structure("BIG_ENDIAN")
        self.s.define_item("test1", 0, 8, "UINT")

    def test_removes_the_item_and_leaves_a_hole(self):
        self.s.append_item("test2", 16, "UINT")
        self.assertEqual(self.s.defined_length, 3)
        self.s.delete_item("test1")
        self.assertRaisesRegex(ValueError, "Unknown item: test1", self.s.get_item, "test1")
        self.assertEqual(self.s.defined_length, 3)
        self.assertIsNone(self.s.items.get("TEST1"))
        self.assertIsNotNone(self.s.items["TEST2"])
        self.assertEqual(len(self.s.sorted_items), 1)
        self.assertEqual(self.s.sorted_items[0], self.s.get_item("test2"))
        buffer = b"\x01\x02\x03"
        self.assertEqual(self.s.read("test2", "RAW", buffer), 0x0203)

    def test_allows_new_items_to_be_defined_in_place(self):
        self.s.append_item("test2", 16, "UINT")
        self.s.append_item("test3", 8, "UINT")
        self.assertEqual(self.s.defined_length, 4)
        # Delete the first 2 items, note a 3 byte hole now exists
        self.s.delete_item("test1")
        self.s.delete_item("test2")
        self.assertEqual(self.s.defined_length, 4)
        self.assertEqual(len(self.s.items), 1)
        self.assertEqual(len(self.s.sorted_items), 1)
        # Fill the hole and overlap the last byte
        self.s.define_item("test4", 0, 16, "UINT")
        self.s.define_item("test5", 16, 16, "UINT")
        self.s.define_item("test6", 32, 32, "UINT")
        buffer = b"\x01\x02\x03\x04\x05\x06\x07\x08"
        self.assertEqual(self.s.read("test4", "RAW", buffer), 0x0102)
        self.assertEqual(self.s.read("test5", "RAW", buffer), 0x0304)
        self.assertEqual(self.s.read("test6", "RAW", buffer), 0x05060708)
        # test3 is still defined
        self.assertEqual(self.s.read("test3", "RAW", buffer), 0x04)
        self.assertEqual(len(self.s.items), 4)
        self.assertEqual(len(self.s.sorted_items), 4)
        # Check that everything is sorted correctly
        self.assertEqual(self.s.sorted_items[0].name, "TEST4")
        self.assertEqual(self.s.sorted_items[1].name, "TEST5")
        self.assertEqual(self.s.sorted_items[2].name, "TEST3")
        self.assertEqual(self.s.sorted_items[3].name, "TEST6")


class TestStructureReadItem(unittest.TestCase):
    def test_works_if_no_buffer_given(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT")
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", None), 0)

    def test_reads_data_from_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT")
        buffer = b"\x01"
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", buffer), 1)

    def test_reads_array_data_from_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT", 16)
        buffer = b"\x01\x02"
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", buffer), [1, 2])


class TestStructureWriteItem(unittest.TestCase):
    def test_works_if_no_buffer_given(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT")
        s.write_item(s.get_item("test1"), 1, "RAW", None)
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", None), 1)

    def test_writes_data_to_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT")
        buffer = bytearray(b"\x01")
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", buffer), 1)
        s.write_item(s.get_item("test1"), 2, "RAW", buffer)
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", buffer), 2)

    def test_writes_array_data_to_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT", 16)
        buffer = bytearray(b"\x01\x02")
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", buffer), [1, 2])
        s.write_item(s.get_item("test1"), [3, 4], "RAW", buffer)
        self.assertEqual(s.read_item(s.get_item("test1"), "RAW", buffer), [3, 4])


class TestStructureRead(unittest.TestCase):
    def test_complains_if_item_doesnt_exist(self):
        self.assertRaisesRegex(ValueError, "Unknown item: BLAH", Structure().read, "BLAH")

    def test_reads_data_from_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT")
        buffer = b"\x01"
        self.assertEqual(s.read("test1", "RAW", buffer), 1)

    def test_reads_until_null_byte_for_string_items(self):
        s = Structure()
        s.define_item("test1", 0, 80, "STRING")
        buffer = b"\x4e\x4f\x4f\x50\x00\x4e\x4f\x4f\x50\x0a"  # NOOP<NULL>NOOP\n
        self.assertEqual(s.read("test1", "CONVERTED", buffer), "NOOP")

    def test_reads_the_entire_buffer_for_block_items(self):
        s = Structure()
        s.define_item("test1", 0, 80, "BLOCK")
        buffer = b"\x4e\x4f\x4f\x50\x00\x4e\x4f\x4f\x50\x0a"  # NOOP<NULL>NOOP\n
        self.assertEqual(s.read("test1", "CONVERTED", buffer), b"NOOP\x00NOOP\n")

    def test_reads_array_data_from_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT", 16)
        buffer = b"\x01\x02"
        self.assertEqual(s.read("test1", "RAW", buffer), [1, 2])


class TestStructureWrite(unittest.TestCase):
    def test_complains_if_item_doesnt_exist(self):
        with self.assertRaisesRegex(ValueError, "Unknown item: BLAH"):
            Structure().write("BLAH", 0)

    def test_writes_data_to_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT")
        buffer = bytearray(b"\x01")
        self.assertEqual(s.read("test1", "RAW", buffer), 1)
        s.write("test1", 2, "RAW", buffer)
        self.assertEqual(s.read("test1", "RAW", buffer), 2)

    def test_writes_array_data_to_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT", 16)
        buffer = bytearray(b"\x01\x02")
        self.assertEqual(s.read("test1", "RAW", buffer), [1, 2])
        s.write("test1", [3, 4], "RAW", buffer)
        self.assertEqual(s.read("test1", "RAW", buffer), [3, 4])


class TestStructureReadAll(unittest.TestCase):
    def test_reads_all_defined_items(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.append_item("test2", 16, "UINT")
        s.append_item("test3", 32, "UINT")

        buffer = b"\x01\x02\x03\x04\x05\x06\x07\x08"
        vals = s.read_all("RAW", buffer)
        self.assertEqual(vals[0][0], "TEST1")
        self.assertEqual(vals[1][0], "TEST2")
        self.assertEqual(vals[2][0], "TEST3")
        self.assertEqual(vals[0][1], [1, 2])
        self.assertEqual(vals[1][1], 0x0304)
        self.assertEqual(vals[2][1], 0x05060708)

    def test_reads_all_defined_items_synchronized(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.append_item("test2", 16, "UINT")
        s.append_item("test3", 32, "UINT")

        buffer = b"\x01\x02\x03\x04\x05\x06\x07\x08"
        vals = s.read_all("RAW", buffer, False)
        self.assertEqual(vals[0][0], "TEST1")
        self.assertEqual(vals[1][0], "TEST2")
        self.assertEqual(vals[2][0], "TEST3")
        self.assertEqual(vals[0][1], [1, 2])
        self.assertEqual(vals[1][1], 0x0304)
        self.assertEqual(vals[2][1], 0x05060708)


class TestStructureFormatted(unittest.TestCase):
    def test_prints_out_all_the_items_and_values(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 3456)
        s.append_item("test3", 32, "BLOCK")
        s.write("test3", b"\x07\x08\x09\x0a")
        self.assertIn("TEST1: [1, 2]", s.formatted())
        self.assertIn("TEST2: 3456", s.formatted())
        self.assertIn("TEST3", s.formatted())
        self.assertIn("00000000: 07 08 09 0A", s.formatted())


# def test_alters_the_indentation_of_the_item(self):
#     s = Structure('BIG_ENDIAN')
#     s.append_item("test1", 8, 'UINT', 16)
#     s.write("test1", [1, 2])
#     s.append_item("test2", 16, 'UINT')
#     s.write("test2", 3456)
#     s.append_item("test3", 32, 'BLOCK')
#     s.write("test3", "\x07\x08\x09\x0A")
#     expect(s.formatted('CONVERTED', 4)).to include("    TEST1: [1, 2]")
#     expect(s.formatted('CONVERTED', 4)).to include("    TEST2: 3456")
#     expect(s.formatted('CONVERTED', 4)).to include("    TEST3")
#     expect(s.formatted('CONVERTED', 4)).to include("    00000000: 07 08 09 0A")

# def test_processes_uses_a_different_buffer(self):
#     s = Structure('BIG_ENDIAN')
#     s.append_item("test1", 8, 'UINT', 16)
#     s.write("test1", [1, 2])
#     s.append_item("test2", 16, 'UINT')
#     s.write("test2", 3456)
#     s.append_item("test3", 32, 'BLOCK')
#     s.write("test3", "\x07\x08\x09\x0A")
#     buffer = "\x0A\x0B\x0C\x0D\xDE\xAD\xBE\xEF"
#     expect(s.formatted('CONVERTED', 0, buffer)).to include("TEST1: [10, 11]")
#     expect(s.formatted('CONVERTED', 0, buffer)).to include("TEST2: 0x0C0D")
#     expect(s.formatted('CONVERTED', 0, buffer)).to include("TEST3")
#     expect(s.formatted('CONVERTED', 0, buffer)).to include("00000000: DE AD BE EF")

# def test_ignores_items(self):
#     s = Structure('BIG_ENDIAN')
#     s.append_item("test1", 8, 'UINT', 16)
#     s.write("test1", [1, 2])
#     s.append_item("test2", 16, 'UINT')
#     s.write("test2", 3456)
#     s.append_item("test3", 32, 'BLOCK')
#     s.write("test3", "\x07\x08\x09\x0A")
#     expect(s.formatted('CONVERTED', 0, s.buffer, %w(TEST1 TEST3))).to eq("TEST2: 3456\n")
#     expect(s.formatted('CONVERTED', 0, s.buffer, %w(TEST1 TEST2 TEST3))).to eq("")


class TestStructureBuffer(unittest.TestCase):
    def test_returns_the_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 0x0304)
        s.append_item("test3", 32, "UINT")
        s.write("test3", 0x05060708)
        self.assertEqual(s.buffer, b"\x01\x02\x03\x04\x05\x06\x07\x08")
        self.assertIsNot(s.buffer, s.buffer)
        self.assertIs(s.buffer_no_copy(), s.buffer_no_copy())

    def test_complains_if_the_given_buffer_is_too_small(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 16, "UINT")
        with self.assertRaisesRegex(ValueError, "Buffer length less than defined length"):
            s.buffer = b"\x00"

    def test_complains_if_the_given_buffer_is_too_big(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 16, "UINT")
        with self.assertRaisesRegex(ValueError, "Buffer length greater than defined length"):
            s.buffer = b"\x00\x00\x00"

    def test_does_not_complain_if_the_given_buffer_is_too_big_and_were_not_fixed_length(
        self,
    ):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.append_item("test2", 0, "BLOCK")
        s.buffer = b"\x01\x02\x03"
        self.assertEqual(s.read("test1"), 1)
        self.assertEqual(s.read("test2"), b"\x02\x03")

    def test_sets_the_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 0x0304)
        s.append_item("test3", 32, "UINT")
        s.write("test3", 0x05060708)
        self.assertEqual(s.read("test1"), [1, 2])
        self.assertEqual(s.read("test2"), 0x0304)
        self.assertEqual(s.read("test3"), 0x05060708)
        s.buffer = b"\x00\x01\x02\x03\x04\x05\x06\x07"
        self.assertEqual(s.read("test1"), [0, 1])
        self.assertEqual(s.read("test2"), 0x0203)
        self.assertEqual(s.read("test3"), 0x04050607)

    def test_duplicates_the_structure_with_a_new_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 0x0304)
        s.append_item("test3", 32, "UINT")
        s.write("test3", 0x05060708)
        # Get a reference to the original buffer
        old_buffer = s.buffer_no_copy()

        s2 = s.clone()
        # Ensure we didn't modify the original buffer object
        self.assertIs(s.buffer_no_copy(), old_buffer)
        # Check that they are equal in value
        self.assertEqual(s2.buffer_no_copy(), s.buffer_no_copy())
        # But not the same object
        # self.assertIsNot(s2.buffer_no_copy(), s.buffer_no_copy())
        self.assertEqual(s2.read("test1"), [1, 2])
        self.assertEqual(s2.read("test2"), 0x0304)
        self.assertEqual(s2.read("test3"), 0x05060708)
        s2.write("test1", [0, 0])
        self.assertEqual(s2.read("test1"), [0, 0])
        # Ensure we didn't change the original
        self.assertEqual(s.read("test1"), [1, 2])

    def test_deep_copy(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 0x0304)
        s.append_item("test3", 32, "UINT")
        s.write("test3", 0x05060708)

        s2 = s.deep_copy()
        self.assertEqual(s.items["TEST1"].overflow, "ERROR")
        self.assertEqual(s2.items["TEST1"].overflow, "ERROR")
        # Change something about the item in the original
        s.items["TEST1"].overflow = "SATURATE"
        self.assertEqual(s.items["TEST1"].overflow, "SATURATE")
        # Verify the deep_copy didn't change
        self.assertEqual(s2.items["TEST1"].overflow, "ERROR")


class TestStructureLength(unittest.TestCase):
    def test_returns_length_of_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 16, "UINT")
        self.assertEqual(s.length(), 2)

    def test_allocates_buffer_if_needed(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 32, "UINT")
        # Buffer is None until accessed
        self.assertEqual(s.length(), 4)


class TestStructureResizeBuffer(unittest.TestCase):
    def test_resizes_buffer_if_smaller_than_defined_length(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 32, "UINT")
        s._buffer = bytearray(b"\x00")  # Set buffer smaller than defined
        s.resize_buffer()
        self.assertEqual(len(s._buffer), 4)

    def test_allocates_buffer_if_none(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 16, "UINT")
        s._buffer = None
        s.resize_buffer()
        self.assertEqual(len(s._buffer), 2)


class TestStructureAccessor(unittest.TestCase):
    def test_returns_accessor(self):
        s = Structure("BIG_ENDIAN")
        from openc3.accessors.binary_accessor import BinaryAccessor

        self.assertIsInstance(s.accessor, BinaryAccessor)


class TestStructureReadItems(unittest.TestCase):
    def test_reads_multiple_items_from_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.append_item("test2", 16, "UINT")
        items = [s.get_item("test1"), s.get_item("test2")]
        buffer = b"\x01\x02\x03"
        result = s.read_items(items, "RAW", buffer)
        self.assertEqual(result["TEST1"], 1)
        self.assertEqual(result["TEST2"], 0x0203)

    def test_allocates_buffer_if_none(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        items = [s.get_item("test1")]
        result = s.read_items(items, "RAW", None)
        self.assertEqual(result["TEST1"], 0)


class TestStructureWriteItems(unittest.TestCase):
    def test_writes_multiple_items_to_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.append_item("test2", 16, "UINT")
        items = [s.get_item("test1"), s.get_item("test2")]
        values = [5, 0x0A0B]
        s.write_items(items, values)
        self.assertEqual(s.read("test1"), 5)
        self.assertEqual(s.read("test2"), 0x0A0B)

    def test_allocates_buffer_if_none(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        items = [s.get_item("test1")]
        values = [10]
        s._buffer = None
        s.write_items(items, values, "RAW", None)
        self.assertEqual(s.read("test1"), 10)


class TestStructureAppendItemDerived(unittest.TestCase):
    def test_appends_derived_item_at_offset_zero(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.append_item("derived1", 0, "DERIVED")
        # DERIVED item should have bit_offset of 0 regardless of defined_length_bits
        self.assertEqual(s.items["DERIVED1"].bit_offset, 0)


class TestStructureAppendDerived(unittest.TestCase):
    def test_appends_derived_item_to_structure(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        item = StructureItem("derived1", 0, 0, "DERIVED", "BIG_ENDIAN", None)
        s.append(item)
        self.assertEqual(s.items["DERIVED1"].bit_offset, 0)


class TestStructureSetItemVariableBitSize(unittest.TestCase):
    def test_handles_variable_bit_size_uint(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("length", 8, "UINT")
        s.append_item("data", 8, "UINT")
        item = s.get_item("data")
        item.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        s.set_item(item)

    def test_handles_variable_bit_size_with_length_value_bit_offset(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("length", 8, "UINT")
        item = s.append_item("data", 0, "STRING")
        item.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 8,
            "length_bits_per_count": 8,
        }
        original_length = s.defined_length_bits
        s.set_item(item)
        # defined_length_bits should increase due to minimum_data_bits
        self.assertGreater(s.defined_length_bits, original_length)

    def test_array_with_zero_size_not_treated_as_quic_integer(self):
        """
        Test that arrays with original_array_size=0 are NOT treated as QUIC integers.

        This test ensures the fix for the Python-specific bug where:
        - `not item.original_array_size` incorrectly returned True for arrays with original_array_size=0
        - In Python, `not 0` is True, but 0 means "this is an array with zero initial size"
        - This was causing arrays to be treated as QUIC integers, adding 6 bits to defined_length_bits

        Without the fix (using `not item.original_array_size`):
        - ARRAY1 would be treated as QUIC integer, adding 6 bits
        - ARRAY2_LENGTH would be at bit_offset 38 instead of 32

        With the fix (using `item.original_array_size is None`):
        - ARRAY1 is correctly identified as an array
        - ARRAY2_LENGTH is at bit_offset 32 (same as ARRAY1 since ARRAY1 has 0 size)
        """
        s = Structure("BIG_ENDIAN")
        # Define ARRAY1_LENGTH (32 bits)
        s.append_item("ARRAY1_LENGTH", 32, "UINT")
        # Define ARRAY1 as an array with 0 initial size
        item = s.append_item("ARRAY1", 8, "UINT", 0)  # array_size=0
        item.variable_bit_size = {
            "length_item_name": "ARRAY1_LENGTH",
            "length_bits_per_count": 8,
            "length_value_bit_offset": 0,
        }
        s.set_item(item)

        # ARRAY1 is at bit_offset 32 (after ARRAY1_LENGTH)
        self.assertEqual(s.get_item("ARRAY1").bit_offset, 32)

        # defined_length_bits should still be 32 (ARRAY1_LENGTH only, since ARRAY1 has 0 size)
        # If the bug were present, it would be 38 (32 + 6 for QUIC minimum)
        self.assertEqual(s.defined_length_bits, 32)

        # Now append ARRAY2_LENGTH - it should be at bit_offset 32 (same as ARRAY1 since ARRAY1 has 0 size)
        s.append_item("ARRAY2_LENGTH", 32, "UINT")
        self.assertEqual(s.get_item("ARRAY2_LENGTH").bit_offset, 32)

        # Define ARRAY2 as an array with 0 initial size
        item2 = s.append_item("ARRAY2", 8, "UINT", 0)  # array_size=0
        item2.variable_bit_size = {
            "length_item_name": "ARRAY2_LENGTH",
            "length_bits_per_count": 8,
            "length_value_bit_offset": 0,
        }
        s.set_item(item2)

        # ARRAY2 should be at bit_offset 64 (after both LENGTH fields)
        self.assertEqual(s.get_item("ARRAY2").bit_offset, 64)

        # Total defined_length should be 8 bytes (64 bits)
        self.assertEqual(s.defined_length_bits, 64)
        self.assertEqual(s.defined_length, 8)


class TestStructureDeleteItemError(unittest.TestCase):
    def test_complains_if_item_doesnt_exist(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        with self.assertRaises(KeyError):
            s.delete_item("nonexistent")


class TestStructureFormattedHiddenItems(unittest.TestCase):
    def test_skips_hidden_items(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.write("test1", 5)
        s.append_item("test2", 8, "UINT")
        s.write("test2", 10)
        s.items["TEST2"].hidden = True
        result = s.formatted()
        self.assertIn("TEST1: 5", result)
        self.assertNotIn("TEST2", result)

    def test_skips_ignored_items(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.write("test1", 5)
        s.append_item("test2", 8, "UINT")
        s.write("test2", 10)
        result = s.formatted("RAW", 0, None, ["TEST2"])
        self.assertIn("TEST1: 5", result)
        self.assertNotIn("TEST2", result)

    def test_handles_non_bytes_block_value(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 32, "BLOCK")
        # Set buffer directly so block reads back correctly
        s.buffer = b"\x01\x02\x03\x04"
        result = s.formatted()
        self.assertIn("TEST1", result)


class TestStructureReadAllBuffer(unittest.TestCase):
    def test_uses_internal_buffer_if_none_provided(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.write("test1", 42)
        vals = s.read_all("RAW", None)
        self.assertEqual(vals[0][1], 42)


class TestStructureSynchronize(unittest.TestCase):
    def test_returns_mutex(self):
        s = Structure("BIG_ENDIAN")
        with s.synchronize():
            pass  # Just test that we can acquire and release the mutex

    def test_synchronize_allow_reads_non_blocking(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.write("test1", 1)
        # Call with top=False which enters non-blocking path
        with s.synchronize_allow_reads(False):
            val = s.read("test1")
            self.assertEqual(val, 1)


class TestStructureCalculateTotalBitSize(unittest.TestCase):
    def test_calculates_quic_encoded_integer_bit_size(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("length", 2, "UINT")
        s.append_item("data", 8, "UINT")
        item = s.get_item("data")
        item.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        # Test different length values for QUIC encoding
        s.write("length", 0)
        self.assertEqual(s.calculate_total_bit_size(item), 6)  # case 0

        s.write("length", 1)
        self.assertEqual(s.calculate_total_bit_size(item), 14)  # case 1

        s.write("length", 2)
        self.assertEqual(s.calculate_total_bit_size(item), 30)  # case 2

        s.write("length", 3)
        self.assertEqual(s.calculate_total_bit_size(item), 62)  # case _ (default)

    def test_calculates_variable_string_bit_size(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("length", 8, "UINT")
        s.append_item("data", 0, "STRING")
        item = s.get_item("data")
        item.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 8,
            "length_bits_per_count": 8,
        }
        s.write("length", 5)
        result = s.calculate_total_bit_size(item)
        # 5 * 8 + 8 = 48
        self.assertEqual(result, 48)

    def test_calculates_size_for_negative_bit_size_items(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        item = s.append_item("data", 0, "BLOCK")
        s.buffer = b"\x00\x01\x02\x03\x04"
        # Item with original_bit_size == 0 (variable length)
        result = s.calculate_total_bit_size(item)
        # (5 * 8) - 8 + 0 = 32 bits
        self.assertEqual(result, 32)

    def test_calculates_size_for_negative_array_size_items(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.define_item("data", 8, 8, "UINT", -8)  # negative array_size
        item = s.get_item("data")
        s.buffer = b"\x00\x01\x02\x03\x04"
        result = s.calculate_total_bit_size(item)
        # (5 * 8) - 8 + (-8) = 24 bits
        self.assertEqual(result, 24)

    def test_raises_for_non_variable_sized_item(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        item = s.get_item("test1")
        with self.assertRaisesRegex(RuntimeError, "Unexpected use of calculate_total_bit_size"):
            s.calculate_total_bit_size(item)


class TestStructureRecalculateBitOffsets(unittest.TestCase):
    def test_skips_parented_items(self):
        s = Structure("BIG_ENDIAN")
        parent = s.append_item("parent", 32, "BLOCK")
        s.append_item("child", 8, "UINT")
        child = s.get_item("child")
        child.parent_item = parent
        # Just verify it doesn't crash when processing parented items
        s.recalculate_bit_offsets()

    def test_handles_variable_array_size(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("length", 8, "UINT")
        item = s.define_item("data", 8, 8, "UINT", 0)  # array_size = 0
        item.variable_bit_size = {
            "length_item_name": "LENGTH",
            "length_value_bit_offset": 0,
            "length_bits_per_count": 8,
        }
        s.append_item("after", 8, "UINT")
        s.write("length", 2)  # 2 * 8 = 16 bits
        s.buffer = b"\x02\x00\x00\x00"
        s.recalculate_bit_offsets()


class TestStructureInternalBufferEquals(unittest.TestCase):
    def test_complains_about_non_bytes_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        with self.assertRaisesRegex(TypeError, "Buffer class is list but must be bytearray"):
            s.buffer = [1, 2, 3]


class TestStructureDefineNegativeArraySize(unittest.TestCase):
    def test_handles_negative_array_size_in_define(self):
        s = Structure("BIG_ENDIAN")
        s.define_item("test1", 0, 8, "UINT", -16)
        self.assertEqual(s.items["TEST1"].array_size, -16)
        self.assertFalse(s.fixed_size)


class TestStructureWithBytesBuffer(unittest.TestCase):
    def test_accepts_bytes_buffer_in_constructor(self):
        s = Structure("BIG_ENDIAN", b"\x01\x02\x03\x04")
        s.append_item("test1", 32, "UINT")
        self.assertEqual(s.read("test1"), 0x01020304)


class TestStructureReadItemNoBuffer(unittest.TestCase):
    def test_allocates_buffer_when_both_buffers_are_none(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s._buffer = None  # Explicitly set internal buffer to None
        # read_item should allocate buffer when both param and _buffer are None
        result = s.read_item(s.get_item("test1"), "RAW", None)
        self.assertEqual(result, 0)


class TestStructureWriteItemNoBuffer(unittest.TestCase):
    def test_allocates_buffer_when_both_buffers_are_none(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s._buffer = None  # Explicitly set internal buffer to None
        # write_item should allocate buffer when both param and _buffer are None
        s.write_item(s.get_item("test1"), 5, "RAW", None)
        self.assertEqual(s.read("test1"), 5)


class TestStructureReadItemsNoBuffer(unittest.TestCase):
    def test_allocates_buffer_when_both_buffers_are_none(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        items = [s.get_item("test1")]
        s._buffer = None  # Explicitly set internal buffer to None
        # read_items should allocate buffer when both param and _buffer are None
        result = s.read_items(items, "RAW", None)
        self.assertEqual(result["TEST1"], 0)


class TestStructureSynchronizeAllowReadsMutexHeld(unittest.TestCase):
    def test_yields_when_mutex_already_held(self):
        import threading

        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT")
        s.write("test1", 42)
        # First acquire mutex with top=True, then call with top=False
        # This should hit the else branch where mutex_allow_reads is set
        with s.synchronize_allow_reads(True):
            # Inside top-level context, call again with top=False
            with s.synchronize_allow_reads(False):
                val = s.read("test1")
                self.assertEqual(val, 42)


class TestStructureItemComparison(unittest.TestCase):
    def test_lt_other_has_variable_bit_size_self_does_not(self):
        si1 = StructureItem("si1", 0, 8, "UINT", "BIG_ENDIAN", None)
        si2 = StructureItem("si2", 0, 8, "UINT", "BIG_ENDIAN", None)
        si2.variable_bit_size = {"length_item_name": "LENGTH", "length_value_bit_offset": 0, "length_bits_per_count": 8}
        # si2 has variable_bit_size, si1 does not
        # Variable bit size items should come before regular items, so si2 < si1 is True, si1 < si2 is False
        self.assertFalse(si1 < si2)
        self.assertTrue(si2 < si1)


class TestStructureDefineItemRecalculateBitOffsets(unittest.TestCase):
    def test_recalculates_the_bit_offsets_for_0_size(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 40, "BLOCK")
        s.append_item("test2", 0, "BLOCK")
        s.define_item("test3", -32, 16, "UINT")
        s.define_item("test4", -16, 16, "UINT")
        s.buffer = b"\x01\x02\x03\x04\x05\x0a\x0b\x0b\x0a\xaa\x55\xbb\x66"
        self.assertEqual(s.read("test1"), b"\x01\x02\x03\x04\x05")
        self.assertEqual(s.read("test2"), b"\x0a\x0b\x0b\x0a\xaa\x55\xbb\x66")
        self.assertEqual(s.read("test3"), 0xAA55)
        self.assertEqual(s.read("test4"), 0xBB66)


class TestStructureWriteFullSize64BitIntegers(unittest.TestCase):
    def test_writes_full_size_64_bit_integers(self):
        from openc3.accessors.binary_accessor import BinaryAccessor

        s = Structure("BIG_ENDIAN")
        s.define_item("test1", 0, 64, "UINT")
        s.define_item("test2", 64, 64, "INT")
        buffer = bytearray(b"\x00" * 16)
        self.assertEqual(s.read("test1", "RAW", buffer), 0)
        self.assertEqual(s.read("test2", "RAW", buffer), 0)
        s.write("test1", BinaryAccessor.MAX_UINT64, "RAW", buffer)
        self.assertEqual(s.read("test1", "RAW", buffer), BinaryAccessor.MAX_UINT64)
        s.write("test2", BinaryAccessor.MIN_INT64, "RAW", buffer)
        self.assertEqual(s.read("test2", "RAW", buffer), BinaryAccessor.MIN_INT64)
        s.write("test2", BinaryAccessor.MAX_INT64, "RAW", buffer)
        self.assertEqual(s.read("test2", "RAW", buffer), BinaryAccessor.MAX_INT64)


class TestStructureFormattedIndentation(unittest.TestCase):
    def test_alters_the_indentation_of_the_item(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 3456)
        s.append_item("test3", 32, "BLOCK")
        s.write("test3", b"\x07\x08\x09\x0a")
        self.assertIn("    TEST1: [1, 2]", s.formatted("CONVERTED", 4))
        self.assertIn("    TEST2: 3456", s.formatted("CONVERTED", 4))
        self.assertIn("    TEST3", s.formatted("CONVERTED", 4))
        self.assertIn("    00000000: 07 08 09 0A", s.formatted("CONVERTED", 4))

    def test_processes_uses_a_different_buffer(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 3456)
        s.append_item("test3", 32, "BLOCK")
        s.write("test3", b"\x07\x08\x09\x0a")
        buffer = b"\x0a\x0b\x0c\x0d\xde\xad\xbe\xef"
        self.assertIn("TEST1: [10, 11]", s.formatted("CONVERTED", 0, buffer))
        self.assertIn("TEST2: 3085", s.formatted("CONVERTED", 0, buffer))
        self.assertIn("TEST3", s.formatted("CONVERTED", 0, buffer))
        self.assertIn("00000000: DE AD BE EF", s.formatted("CONVERTED", 0, buffer))

    def test_ignores_items(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        s.append_item("test2", 16, "UINT")
        s.write("test2", 3456)
        s.append_item("test3", 32, "BLOCK")
        s.write("test3", b"\x07\x08\x09\x0a")
        self.assertEqual(s.formatted("CONVERTED", 0, s.buffer, ["TEST1", "TEST3"]), "TEST2: 3456\n")
        self.assertEqual(s.formatted("CONVERTED", 0, s.buffer, ["TEST1", "TEST2", "TEST3"]), "")


class TestStructureBufferRecalculateBitOffsets(unittest.TestCase):
    def test_recalculates_the_bit_offsets_for_0_size(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 80, "BLOCK")
        s.append_item("test2", 0, "BLOCK")
        s.define_item("test3", -16, 16, "UINT")
        s.buffer = (
            b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09" b"\x0a\x0b\x0c\x0d\x0e\x0f\x0f\x0e\x0d\x0c\x0b\x0a\xaa\x55"
        )
        self.assertEqual(s.read("test1"), b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09")
        self.assertEqual(s.read("test2"), b"\x0a\x0b\x0c\x0d\x0e\x0f\x0f\x0e\x0d\x0c\x0b\x0a\xaa\x55")
        self.assertEqual(s.read("test3"), 0xAA55)


class TestStructureShortBufferAllowed(unittest.TestCase):
    def test_returns_none_for_items_outside_buffer_bounds(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("item1", 16, "UINT")
        s.append_item("item2", 16, "UINT")
        s.append_item("item3", 16, "UINT")
        s.short_buffer_allowed = True
        # Set a short buffer that only contains data for item1
        s.buffer = b"\x00\x01"
        # item1 should read successfully
        self.assertEqual(s.read("item1"), 1)
        # item2 and item3 should return None since they're outside the buffer
        self.assertIsNone(s.read("item2"))
        self.assertIsNone(s.read("item3"))
        # Buffer should remain at its original size (not padded)
        self.assertEqual(len(s.buffer), 2)

    def test_raises_error_when_short_buffer_allowed_is_false(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("item1", 16, "UINT")
        s.append_item("item2", 16, "UINT")
        with self.assertRaisesRegex(ValueError, "Buffer length less than defined length"):
            s.buffer = b"\x00\x01"
