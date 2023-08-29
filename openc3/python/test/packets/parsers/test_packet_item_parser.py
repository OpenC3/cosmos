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
import tempfile
from unittest.mock import *
from test.test_helper import *
from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_config import PacketConfig


class TestPacketItemParserTlm(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_only_allows_item_after_telemetry(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 8 0 DERIVED\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "ITEM types are only valid with TELEMETRY"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_given_an_incomplete_definition(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 8 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 8\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_given_a_bad_bit_offset(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 EIGHT 0 DERIVED\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "invalid literal for int()"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_given_a_bad_bit_size(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 8 ZERO DERIVED\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "invalid literal for int()"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_given_a_bad_array_size(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ARRAY_ITEM ITEM3 0 32 FLOAT EIGHT\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "invalid literal for int()"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_only_allows_derived_items_with_offset_0_and_size_0(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 8 0 DERIVED\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "DERIVED items must have bit_offset of zero"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 0 8 DERIVED\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "DERIVED items must have bit_size of zero"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ITEM ITEM1 0 0 DERIVED\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertIn("ITEM1", self.pc.telemetry["TGT1"]["PKT1"].items.keys())
        tf.close()

    def test_accepts_types_int_uint_float_string_block(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ID_ITEM ITEM1 0 32 INT 0\n")
        tf.write("  ITEM ITEM2 0 32 UINT\n")
        tf.write("  ARRAY_ITEM ITEM3 0 32 FLOAT 64\n")
        tf.write('  APPEND_ID_ITEM ITEM4 32 STRING "ABCD"\n')
        tf.write("  APPEND_ITEM ITEM5 32 BLOCK\n")
        tf.write("  APPEND_ARRAY_ITEM ITEM6 32 BLOCK 64\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertTrue(
            set(["ITEM1", "ITEM2", "ITEM3", "ITEM4", "ITEM5", "ITEM6"]).issubset(
                set(self.pc.telemetry["TGT1"]["PKT1"].items.keys())
            ),
        )
        id_items = []
        id_items.append(self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"])
        id_items.append(self.pc.telemetry["TGT1"]["PKT1"].items["ITEM4"])
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].id_items, id_items)
        tf.close()

    def test_supports_arbitrary_endianness_per_item(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  ID_ITEM ITEM1 0 32 UINT 0 "" LITTLE_ENDIAN\n')
        tf.write('  ITEM ITEM2 0 32 UINT "" LITTLE_ENDIAN\n')
        tf.write('  ARRAY_ITEM ITEM3 0 32 UINT 64 "" LITTLE_ENDIAN\n')
        tf.write('  APPEND_ID_ITEM ITEM4 32 UINT 1 "" LITTLE_ENDIAN\n')
        tf.write('  APPEND_ITEM ITEM5 32 UINT "" LITTLE_ENDIAN\n')
        tf.write('  APPEND_ARRAY_ITEM ITEM6 32 UINT 64 "" LITTLE_ENDIAN\n')
        tf.write('  ID_ITEM ITEM10 224 32 UINT 0 "" BIG_ENDIAN\n')
        tf.write('  ITEM ITEM20 256 32 UINT "" BIG_ENDIAN\n')
        tf.write('  ARRAY_ITEM ITEM30 0 32 UINT 64 "" BIG_ENDIAN\n')
        tf.write('  APPEND_ID_ITEM ITEM40 32 UINT 1 "" BIG_ENDIAN\n')
        tf.write('  APPEND_ITEM ITEM50 32 UINT "" BIG_ENDIAN\n')
        tf.write('  APPEND_ARRAY_ITEM ITEM60 32 UINT 64 "" BIG_ENDIAN\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        packet = self.pc.telemetry["TGT1"]["PKT1"]
        packet.buffer = bytearray(b"\x00\x00\x00\x01" * 16)
        self.assertEqual(packet.read("ITEM1"), 0x01000000)
        self.assertEqual(packet.read("ITEM2"), 0x01000000)
        self.assertEqual(packet.read("ITEM3"), [0x01000000, 0x01000000])
        self.assertEqual(packet.read("ITEM4"), 0x01000000)
        self.assertEqual(packet.read("ITEM5"), 0x01000000)
        self.assertEqual(packet.read("ITEM6"), [0x01000000, 0x01000000])
        self.assertEqual(packet.read("ITEM10"), 0x00000001)
        self.assertEqual(packet.read("ITEM20"), 0x00000001)
        self.assertEqual(packet.read("ITEM30"), [0x00000001, 0x00000001])
        self.assertEqual(packet.read("ITEM40"), 0x00000001)
        self.assertEqual(packet.read("ITEM50"), 0x00000001)
        self.assertEqual(packet.read("ITEM60"), [0x00000001, 0x00000001])
        tf.close()

    def test_complains_if_an_item_is_redefined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY TGT1 PKT1 BIG_ENDIAN "Description"\n')
        tf.write('  APPEND_ITEM ITEM1 16 UINT "Item 1"\n')
        tf.write('  APPEND_ITEM ITEM1 16 UINT "Another item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        packet = self.pc.telemetry["TGT1"]["PKT1"]
        packet.buffer = bytearray(b"\xDE\xAD\xBE\xEF")
        self.assertEqual(packet.read("ITEM1"), 0xBEEF)
        self.assertIn("TGT1 PKT1 ITEM1 redefined.", self.pc.warnings)
        tf.close()

    def test_only_allows_parameter_after_command(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER ITEM1 8 0 DERIVED 0 0 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "PARAMETER types are only valid with COMMAND"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()


class TestPacketItemParserCmd(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_given_an_incomplete_definition(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER ITEM1 8 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER ITEM1 8\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER ITEM1\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_only_allows_derived_items_with_offset_0_and_size_0(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER ITEM1 8 0 DERIVED 0 0 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "DERIVED items must have bit_offset of zero"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER ITEM1 0 8 DERIVED 0 0 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "DERIVED items must have bit_size of zero"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  PARAMETER ITEM1 0 0 DERIVED 0 0 0\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertIn("ITEM1", self.pc.commands["TGT1"]["PKT1"].items.keys())
        tf.close()

    def test_doesnt_allow_id_parameter_with_derived_type(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ID_PARAMETER ITEM1 0 0 DERIVED 0 0 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "DERIVED data type not allowed"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_doesnt_allow_append_id_parameter_with_derived_type(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  APPEND_ID_PARAMETER ITEM1 0 DERIVED 0 0 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "DERIVED data type not allowed"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_accepts_types_int_uint_float_string_block(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  ID_PARAMETER ITEM1 0 32 INT 0 0 0\n")
        tf.write('  ID_PARAMETER ITEM2 32 32 STRING "ABCD"\n')
        tf.write("  PARAMETER ITEM3 64 32 UINT 0 0 0\n")
        tf.write("  ARRAY_PARAMETER ITEM4 96 32 FLOAT 64\n")
        tf.write("  APPEND_ID_PARAMETER ITEM5 32 UINT 0 0 0\n")
        tf.write('  APPEND_ID_PARAMETER ITEM6 32 STRING "ABCD"\n')
        tf.write('  APPEND_PARAMETER ITEM7 32 BLOCK "1234"\n')
        tf.write("  APPEND_ARRAY_PARAMETER ITEM8 32 BLOCK 64\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertIn("ITEM1", self.pc.commands["TGT1"]["PKT1"].items.keys())
        tf.close()

    def test_supports_arbitrary_range_default_and_endianness_per_item(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  ID_PARAMETER ITEM1 0 32 UINT 1 2 3 "" LITTLE_ENDIAN\n')
        tf.write('  PARAMETER ITEM2 0 32 UINT 4 5 6 "" LITTLE_ENDIAN\n')
        tf.write('  ARRAY_PARAMETER ITEM3 0 32 UINT 64 "" LITTLE_ENDIAN\n')
        tf.write('  APPEND_ID_PARAMETER ITEM4 32 UINT 7 8 9 "" LITTLE_ENDIAN\n')
        tf.write('  APPEND_PARAMETER ITEM5 32 UINT 10 11 12 "" LITTLE_ENDIAN\n')
        tf.write('  APPEND_ARRAY_PARAMETER ITEM6 32 UINT 64 "" LITTLE_ENDIAN\n')
        tf.write('  ID_PARAMETER ITEM10 224 32 UINT 13 14 15 "" BIG_ENDIAN\n')
        tf.write('  PARAMETER ITEM20 256 32 UINT 16 17 18 "" BIG_ENDIAN\n')
        tf.write('  ARRAY_PARAMETER ITEM30 0 32 UINT 64 "" BIG_ENDIAN\n')
        tf.write('  APPEND_ID_PARAMETER ITEM40 32 UINT 19 20 21 "" BIG_ENDIAN\n')
        tf.write('  APPEND_PARAMETER ITEM50 32 UINT 22 23 24 "" BIG_ENDIAN\n')
        tf.write('  APPEND_ARRAY_PARAMETER ITEM60 32 UINT 64 "" BIG_ENDIAN\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        packet = self.pc.commands["TGT1"]["PKT1"]
        packet.buffer = b"\x00\x00\x00\x01" * 16
        self.assertEqual(packet.get_item("ITEM1").minimum, 1)
        self.assertEqual(packet.get_item("ITEM1").maximum, 2)
        self.assertEqual(packet.get_item("ITEM1").default, 3)
        self.assertEqual(packet.get_item("ITEM1").id_value, 3)
        self.assertEqual(packet.read("ITEM1"), 0x01000000)
        self.assertEqual(packet.get_item("ITEM2").minimum, 4)
        self.assertEqual(packet.get_item("ITEM2").maximum, 5)
        self.assertEqual(packet.get_item("ITEM2").default, 6)
        self.assertEqual(packet.get_item("ITEM2").id_value, None)
        self.assertEqual(packet.read("ITEM2"), 0x01000000)
        self.assertIsNone(packet.get_item("ITEM3").minimum)
        self.assertIsNone(packet.get_item("ITEM3").maximum)
        self.assertEqual(packet.get_item("ITEM3").default, [])
        self.assertEqual(packet.get_item("ITEM3").id_value, None)
        self.assertEqual(packet.read("ITEM3"), [0x01000000, 0x01000000])
        self.assertEqual(packet.get_item("ITEM4").minimum, 7)
        self.assertEqual(packet.get_item("ITEM4").maximum, 8)
        self.assertEqual(packet.get_item("ITEM4").default, 9)
        self.assertEqual(packet.get_item("ITEM4").id_value, 9)
        self.assertEqual(packet.read("ITEM4"), 0x01000000)
        self.assertEqual(packet.get_item("ITEM5").minimum, 10)
        self.assertEqual(packet.get_item("ITEM5").maximum, 11)
        self.assertEqual(packet.get_item("ITEM5").default, 12)
        self.assertEqual(packet.get_item("ITEM5").id_value, None)
        self.assertEqual(packet.read("ITEM5"), 0x01000000)
        self.assertIsNone(packet.get_item("ITEM3").minimum)
        self.assertIsNone(packet.get_item("ITEM3").maximum)
        self.assertEqual(packet.get_item("ITEM6").default, [])
        self.assertEqual(packet.get_item("ITEM6").id_value, None)
        self.assertEqual(packet.read("ITEM6"), [0x01000000, 0x01000000])
        self.assertEqual(packet.get_item("ITEM10").minimum, 13)
        self.assertEqual(packet.get_item("ITEM10").maximum, 14)
        self.assertEqual(packet.get_item("ITEM10").default, 15)
        self.assertEqual(packet.get_item("ITEM10").id_value, 15)
        self.assertEqual(packet.read("ITEM10"), 0x00000001)
        self.assertEqual(packet.get_item("ITEM20").minimum, 16)
        self.assertEqual(packet.get_item("ITEM20").maximum, 17)
        self.assertEqual(packet.get_item("ITEM20").default, 18)
        self.assertEqual(packet.get_item("ITEM20").id_value, None)
        self.assertEqual(packet.read("ITEM20"), 0x00000001)
        self.assertIsNone(packet.get_item("ITEM3").minimum)
        self.assertIsNone(packet.get_item("ITEM3").maximum)
        self.assertEqual(packet.get_item("ITEM30").default, [])
        self.assertEqual(packet.get_item("ITEM30").id_value, None)
        self.assertEqual(packet.read("ITEM30"), [0x00000001, 0x00000001])
        self.assertEqual(packet.get_item("ITEM40").minimum, 19)
        self.assertEqual(packet.get_item("ITEM40").maximum, 20)
        self.assertEqual(packet.get_item("ITEM40").default, 21)
        self.assertEqual(packet.get_item("ITEM40").id_value, 21)
        self.assertEqual(packet.read("ITEM40"), 0x00000001)
        self.assertEqual(packet.get_item("ITEM50").minimum, 22)
        self.assertEqual(packet.get_item("ITEM50").maximum, 23)
        self.assertEqual(packet.get_item("ITEM50").default, 24)
        self.assertEqual(packet.get_item("ITEM50").id_value, None)
        self.assertEqual(packet.read("ITEM50"), 0x00000001)
        self.assertIsNone(packet.get_item("ITEM3").minimum)
        self.assertIsNone(packet.get_item("ITEM3").maximum)
        self.assertEqual(packet.get_item("ITEM60").default, [])
        self.assertEqual(packet.get_item("ITEM60").id_value, None)
        self.assertEqual(packet.read("ITEM60"), [0x00000001, 0x00000001])
        tf.close()

    def test_only_supports_big_endian_and_little_endian(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  ID_PARAMETER ITEM1 0 32 UINT 0 0 0 "" MIDDLE_ENDIAN\n')
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Invalid endianness MIDDLE_ENDIAN"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    # def test_allows_for_different_default_type_than_the_data_type(self):
    #     tf = tempfile.NamedTemporaryFile(mode="w")
    #     tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
    #     tf.write('  PARAMETER ITEM1 0 32 UINT 4.5 5.5 6.5 "" LITTLE_ENDIAN\n')
    #     tf.write("    GENERIC_WRITE_CONVERSION_START\n")
    #     tf.write("      value / 2.0\n")
    #     tf.write("    GENERIC_WRITE_CONVERSION_END\n")
    #     tf.seek(0)
    #     self.pc.process_file(tf.name, "TGT1")
    #     tf.close()

    def test_requires_the_default_type_matches_the_data_type(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  PARAMETER ITEM1 0 32 UINT 4.5 5.5 6.5 "" LITTLE_ENDIAN\n')
        tf.seek(0)
        with self.assertRaisesRegex(
            AttributeError,
            "TGT1 PKT1 ITEM1: default must be a int but is a float",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_accepts_hex_values(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write(
            '  PARAMETER ITEM1 0 32 UINT 0x12345678 0xDEADFEEF 0xBA5EBA11 "" LITTLE_ENDIAN\n'
        )
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_a_parameter_is_redefined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND TGT1 PKT1 BIG_ENDIAN "Description"\n')
        tf.write('  APPEND_PARAMETER PARAM1 16 UINT MIN MAX 1 "Param 1"\n')
        tf.write('  APPEND_PARAMETER PARAM1 16 UINT MIN MAX 2 "Another param"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        packet = self.pc.commands["TGT1"]["PKT1"]
        packet.buffer = b"\xDE\xAD\xBE\xEF"
        self.assertEqual(packet.read("PARAM1"), 0xBEEF)
        self.assertIn("TGT1 PKT1 PARAM1 redefined.", self.pc.warnings)
        tf.close()
