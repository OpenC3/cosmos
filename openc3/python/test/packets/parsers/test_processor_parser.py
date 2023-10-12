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
from openc3.packets.packet_config import PacketConfig
from openc3.config.config_parser import ConfigParser


class TestProcessorParser(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_a_current_packet_is_not_defined(self):
        # Check for missing TELEMETRY line
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("PROCESSOR")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "No current packet for PROCESSOR"
        ):
            self.pc.process_file(tf.name, "SYSTEM")
        tf.close()

    def test_complains_if_there_are_not_enough_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PROCESSOR\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for PROCESSOR"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_about_missing_processor_file(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt2 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PROCESSOR TEST test_only.py\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "No module named 'test_only",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_parses_the_processor(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt3 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM item1 0 16 UINT "Integer Item"\n')
        tf.write(
            "    READ_CONVERSION openc3/conversions/processor_conversion.py WATER HIGH_WATER\n"
        )
        tf.write("  PROCESSOR WATER openc3/processors/watermark_processor.py ITEM1\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT3"].buffer = b"\x00\x01"
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT3"].read("ITEM1"), 0)
        tf.close()

    def test_complains_if_applied_to_a_command_packet(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt4 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PROCESSOR WATER openc3/processors/watermark_processor.py ITEM\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "PROCESSOR only applies to telemetry packets"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()
