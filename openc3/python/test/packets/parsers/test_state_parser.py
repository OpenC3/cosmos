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
from openc3.packets.telemetry import Telemetry


class TestStateParser(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_a_current_item_is_not_defined(self):
        # Check for missing ITEM definitions
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("STATE\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "No current item for STATE"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_there_are_not_enough_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("STATE\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for STATE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_limits_defined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 7 3 5\n")
        tf.write("    STATE ONE 1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Items with LIMITS can't define STATE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_units_defined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("    UNITS Kelvin K\n")
        tf.write("    STATE ONE 1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Items with UNITS can't define STATE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_there_are_too_many_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("STATE mystate 0 RED extra\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Too many parameters for STATE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_supports_string_items(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  APPEND_ITEM item1 128 STRING "state item"\n')
        tf.write('    STATE FALSE "FALSE STRING"\n')
        tf.write('    STATE TRUE "TRUE STRING"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT1"].write("ITEM1", "TRUE STRING")
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1"), "TRUE")
        self.pc.telemetry["TGT1"]["PKT1"].write("ITEM1", "FALSE STRING")
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1"), "FALSE")
        tf.close()

    def test_warns_about_duplicate_states_and_replace_the_duplicate(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  APPEND_PARAMETER item1 8 UINT 0 2 0 "state item"\n')
        tf.write("    STATE FALSE 0\n")
        tf.write("    STATE TRUE 1\n")
        tf.write("    STATE FALSE 2\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertIn(
            "Duplicate state defined on line 5: STATE FALSE 2", self.pc.warnings
        )
        self.pc.commands["TGT1"]["PKT1"].buffer = b"\x00"
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), 0)
        self.pc.commands["TGT1"]["PKT1"].buffer = b"\x02"
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), "FALSE")
        tf.close()

    def test_defines_states_on_array_items(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  APPEND_ARRAY_ITEM item1 8 UINT 40 "state item"\n')
        tf.write("    STATE FALSE 0\n")
        tf.write("    STATE TRUE 1\n")
        tf.write("    STATE ERROR ANY\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tlm = Telemetry(self.pc, System)
        pkt = tlm.packet("TGT1", "PKT1")
        pkt.write("ITEM1", [0, 1, 2, 1, 0])
        self.assertEqual(pkt.read("ITEM1"), ["FALSE", "TRUE", "ERROR", "TRUE", "FALSE"])
        tf.close()

    def test_uses_state_or_format_string_if_no_state(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 8 UINT "Test Item"\n')
        tf.write('    FORMAT_STRING "0x%x"\n')
        tf.write("    STATE ONE 1\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tlm = Telemetry(self.pc, System)
        pkt = tlm.packet("TGT1", "PKT1")
        pkt.write("ITEM1", 1)
        self.assertEqual(pkt.read("ITEM1", "FORMATTED"), "ONE")
        pkt.write("ITEM1", 2)
        self.assertEqual(pkt.read("ITEM1", "FORMATTED"), "0x2")
        tf.close()

        # Ensure the order of STATE vs FORMAT_STRING doesn't matter
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 8 UINT "Test Item"\n')
        tf.write("    STATE ONE 1\n")
        tf.write('    FORMAT_STRING "0x%x"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tlm = Telemetry(self.pc, System)
        pkt = tlm.packet("TGT1", "PKT1")
        pkt.write("ITEM1", 1)
        self.assertEqual(pkt.read("ITEM1", "FORMATTED"), "ONE")
        pkt.write("ITEM1", 2)
        self.assertEqual(pkt.read("ITEM1", "FORMATTED"), "0x2")
        tf.close()

    def test_allows_an_any_state(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  APPEND_ITEM item1 8 UINT "state item"\n')
        tf.write("    STATE FALSE 0\n")
        tf.write("    STATE TRUE 1\n")
        tf.write("    STATE ERROR ANY\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        tlm = Telemetry(self.pc, System)
        pkt = tlm.packet("TGT1", "PKT1")
        pkt.write("ITEM1", 0)
        self.assertEqual(pkt.read("ITEM1"), "FALSE")
        pkt.write("ITEM1", 1)
        self.assertEqual(pkt.read("ITEM1"), "TRUE")
        pkt.write("ITEM1", 2)
        self.assertEqual(pkt.read("ITEM1"), "ERROR")
        tf.close()

    def test_only_allows_green_yellow_or_red(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  APPEND_ITEM item1 8 UINT "state item"\n')
        tf.write("    STATE WORST 1 ORANGE\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Invalid state color ORANGE"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_records_the_state_values_and_colors(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('  APPEND_ITEM item1 8 UINT "state item"\n')
        tf.write("    STATE STATE1 1 RED\n")
        tf.write("    STATE STATE2 2 YELLOW\n")
        tf.write("    STATE STATE3 3 GREEN\n")
        tf.write("    STATE STATE4 4\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        index = 1
        colors = ["RED", "YELLOW", "GREEN"]
        for name, val in (
            self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"].states.items()
        ):
            self.assertEqual(name, f"STATE{index}")
            self.assertEqual(val, index)
            if self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"].state_colors.get(name):
                self.assertEqual(
                    self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"].state_colors[name],
                    colors[index - 1],
                )
            index += 1
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].limits_items,
            [self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"]],
        )
        tf.close()

    def test_only_allows_hazardous_or_disable_messages_as_the_third_param(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  APPEND_PARAMETER item1 8 UINT 0 0 0\n")
        tf.write("    STATE WORST 0 RED\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "HAZARDOUS or DISABLE_MESSAGES expected as third parameter",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_allows_disable_messages_as_the_third_param(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  APPEND_PARAMETER item1 8 UINT 0 0 0\n")
        tf.write("    STATE GOOD 1\n")
        tf.write("    STATE BAD 0 DISABLE_MESSAGES\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertFalse(
            self.pc.commands["TGT1"]["PKT1"]
            .items["ITEM1"]
            .messages_disabled.get("GOOD")
        )
        self.assertTrue(
            self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].messages_disabled.get("BAD")
        )
        tf.close()

    def test_allows_hazardous_and_an_optional_description(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  APPEND_PARAMETER item1 8 UINT 1 3 1\n")
        tf.write("    STATE GOOD 1\n")
        tf.write("    STATE BAD 2 HAZARDOUS\n")
        tf.write('    STATE WORST 3 HAZARDOUS "Hazardous description"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.commands["TGT1"]["PKT1"].buffer = "\x01"
        self.pc.commands["TGT1"]["PKT1"].check_limits
        self.assertIsNone(
            self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].hazardous.get("GOOD")
        )
        self.assertIsNotNone(
            self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].hazardous.get("BAD")
        )
        self.assertIsNotNone(
            self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].hazardous.get("WORST")
        )
        self.assertEqual(
            self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].hazardous.get("WORST"),
            "Hazardous description",
        )
        self.assertEqual(len(self.pc.commands["TGT1"]["PKT1"].limits_items), 0)
        tf.close()
