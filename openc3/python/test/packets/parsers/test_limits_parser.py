# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import tempfile
import unittest
from unittest.mock import *

from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_config import PacketConfig
from test.test_helper import *


class TestLimitsParser(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def test_complains_if_a_current_item_is_not_defined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  LIMITS mylimits 1 ENABLED 0 10 20 30 12 18\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "No current item for LIMITS"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_there_are_not_enough_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 0 10 20 30 12\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Must give both a green low and green high"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 0 10 20\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters for LIMITS"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_there_are_too_many_parameters(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM myitem 0 8 UINT "Test Item"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 0 10 20 30 12 18 20\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Too many parameters for LIMITS"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_applied_to_a_command_parameter(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_PARAMETER item1 16 UINT 0 0 0 "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "LIMITS only applies to telemetry items"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_a_default_limits_set_isnt_defined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS TVAC 3 ENABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "DEFAULT limits set must be defined"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_states_are_defined(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    STATE ONE 1\n")
        tf.write("    LIMITS TVAC 3 ENABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Items with STATE can't define LIMITS"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_sets_a_warning_if_a_new_limits_set_persistence_isnt_consistent_with_default(
        self,
    ):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ID_ITEM item1 16 UINT 1 "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 7 3 5\n")
        tf.write("    LIMITS TVAC 1 ENABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertIn("persistence setting conflict with DEFAULT", self.pc.warnings[-1])
        tf.close()

    def test_sets_a_warning_if_a_new_limits_set_enable_isnt_consistent_with_default(
        self,
    ):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ID_ITEM item1 16 UINT 1 "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 7 3 5\n")
        tf.write("    LIMITS TVAC 3 DISABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertIn("enable setting conflict with DEFAULT", self.pc.warnings[-1])
        tf.close()

    def test_records_2_warnings_if_a_new_limits_set_persistence_and_enable_isnt_consistent_with_default(
        self,
    ):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ID_ITEM item1 16 UINT 1 "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 7 3 5\n")
        tf.write("    LIMITS TVAC 1 DISABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(len(self.pc.warnings), 2)
        tf.close()

    def test_complains_if_the_second_parameter_isnt_a_number(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT TRUE ENABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Persistence must be an integer"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_the_third_parameter_isnt_enabled_or_disabled(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 TRUE 1 2 6 7 3 5\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Initial LIMITS state must be ENABLED or DISABLED"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_the_fourth_through_ninth_parameter_arent_numbers(self):
        msgs = [
            "",
            "",
            "",
            "",
            "red low",
            "yellow low",
            "yellow high",
            "red high",
            "green low",
            "green high",
        ]
        for index in range(4, 10):
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
            limits = ["LIMITS", "DEFAULT", "3", "ENABLED", "1", "2", "6", "7", "3", "5"]
            limits[index] = "X"
            tf.write(" ".join(limits))
            tf.seek(0)
            with self.assertRaisesRegex(ConfigParser.Error, f"Invalid {msgs[index]} limit value"):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

    def test_complains_if_the_4_limits_are_out_of_order(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 2 1 3 4\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure yellow limits are within red limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 5 3 7\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure yellow limits are within red limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 5 4\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure yellow limits are within red limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 3 0\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure yellow limits are within red limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_if_the_6_limits_are_out_of_order(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 7 0 5\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure green limits are within yellow limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 3 6 7 2 5\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure green limits are within yellow limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 8 3 7\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure green limits are within yellow limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 8 3 9\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure green limits are within yellow limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 3 ENABLED 1 2 6 8 4 3\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid limits specified. Ensure green limits are within yellow limits.",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_takes_4_limits_values(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 1 2 6 7\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        item = self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"]
        self.assertIsNotNone(item.limits.values["DEFAULT"])
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x04\x00"
        self.pc.telemetry["TGT1"]["PKT1"].enable_limits("ITEM1")
        self.pc.telemetry["TGT1"]["PKT1"].check_limits()
        self.assertEqual(item.limits.state, "GREEN")
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].limits_items, [item])
        tf.close()

    def test_takes_6_limits_values(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 1 2 6 7 3 5\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        item = self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"]
        self.assertIsNotNone(item.limits.values["DEFAULT"])
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x04\x00"
        self.pc.telemetry["TGT1"]["PKT1"].enable_limits("ITEM1")
        self.pc.telemetry["TGT1"]["PKT1"].check_limits()
        self.assertEqual(item.limits.state, "BLUE")
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].limits_items, [item])
        tf.close()

    def test_create_multiple_limits_sets(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 1 2 6 7\n")
        tf.write("    LIMITS TVAC 1 ENABLED 1 2 6 7\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        item = self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"]
        self.assertEqual(len(item.limits.values), 2)
        self.assertIsNotNone(item.limits.values.get("DEFAULT"))
        self.assertIsNotNone(item.limits.values.get("TVAC"))
        tf.close()


class TestLimitsParserChangeLimits(unittest.TestCase):
    def setUp(self):
        self.pc = PacketConfig()

    def parse_limits(self, item_def, *limits_lines):
        with tempfile.NamedTemporaryFile(mode="w") as tf:
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write(f"  {item_def}\n")
            for line in limits_lines:
                tf.write(f"    {line}\n")
            tf.seek(0)
            self.pc.process_file(tf.name, "TGT1")
        return self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"]

    def test_creates_sequence_change_and_static_limits(self):
        for change_type in ["SEQUENCE", "CHANGE", "STATIC"]:
            self.pc = PacketConfig()
            item = self.parse_limits(
                'APPEND_ITEM item1 16 UINT "Item"', f"LIMITS DEFAULT 2 DISABLED {change_type.lower()} yellow"
            )
            self.assertEqual(item.limits.change_type, change_type)
            self.assertEqual(item.limits.change_color, "YELLOW")
            self.assertIsNone(item.limits.values)
            self.assertFalse(item.limits.enabled)
            self.assertEqual(item.limits.persistence_setting, 2)
            self.assertIn(item, self.pc.telemetry["TGT1"]["PKT1"].limits_items)

    def test_keeps_persistence_above_1_without_warning(self):
        for change_type in ["SEQUENCE", "CHANGE", "STATIC"]:
            self.pc = PacketConfig()
            item = self.parse_limits('APPEND_ITEM item1 16 UINT "Item"', f"LIMITS DEFAULT 3 ENABLED {change_type} RED")
            self.assertEqual(item.limits.persistence_setting, 3)
            self.assertFalse(any("persistence" in warning for warning in self.pc.warnings))

    def test_allows_change_and_static_on_string_items(self):
        item = self.parse_limits('APPEND_ITEM item1 64 STRING "Item"', "LIMITS DEFAULT 1 ENABLED STATIC RED")
        self.assertEqual(item.limits.change_type, "STATIC")

    def test_complains_about_sequence_on_non_numeric_or_array_items(self):
        with self.assertRaisesRegex(
            ConfigParser.Error, "SEQUENCE limits can only be applied to INT, UINT, FLOAT, or DERIVED items"
        ):
            self.parse_limits('APPEND_ITEM item1 64 STRING "Item"', "LIMITS DEFAULT 1 ENABLED SEQUENCE RED")
        with self.assertRaisesRegex(ConfigParser.Error, "SEQUENCE limits can't be applied to array items"):
            self.parse_limits('APPEND_ARRAY_ITEM item1 8 UINT 64 "Item"', "LIMITS DEFAULT 1 ENABLED SEQUENCE RED")

    def test_complains_about_invalid_colors(self):
        with self.assertRaisesRegex(ConfigParser.Error, "SEQUENCE limits color must be RED or YELLOW"):
            self.parse_limits('APPEND_ITEM item1 16 UINT "Item"', "LIMITS DEFAULT 1 ENABLED SEQUENCE GREEN")

    def test_complains_about_the_wrong_number_of_parameters(self):
        with self.assertRaisesRegex(ConfigParser.Error, "Not enough parameters for LIMITS"):
            self.parse_limits('APPEND_ITEM item1 16 UINT "Item"', "LIMITS DEFAULT 1 ENABLED SEQUENCE")
        with self.assertRaisesRegex(ConfigParser.Error, "Too many parameters for LIMITS"):
            self.parse_limits('APPEND_ITEM item1 16 UINT "Item"', "LIMITS DEFAULT 1 ENABLED SEQUENCE RED 5")

    def test_complains_if_not_in_the_default_limits_set(self):
        with self.assertRaisesRegex(
            ConfigParser.Error, "SEQUENCE limits can only be defined in the DEFAULT limits set"
        ):
            self.parse_limits('APPEND_ITEM item1 16 UINT "Item"', "LIMITS TVAC 1 ENABLED SEQUENCE RED")

    def test_complains_if_combined_with_numeric_limits(self):
        with self.assertRaisesRegex(ConfigParser.Error, "already has LIMITS defined"):
            self.parse_limits(
                'APPEND_ITEM item1 16 UINT "Item"',
                "LIMITS DEFAULT 1 ENABLED 1 2 6 7",
                "LIMITS DEFAULT 1 ENABLED CHANGE RED",
            )
        self.pc = PacketConfig()
        with self.assertRaisesRegex(
            ConfigParser.Error, "already has CHANGE limits and can't also define numeric LIMITS"
        ):
            self.parse_limits(
                'APPEND_ITEM item1 16 UINT "Item"',
                "LIMITS DEFAULT 1 ENABLED CHANGE RED",
                "LIMITS TVAC 1 ENABLED 1 2 6 7",
            )

    def test_complains_if_combined_with_state(self):
        with self.assertRaisesRegex(ConfigParser.Error, "Items with LIMITS can't define STATE"):
            self.parse_limits('APPEND_ITEM item1 16 UINT "Item"', "LIMITS DEFAULT 1 ENABLED CHANGE RED", "STATE ON 1")

    def test_round_trips_through_to_config_and_as_json(self):
        item = self.parse_limits('APPEND_ITEM item1 16 UINT "Item"', "LIMITS DEFAULT 3 ENABLED CHANGE RED")
        self.assertIn("LIMITS DEFAULT 3 ENABLED CHANGE RED\n", item.to_config("TELEMETRY", "BIG_ENDIAN"))
        json = item.as_json()
        self.assertTrue(json["limits"]["enabled"])
        self.assertEqual(json["limits"]["persistence_setting"], 3)
        self.assertEqual(json["limits"]["DEFAULT"], {"change_type": "CHANGE", "change_color": "RED"})
