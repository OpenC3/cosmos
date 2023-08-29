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


class TestFormatStringParser(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_a_current_item_is_not_defined(self):
        # Check for missing ITEM definitions
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  FORMAT_STRING\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "No current item for FORMAT_STRING"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_there_are_not_enough_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("  FORMAT_STRING\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for FORMAT_STRING"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_there_are_too_many_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("FORMAT_STRING '0x%x' extra")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Too many parameters for FORMAT_STRING"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_about_invalid_format_strings(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 INT\n")
        tf.write('    FORMAT_STRING "%*s"\n')
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Invalid FORMAT_STRING specified for type INT: %\*s"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 STRING\n")
        tf.write('    FORMAT_STRING "%d"\n')
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Invalid FORMAT_STRING specified for type STRING: %d"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_formats_integers(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 INT\n")
        tf.write('    FORMAT_STRING "d%d"\n')
        tf.write("  ITEM item2 0 8 UINT\n")
        tf.write('    FORMAT_STRING "u%u"\n')
        tf.write("  ITEM item3 0 8 UINT\n")
        tf.write('    FORMAT_STRING "0x%x"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x0a\x0b\x0c"
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1", "FORMATTED"), "d10"
        )
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].read("ITEM2", "FORMATTED"), "u10"
        )
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].read("ITEM3", "FORMATTED"), "0xa"
        )
        tf.close()

    def test_formats_floats(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 32 FLOAT\n")
        tf.write('    FORMAT_STRING "%3.3f"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT1"].write("ITEM1", 12345.12345)
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1", "FORMATTED"), "12345.123"
        )
        tf.close()

    def test_formats_strings_and_blocks(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 32 STRING\n")
        tf.write('    FORMAT_STRING "String= %s"\n')
        tf.write("  ITEM item2 0 32 BLOCK\n")
        tf.write('    FORMAT_STRING "Block= %s"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT1"].write("ITEM1", "HI")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1", "FORMATTED"), "String= HI"
        )
        self.pc.telemetry["TGT1"]["PKT1"].write("ITEM2", b"\x00\x01\x02\x03")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].read("ITEM2", "FORMATTED"),
            "Block= bytearray(b'\\x00\\x01\\x02\\x03')",
        )
        tf.close()
