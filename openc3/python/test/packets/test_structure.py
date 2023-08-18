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
            AttributeError,
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
        self.s = Structure()

    def test_adds_item_to_items_and_sorted_items(self):
        self.assertIsNone(self.s.items.get("test1"))
        self.assertEqual(len(self.s.sorted_items), 0)
        self.s.define_item("test1", 0, 8, "UINT")
        self.assertIsNotNone(self.s.items["TEST1"])
        self.assertIsNotNone(self.s.sorted_items[0])
        self.assertEqual(self.s.sorted_items[0].name, "TEST1")
        self.assertEqual(self.s.defined_length, 1)
        self.assertTrue(self.s.fixed_size)

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

    def test_adds_item_with_negative_offset(self):
        self.assertRaisesRegex(
            AttributeError,
            "TEST11: Can't define an item with array_size 128 greater than negative bit_offset -64",
            self.s.define_item,
            "test11",
            -64,
            8,
            "UINT",
            128,
        )
        self.assertRaisesRegex(
            AttributeError,
            "TEST10: Can't define an item with negative array_size -64 and negative bit_offset -64",
            self.s.define_item,
            "test10",
            -64,
            8,
            "UINT",
            -64,
        )
        self.assertRaisesRegex(
            AttributeError,
            "TEST9: Can't define an item with negative bit_size -64 and negative bit_offset -64",
            self.s.define_item,
            "test9",
            -64,
            -64,
            "BLOCK",
        )
        self.assertRaisesRegex(
            AttributeError,
            "TEST8: bit_size cannot be negative or zero for array items",
            self.s.define_item,
            "test8",
            0,
            -32,
            "BLOCK",
            64,
        )
        self.assertRaisesRegex(
            AttributeError,
            "TEST7: bit_size cannot be negative or zero for array items",
            self.s.define_item,
            "test7",
            0,
            0,
            "BLOCK",
            64,
        )
        self.assertRaisesRegex(
            AttributeError,
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

    def test_recalulates_sorted_items_when_adding_multiple_items(self):
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

    def test_complains_if_appending_after_a_variably_sized_item(self):
        self.s.define_item("test1", 0, 0, "BLOCK")
        self.assertRaisesRegex(
            AttributeError,
            "Can't append an item after a variably sized item",
            self.s.append_item,
            "test2",
            8,
            "UINT",
        )

    def test_complains_if_appending_after_a_variably_sized_array(self):
        self.s.define_item("test1", 0, 8, "UINT", -8)
        self.assertRaisesRegex(
            AttributeError,
            "Can't append an item after a variably sized item",
            self.s.append_item,
            "test2",
            8,
            "UINT",
        )


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

    def test_complains_if_appending_after_a_variably_sized_define_item(self):
        self.s.define_item("test1", 0, 0, "BLOCK")
        item = StructureItem("test2", 0, 16, "UINT", "BIG_ENDIAN")
        self.assertRaisesRegex(
            AttributeError,
            "Can't append an item after a variably sized item",
            self.s.append,
            item,
        )


class TestStructureGetItem(unittest.TestCase):
    def setUp(self):
        self.s = Structure()
        self.s.define_item("test1", 0, 8, "UINT")

    def test_returns_a_defined_item(self):
        self.assertIsNotNone(self.s.get_item("test1"))

    def test_complains_if_an_item_doesnt_exist(self):
        self.assertRaisesRegex(
            AttributeError, "Unknown item: test2", self.s.get_item, "test2"
        )


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
            AttributeError,
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
        self.assertRaisesRegex(
            AttributeError, "Unknown item: test1", self.s.get_item, "test1"
        )
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
        self.assertRaisesRegex(
            AttributeError, "Unknown item: BLAH", Structure().read, "BLAH"
        )

    def test_reads_data_from_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT")
        buffer = b"\x01"
        self.assertEqual(s.read("test1", "RAW", buffer), 1)

    def test_reads_until_null_byte_for_string_items(self):
        s = Structure()
        s.define_item("test1", 0, 80, "STRING")
        buffer = b"\x4E\x4F\x4F\x50\x00\x4E\x4F\x4F\x50\x0A"  # NOOP<NULL>NOOP\n
        self.assertEqual(s.read("test1", "CONVERTED", buffer), "NOOP")

    def test_reads_the_entire_buffer_for_block_items(self):
        s = Structure()
        s.define_item("test1", 0, 80, "BLOCK")
        buffer = b"\x4E\x4F\x4F\x50\x00\x4E\x4F\x4F\x50\x0A"  # NOOP<NULL>NOOP\n
        self.assertEqual(s.read("test1", "CONVERTED", buffer), b"NOOP\x00NOOP\n")

    def test_reads_array_data_from_the_buffer(self):
        s = Structure()
        s.define_item("test1", 0, 8, "UINT", 16)
        buffer = b"\x01\x02"
        self.assertEqual(s.read("test1", "RAW", buffer), [1, 2])


class TestStructureWrite(unittest.TestCase):
    def test_complains_if_item_doesnt_exist(self):
        with self.assertRaisesRegex(AttributeError, "Unknown item: BLAH"):
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
        s.write("test3", b"\x07\x08\x09\x0A")
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
#     expect(s.formatted('CONVERTED', 0, buffer)).to include("TEST2: #{0x0C0D}")
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
        with self.assertRaisesRegex(
            AttributeError, "Buffer length less than defined length"
        ):
            s.buffer = b"\x00"

    def test_complains_if_the_given_buffer_is_too_big(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 16, "UINT")
        with self.assertRaisesRegex(
            AttributeError, "Buffer length greater than defined length"
        ):
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

    def test_enables_reading_by_name(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        self.assertEqual(s.test1, [1, 2])

    def test_enables_writing_by_name(self):
        s = Structure("BIG_ENDIAN")
        s.append_item("test1", 8, "UINT", 16)
        s.write("test1", [1, 2])
        self.assertEqual(s.test1, [1, 2])
        s.test1 = [3, 4]
        self.assertEqual(s.test1, [3, 4])

    def test_works_if_there_is_no_buffer(self):
        s = Structure("BIG_ENDIAN", None)
        s.append_item("test1", 8, "UINT", 16)
        s.test1 = [5, 6]
        self.assertEqual(s.test1, [5, 6])

    def test_complains_if_it_cant_find_an_item(self):
        s = Structure("BIG_ENDIAN")
        with self.assertRaisesRegex(AttributeError, "Unknown item: test1"):
            s.test1
