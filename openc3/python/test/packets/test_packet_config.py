# Copyright 2024 OpenC3, Inc.
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

import tempfile
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_config import PacketConfig


class TestPacketConfig(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()
        self.pc = PacketConfig()

    def test_complains_about_unknown_keywords(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("BLAH")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "Unknown keyword 'BLAH'"):
            self.pc.process_file(tf.name, "SYSTEM")
        tf.close()

    def test_creates_unknown_cmd_tlm_packets(self):
        # Only one target called "UNKNOWN"
        self.assertEqual(list(self.pc.commands.keys()), ["UNKNOWN"])
        self.assertEqual(list(self.pc.telemetry.keys()), ["UNKNOWN"])
        # Only one cmd/tlm packet called "UNKNOWN"
        self.assertEqual(list(self.pc.commands["UNKNOWN"].keys()), ["UNKNOWN"])
        self.assertEqual(list(self.pc.telemetry["UNKNOWN"].keys()), ["UNKNOWN"])

    # def test_outputs_parsed_definitions_back_to_a_file(self):
    #     tf = tempfile.NamedTemporaryFile(mode="w")
    #     tlm = (
    #         'TELEMETRY TGT1 PKT1 LITTLE_ENDIAN "Telemetry"\n'
    #         '  ITEM BYTE 0 8 UINT "Item"\n'
    #     )
    #     tf.write(tlm)
    #     cmd = (
    #         'COMMAND TGT1 PKT1 LITTLE_ENDIAN "Command"\n'
    #         '  PARAMETER PARAM 0 16 UINT 0 0 0 "Param"\n'
    #     )
    #     tf.write(cmd)
    #     limits = "LIMITS_GROUP TVAC\n" "  LIMITS_GROUP_ITEM TGT1 PKT1 ITEM1\n"
    #     tf.write(limits)
    #     tf.seek(0)
    #     self.pc.process_file(tf.name, "TGT1")
    #     self.pc.to_config(TEST_DIR)
    #     data = ""
    #     with open(
    #         os.path.join(
    #             TEST_DIR,
    #             "TGT1",
    #             "cmd_tlm",
    #             "tg1_cmd.txt",
    #         ),
    #         "r",
    #     ) as f:
    #         data = f.read()
    #     self.assertEqual(cmd.strip(), data.strip())
    #     self.assertEqual(tlm.strip(),  File.read(File.join(OpenC3:'USERPATH', 'TGT1', 'cmd_tlm', 'tgt1_tlm.txt')).strip())
    #     self.assertEqual(limits.strip(),  File.read(File.join(OpenC3:'USERPATH', 'SYSTEM', 'cmd_tlm', 'limits_groups.txt')).strip())
    #     tf.close()
    #     shutil.rmtree(os.path.join(TEST_DIR, "TGT1"))

    # context "with all telemetry keywords" do
    #   before(:all) do
    # top level keywords
    top_keywords = [
        "SELECT_COMMAND",
        "SELECT_TELEMETRY",
        "LIMITS_GROUP",
        "LIMITS_GROUP_ITEM",
    ]
    # Keywords that require a current packet from TELEMETRY keyword
    tlm_keywords = [
        "SELECT_ITEM",
        "ITEM",
        "ID_ITEM",
        "ARRAY_ITEM",
        "APPEND_ITEM",
        "APPEND_ID_ITEM",
        "APPEND_ARRAY_ITEM",
        "PROCESSOR",
        "META",
    ]
    # Keywords that require both a current packet and current item
    item_keywords = [
        "STATE",
        "READ_CONVERSION",
        "WRITE_CONVERSION",
        "POLY_READ_CONVERSION",
        "POLY_WRITE_CONVERSION",
        "SEG_POLY_READ_CONVERSION",
        "SEG_POLY_WRITE_CONVERSION",
        "GENERIC_READ_CONVERSION_START",
        "GENERIC_WRITE_CONVERSION_START",
        "LIMITS",
        "LIMITS_RESPONSE",
        "UNITS",
        "FORMAT_STRING",
        "DESCRIPTION",
        "META",
    ]

    def test_complains_if_a_current_packet_is_not_defined(self):
        # Check for missing TELEMETRY line
        for keyword in TestPacketConfig.tlm_keywords:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(keyword)
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"No current packet for {keyword}"
            ):
                self.pc.process_file(tf.name, "SYSTEM")
            tf.close()

    def test_complains_if_a_current_item_is_not_defined(self):
        # Check for missing ITEM definitions
        for keyword in TestPacketConfig.item_keywords:
            if keyword == "META":
                continue

            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write(keyword)
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"No current item for {keyword}"
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

    def test_complains_if_there_are_not_enough_parameters(self):
        for keyword in TestPacketConfig.top_keywords:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(keyword)
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Not enough parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "SYSTEM")
            tf.close()

        for keyword in TestPacketConfig.tlm_keywords:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write(keyword)
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Not enough parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

        for keyword in TestPacketConfig.item_keywords:
            if (
                keyword == "GENERIC_READ_CONVERSION_START"
                or keyword == "GENERIC_WRITE_CONVERSION_START"
            ):
                continue

            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write('ITEM myitem 0 8 UINT "Test Item"\n')
            tf.write(keyword)
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Not enough parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

    def test_builds_the_id_value_hash(self):
        for keyword in TestPacketConfig.tlm_keywords:
            if keyword == "PROCESSOR" or keyword == "META":
                continue

            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('TELEMETRY tgt1 pkt1 BIG_ENDIAN "Packet"\n')
            tf.write('ID_ITEM myitem 0 8 UINT 13 "Test Item id=1"\n')
            tf.write('APPEND_ID_ITEM myitem 8 UINT 114 "Test Item id=1"\n')
            tf.write('COMMAND tgt1 pkt1 BIG_ENDIAN "Packet"\n')
            tf.write('ID_PARAMETER myitem 0 8 UINT 12 12 12 "Test Item id=1"\n')
            tf.write('APPEND_ID_PARAMETER myitem 8 UINT 115 115 115 "Test Item id=1"\n')
            tf.seek(0)
            self.pc.process_file(tf.name, "TGT1")
            expected_tlm_hash = {}
            expected_tlm_hash["TGT1"] = {}
            expected_tlm_hash["TGT1"]["[13, 114]"] = self.pc.telemetry["TGT1"]["PKT1"]
            expected_cmd_hash = {}
            expected_cmd_hash["TGT1"] = {}
            expected_cmd_hash["TGT1"]["[12, 115]"] = self.pc.commands["TGT1"]["PKT1"]
            self.assertEqual(self.pc.tlm_id_value_hash, expected_tlm_hash)
            self.assertEqual(self.pc.cmd_id_value_hash, expected_cmd_hash)
            tf.close()

    def test_complains_if_there_are_too_many_parameters(self):
        for keyword in TestPacketConfig.top_keywords:
            tf = tempfile.NamedTemporaryFile(mode="w")
            match keyword:
                case "SELECT_COMMAND":
                    tf.write("SELECT_COMMAND tgt1 pkt1 extra\n")
                case "SELECT_TELEMETRY":
                    tf.write("SELECT_TELEMETRY tgt1 pkt1 extra\n")
                case "LIMITS_GROUP":
                    tf.write("LIMITS_GROUP name extra")
                case "LIMITS_GROUP_ITEM":
                    tf.write("LIMITS_GROUP_ITEM target packet item extra")
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Too many parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

        for keyword in TestPacketConfig.tlm_keywords:
            if keyword == "PROCESSOR" or keyword == "META":
                continue

            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            match keyword:
                case "ITEM":
                    tf.write('ITEM myitem 0 8 UINT "Test Item" BIG_ENDIAN extra\n')
                case "APPEND_ITEM":
                    tf.write('APPEND_ITEM myitem 8 UINT "Test Item" BIG_ENDIAN extra\n')
                case "ID_ITEM":
                    tf.write(
                        'ID_ITEM myitem 0 8 UINT 1 "Test Item id=1" LITTLE_ENDIAN extra\n'
                    )
                case "APPEND_ID_ITEM":
                    tf.write(
                        'APPEND_ID_ITEM myitem 8 UINT 1 "Test Item id=1" BIG_ENDIAN extra\n'
                    )
                case "ARRAY_ITEM":
                    tf.write(
                        'ARRAY_ITEM myitem 0 8 UINT 24 "Test Item array" LITTLE_ENDIAN extra\n'
                    )
                case "APPEND_ARRAY_ITEM":
                    tf.write(
                        'APPEND_ARRAY_ITEM myitem 0 8 UINT 24 "Test Item array" BIG_ENDIAN extra\n'
                    )
                case "SELECT_ITEM":
                    tf.write("ITEM myitem 0 8 UINT\n")
                    tf.write("SELECT_ITEM myitem extra\n")
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Too many parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

        for keyword in TestPacketConfig.item_keywords:
            # The following can have an "unlimited" number of arguments
            if keyword in [
                "POLY_READ_CONVERSION",
                "POLY_WRITE_CONVERSION",
                "READ_CONVERSION",
                "WRITE_CONVERSION",
                "SEG_POLY_READ_CONVERSION",
                "SEG_POLY_WRITE_CONVERSION",
                "LIMITS_RESPONSE",
                "META",
            ]:
                continue

            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write('ITEM myitem 0 8 UINT "Test Item"\n')
            match keyword:
                case "STATE":
                    tf.write("STATE mystate 0 RED extra\n")
                case "GENERIC_READ_CONVERSION_START" | "GENERIC_WRITE_CONVERSION_START":
                    tf.write(f"{keyword} FLOAT 64 extra")
                case "LIMITS":
                    tf.write("LIMITS mylimits 1 ENABLED 0 10 20 30 12 18 20\n")
                case "UNITS":
                    tf.write("UNITS degrees deg extra\n")
                case "FORMAT_STRING" | "DESCRIPTION":
                    tf.write(f"{keyword} 'string' extra")
            tf.seek(0)
            with self.assertRaisesRegex(
                ConfigParser.Error, f"Too many parameters for {keyword}"
            ):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

    def test_select_complains_if_the_packet_is_not_found(self):
        for keyword in ["SELECT_COMMAND", "SELECT_TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(keyword + " tgt1 pkt1\n")
            tf.write("SELECT_ITEM ITEM1\n")
            tf.write('  DESCRIPTION "New description"\n')
            tf.seek(0)
            with self.assertRaisesRegex(ConfigParser.Error, "Packet not found"):
                self.pc.process_file(tf.name, "TGT1")
            tf.close()

    def test_selects_a_packet_for_modification(self):
        for keyword in ["SELECT_COMMAND", "SELECT_TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write('  APPEND_PARAMETER item1 16 UINT 0 0 0 "Item"\n')
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
            tf.seek(0)
            self.pc.process_file(tf.name, "TGT1")
            if keyword == "SELECT_COMMAND":
                pkt = self.pc.commands["TGT1"]["PKT1"]
            if keyword == "SELECT_TELEMETRY":
                pkt = self.pc.telemetry["TGT1"]["PKT1"]
            self.assertEqual(pkt.get_item("ITEM1").description, "Item")
            tf.close()

            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(keyword + " tgt1 pkt1\n")
            if keyword == "SELECT_COMMAND":
                tf.write("SELECT_PARAMETER ITEM1\n")
            if keyword == "SELECT_TELEMETRY":
                tf.write("SELECT_ITEM ITEM1\n")
            tf.write('  DESCRIPTION "New description"\n')
            tf.seek(0)
            self.pc.process_file(tf.name, "TGT1")
            if keyword == "SELECT_COMMAND":
                pkt = self.pc.commands["TGT1"]["PKT1"]
            if keyword == "SELECT_TELEMETRY":
                pkt = self.pc.telemetry["TGT1"]["PKT1"]
            self.assertEqual(pkt.get_item("ITEM1").description, "New description")
            tf.close()

    def test_substitutes_the_target_name(self):
        for keyword in ["SELECT_COMMAND", "SELECT_TELEMETRY"]:
            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write('  APPEND_PARAMETER item1 16 UINT 0 0 0 "Item"\n')
            tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
            tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
            tf.seek(0)
            self.pc.process_file(tf.name, "NEW")
            if keyword == "SELECT_COMMAND":
                pkt = self.pc.commands["NEW"]["PKT1"]
            if keyword == "SELECT_TELEMETRY":
                pkt = self.pc.telemetry["NEW"]["PKT1"]
            self.assertEqual(pkt.get_item("ITEM1").description, "Item")
            tf.close()

            tf = tempfile.NamedTemporaryFile(mode="w")
            tf.write(keyword + " tgt1 pkt1\n")
            if keyword == "SELECT_COMMAND":
                tf.write("SELECT_PARAMETER ITEM1\n")
            if keyword == "SELECT_TELEMETRY":
                tf.write("SELECT_ITEM ITEM1\n")
            tf.write('  DESCRIPTION "New description"\n')
            tf.seek(0)
            self.pc.process_file(tf.name, "NEW")
            if keyword == "SELECT_COMMAND":
                pkt = self.pc.commands["NEW"]["PKT1"]
            if keyword == "SELECT_TELEMETRY":
                pkt = self.pc.telemetry["NEW"]["PKT1"]
            self.assertEqual(pkt.get_item("ITEM1").description, "New description")
            tf.close()

    def test_complains_if_used_with_select_telemetry(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY TGT PKT LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM ITEM 16 UINT "Item"\n')
        tf.write("SELECT_TELEMETRY TGT PKT\n")
        tf.write("  SELECT_PARAMETER ITEM\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "SELECT_PARAMETER only applies to command packets"
        ):
            self.pc.process_file(tf.name, "TGT")

    def test_complains_if_the_parameter_is_not_found(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND TGT PKT LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_PARAMETER PARAM 16 UINT 0 0 0 "Param"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT")
        pkt = self.pc.commands["TGT"]["PKT"]
        self.assertEqual(pkt.get_item("PARAM").description, "Param")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("SELECT_COMMAND TGT PKT\n")
        tf.write("  SELECT_PARAMETER PARAMX\n")
        tf.write('    DESCRIPTION "New description"\n')
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "PARAMX not found in command packet TGT PKT"
        ):
            self.pc.process_file(tf.name, "TGT")

    def test_select_item_complains_if_used_with_select_command(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND TGT PKT LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_PARAMETER PARAM 16 UINT 0 0 0 "Param"\n')
        tf.write("SELECT_COMMAND TGT PKT\n")
        tf.write("  SELECT_ITEM PARAM\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "SELECT_ITEM only applies to telemetry packets"
        ):
            self.pc.process_file(tf.name, "TGT")

    def test_select_item_complains_if_the_item_is_not_found(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY TGT PKT LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM ITEM 16 UINT "Item"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT")
        pkt = self.pc.telemetry["TGT"]["PKT"]
        self.assertEqual(pkt.get_item("ITEM").description, "Item")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("SELECT_TELEMETRY TGT PKT\n")
        tf.write("  SELECT_ITEM ITEMX\n")
        tf.write('    DESCRIPTION "New description"\n')
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "ITEMX not found in telemetry packet TGT PKT"
        ):
            self.pc.process_file(tf.name, "TGT")

    def test_delete_item_removes_an_item(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY TGT PKT LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM ITEM1 16 UINT "Item"\n')
        tf.write('  APPEND_ITEM ITEM2 16 UINT "Item"\n')
        tf.write(" DELETE_ITEM ITEM1\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT")
        items = self.pc.telemetry["TGT"]["PKT"].items.keys()
        self.assertNotIn("ITEM1", items)
        self.assertIn("ITEM2", items)

    def test_creates_a_new_limits_group(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("LIMITS_GROUP TVAC\n")
        tf.write("LIMITS_GROUP VIBE\n")
        tf.seek(0)
        self.assertEqual(len(self.pc.limits_groups), 0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(["TVAC", "VIBE"], list(self.pc.limits_groups.keys()))
        tf.close()

    def test_adds_a_new_limits_item_to_the_group(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("LIMITS_GROUP TVAC\n")
        tf.write("LIMITS_GROUP_ITEM TGT1 PKT1 ITEM1\n")
        tf.seek(0)
        self.assertEqual(len(self.pc.limits_groups), 0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(self.pc.limits_groups["TVAC"], [["TGT1", "PKT1", "ITEM1"]])
        tf.close()

        # Show we can 're-open' the group and add items
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("LIMITS_GROUP TVAC\n")
        tf.write("LIMITS_GROUP_ITEM TGT1 PKT1 ITEM2\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            self.pc.limits_groups["TVAC"],
            [["TGT1", "PKT1", "ITEM1"], ["TGT1", "PKT1", "ITEM2"]],
        )
        tf.close()

    def test_marks_the_packet_as_allowing_short_buffers(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("ALLOW_SHORT\n")
        tf.write('TELEMETRY tgt1 pkt2 LITTLE_ENDIAN "Description"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertTrue(self.pc.telemetry["TGT1"]["PKT1"].short_buffer_allowed)
        self.assertFalse(self.pc.telemetry["TGT1"]["PKT2"].short_buffer_allowed)
        tf.close()

    def test_saves_metadata(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('META TYPE "struct packet"\n')
        tf.write('TELEMETRY tgt1 pkt2 LITTLE_ENDIAN "Description"\n')
        tf.write('META TYPE "struct packet2"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].meta["TYPE"], ["struct packet"]
        )
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT2"].meta["TYPE"], ["struct packet2"]
        )
        tf.close()

    def test_marks_the_packet_as_messages_disabled(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("DISABLE_MESSAGES\n")
        tf.write('COMMAND tgt1 pkt2 LITTLE_ENDIAN "Description"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertTrue(self.pc.commands["TGT1"]["PKT1"].messages_disabled)
        self.assertFalse(self.pc.commands["TGT1"]["PKT2"].messages_disabled)
        tf.close()

    def test_marks_the_packet_as_hidden(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("HIDDEN\n")
        tf.write('COMMAND tgt1 pkt2 LITTLE_ENDIAN "Description"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertTrue(self.pc.commands["TGT1"]["PKT1"].hidden)
        self.assertFalse(self.pc.commands["TGT1"]["PKT1"].disabled)
        self.assertFalse(self.pc.commands["TGT1"]["PKT2"].hidden)
        self.assertFalse(self.pc.commands["TGT1"]["PKT2"].disabled)
        tf.close()

    def test_marks_the_packet_as_disabled(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("DISABLED\n")
        tf.write('COMMAND tgt1 pkt2 LITTLE_ENDIAN "Description"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertTrue(self.pc.commands["TGT1"]["PKT1"].hidden)
        self.assertTrue(self.pc.commands["TGT1"]["PKT1"].disabled)
        self.assertFalse(self.pc.commands["TGT1"]["PKT2"].hidden)
        self.assertFalse(self.pc.commands["TGT1"]["PKT2"].disabled)
        tf.close()

    def test_sets_the_accessor_for_the_packet(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("ACCESSOR XmlAccessor\n")
        tf.write('COMMAND tgt2 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("ACCESSOR CborAccessor\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "SYSTEM")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].accessor.__class__.__name__, "XmlAccessor"
        )
        self.assertEqual(
            self.pc.commands["TGT2"]["PKT1"].accessor.__class__.__name__, "CborAccessor"
        )
        tf.close()

    def test_handles_bad_accessors(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("ACCESSOR NopeAccessor\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "No module named 'openc3.accessors.nope_accessor"
        ):
            self.pc.process_file(tf.name, "SYSTEM")
        tf.close()

    def test_response_only_applies_to_commands(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  RESPONSE TGT1 PKT1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "RESPONSE only applies to command packets"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_response_requires_two_params(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  RESPONSE TGT1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for RESPONSE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  RESPONSE TGT1 PKT1 ITEM1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Too many parameters for RESPONSE"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_response_sets_the_packet_response(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("RESPONSE TGT2 PKT2\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "SYSTEM")
        self.assertEqual(["TGT2", "PKT2"], self.pc.commands["TGT1"]["PKT1"].response)
        self.assertIsNone(self.pc.commands["TGT1"]["PKT1"].error_response)
        tf.close()

    def test_error_response_only_applies_to_commands(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  ERROR_RESPONSE TGT1 PKT1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "ERROR_RESPONSE only applies to command packets"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_error_response_sets_the_packet_error_response(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("ERROR_RESPONSE TGT2 PKT2\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            ["TGT2", "PKT2"], self.pc.commands["TGT1"]["PKT1"].error_response
        )
        self.assertIsNone(self.pc.commands["TGT1"]["PKT1"].response)
        tf.close()

    def test_screen_only_applies_to_commands(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  SCREEN TGT1 screen\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "SCREEN only applies to command packets"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_screen_requires_two_params(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  SCREEN TGT1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for SCREEN"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  SCREEN TGT1 SCREEN ANOTHER\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Too many parameters for SCREEN"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_screen_sets_the_command_screen(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("SCREEN TGT2 SCREEN\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(["TGT2", "SCREEN"], self.pc.commands["TGT1"]["PKT1"].screen)
        tf.close()

    def test_related_item_only_applies_to_commands(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  RELATED_ITEM TGT1 PKT1 ITEM1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "RELATED_ITEM only applies to command packets"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_related_item_requires_three_params(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  RELATED_ITEM TGT1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for RELATED_ITEM"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  RELATED_ITEM TGT1 PKT1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Not enough parameters for RELATED_ITEM"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  RELATED_ITEM TGT1 PKT1 ITEM1 RAW\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "Too many parameters for RELATED_ITEM"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_related_item_sets_the_command_related_item(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("  RELATED_ITEM TGT1 PKT1 ITEM1\n")
        tf.write("  RELATED_ITEM TGT1 PKT1 ITEM2\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            [["TGT1", "PKT1", "ITEM1"], ["TGT1", "PKT1", "ITEM2"]],
            self.pc.commands["TGT1"]["PKT1"].related_items,
        )
        tf.close()

    # def test_sets_the_template(self):
    #     tf = tempfile.NamedTemporaryFile(mode="w")
    #     tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
    #     tf.write('TEMPLATE "This is a template"\n')
    #     tf.write('COMMAND tgt2 pkt1 LITTLE_ENDIAN "Description"\n')
    #     tf.write('TEMPLATE "Another Template"\n')
    #     tf.seek(0)
    #     self.pc.process_file(tf.name, "SYSTEM")
    #     self.assertEqual(
    #         self.pc.telemetry["TGT1"]["PKT1"].template, "This is a template"
    #     )
    #     self.assertEqual(self.pc.commands["TGT2"]["PKT1"].template, "Another Template")
    #     tf.close()

    # def test_sets_the_template_via_file(self):
    #       data_file = Tempfile('unittest')
    #       data_file.write("File data")
    #       data_file.close
    #       tf = tempfile.NamedTemporaryFile(mode="w")
    #       filename = "datafile2.txt"
    #       File.open(File.dirname(tf.name) + '/' + filename, 'wb') do |file|
    #         file.write("relative file")
    #       tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
    #       tf.write "TEMPLATE_FILE {data_file.path}"
    #       tf.write('COMMAND tgt2 pkt1 LITTLE_ENDIAN "Description"\n')
    #       tf.write "TEMPLATE_FILE {filename}"
    #       tf.seek(0)
    #       self.pc.process_file(tf.name, "SYSTEM")
    #       self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].template,  "File data")
    #       self.assertEqual(self.pc.commands["TGT2"]["PKT1"].template,  "relative file")
    #       File.delete(File.dirname(tf.name) + '/' + filename)
    #       data_file.unlink
    #       tf.close()

    def test_marks_the_packet_as_hazardous(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("HAZARDOUS\n")
        tf.write('TELEMETRY tgt1 pkt2 LITTLE_ENDIAN "Description"\n')
        tf.write('COMMAND tgt2 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write("HAZARDOUS\n")
        tf.write('COMMAND tgt2 pkt2 LITTLE_ENDIAN "Description"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "SYSTEM")
        self.assertTrue(self.pc.telemetry["TGT1"]["PKT1"].hazardous)
        self.assertFalse(self.pc.telemetry["TGT1"]["PKT2"].hazardous)
        self.assertTrue(self.pc.commands["TGT2"]["PKT1"].hazardous)
        self.assertFalse(self.pc.commands["TGT2"]["PKT2"].hazardous)
        tf.close()

    def test_hazardous_takes_a_description(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Description"\n')
        tf.write('HAZARDOUS "Hazardous description"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertTrue(self.pc.commands["TGT1"]["PKT1"].hazardous)
        self.assertEqual(
            self.pc.commands["TGT1"]["PKT1"].hazardous_description,
            "Hazardous description",
        )
        tf.close()

    def test_complains_about_missing_conversion_file(self):
        self.pc = PacketConfig()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
        tf.write("  READ_CONVERSION openc3/missing.py\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "No module named 'openc3.missing'",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PARAMETER item1 0 16 INT 0 0 0\n")
        tf.write("  WRITE_CONVERSION openc3/missing.rb\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "No module named 'openc3.missing'",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_complains_about_a_non_openc3_conversion_class(self):
        filename = os.path.join(
            os.path.dirname(__file__), "../../openc3/test_convert.py"
        )
        if os.path.isfile(filename):
            os.remove(filename)
        with open(filename, "a") as file:
            file.write("class TestConvert:\n  pass")

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
        tf.write("  READ_CONVERSION openc3/test_convert.py\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "read_conversion must be a Conversion but is a TestConvert",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PARAMETER item1 0 16 INT 0 0 0\n")
        tf.write("  WRITE_CONVERSION openc3/test_convert.py\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "write_conversion must be a Conversion but is a TestConvert",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()
        os.remove(filename)

    def test_parses_the_conversion(self):
        filename = os.path.join(
            os.path.dirname(__file__), "../../openc3/test_real_conversion.py"
        )
        if os.path.isfile(filename):
            os.remove(filename)
        with open(filename, "a") as file:
            file.write("from openc3.conversions.conversion import Conversion\n")
            file.write("class TestRealConversion(Conversion):\n")
            file.write("  def call(self, value, packet, buffer):\n")
            file.write("    return value * 2\n")

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
        tf.write("  READ_CONVERSION openc3/test_real_conversion.py\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x01"
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1"), 2)
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PARAMETER item1 0 16 INT 0 0 0\n")
        tf.write("  WRITE_CONVERSION openc3/test_real_conversion.py\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.commands["TGT1"]["PKT1"].write("ITEM1", 3)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), 6)
        tf.close()
        os.remove(filename)

    def test_performs_a_polynomial_conversion(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
        tf.write("  POLY_READ_CONVERSION 5 2\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x01"
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1"), 7.0)
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PARAMETER item1 0 16 INT 0 0 0\n")
        tf.write("  POLY_WRITE_CONVERSION 5 2\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.commands["TGT1"]["PKT1"].write("ITEM1", 3)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), 11)
        tf.close()

    def test_performs_a_segmented_polynomial_conversion(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  ITEM item1 0 16 INT "Integer Item"\n')
        tf.write("  SEG_POLY_READ_CONVERSION 0 1 2\n")
        tf.write("  SEG_POLY_READ_CONVERSION 5 2 3\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x01"
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1"), 3.0)
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x05"
        self.assertEqual(self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1"), 17.0)
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PARAMETER item1 0 16 INT 0 0 0\n")
        tf.write("  SEG_POLY_WRITE_CONVERSION 0 1 2\n")
        tf.write("  SEG_POLY_WRITE_CONVERSION 5 2 3\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.commands["TGT1"]["PKT1"].write("ITEM1", 1)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), 3)
        self.pc.commands["TGT1"]["PKT1"].write("ITEM1", 5)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), 17)
        tf.close()

    def test_processes_a_generic_conversion(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    GENERIC_WRITE_CONVERSION_START\n")
        tf.write("      2.0 * value\n")
        tf.write("    GENERIC_WRITE_CONVERSION_END\n")
        tf.write('  APPEND_ITEM item2 8 UINT "Item"\n')
        tf.write("    GENERIC_READ_CONVERSION_START\n")
        tf.write('      f"Number {value}"\n')
        tf.write("    GENERIC_READ_CONVERSION_END\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        pkt = self.pc.telemetry["TGT1"]["PKT1"]
        pkt.write("item1", 2)
        self.assertEqual(pkt.read("item1"), 4)
        self.assertEqual(pkt.read("item2"), "Number 0")
        tf.close()

    def test_processes_a_generic_conversion_with_a_defined_type(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    GENERIC_WRITE_CONVERSION_START UINT 8\n")
        tf.write("      2.0 * value\n")
        tf.write("    GENERIC_WRITE_CONVERSION_END\n")
        tf.write('  APPEND_ITEM item2 64 FLOAT "Item"\n')
        tf.write("    GENERIC_READ_CONVERSION_START FLOAT 32\n")
        tf.write("      2.0 * value\n")
        tf.write("    GENERIC_READ_CONVERSION_END\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        pkt = self.pc.telemetry["TGT1"]["PKT1"]
        pkt.write("item1", 400)
        self.assertEqual(pkt.read("item1"), 800)
        pkt.write("item2", 400)
        self.assertEqual(pkt.read("item2"), 800.0)
        tf.close()

    def test_processes_a_generic_conversion_with_bad_type(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    GENERIC_WRITE_CONVERSION_START RAW 8\n")
        tf.write("      2.0 * value\n")
        tf.write("    GENERIC_WRITE_CONVERSION_END\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error,
            "Invalid converted_type: RAW",
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()
        tf.close()

    def test_ensures_limits_sets_have_unique_names(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write('  APPEND_ITEM item1 16 UINT "Item"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 1 2 6 7\n")
        tf.write("    LIMITS TVAC 1 ENABLED 1 2 6 7\n")
        tf.write("    LIMITS DEFAULT 1 ENABLED 8 9 12 13\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        item = self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"]
        self.assertEqual(len(item.limits.values), 2)
        # Verify the last defined DEFAULT limits wins
        self.pc.telemetry["TGT1"]["PKT1"].buffer = b"\x04"
        self.pc.telemetry["TGT1"]["PKT1"].enable_limits("ITEM1")
        self.pc.telemetry["TGT1"]["PKT1"].check_limits()
        self.assertEqual(item.limits.state, "RED_LOW")
        tf.close()

    def test_apply_units_when_read_with_units(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("    UNITS Volts V\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].read("ITEM1", "WITH_UNITS"), "0 V"
        )
        tf.close()

    def test_saves_key(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("    KEY mykey\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].get_item("ITEM1").key, "mykey"
        )
        tf.close()

    def test_saves_metadata_for_items(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write('    META TYPE "unsigned int"\n')
        tf.write("    META OTHER\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].get_item("item1").meta["TYPE"],
            ["unsigned int"],
        )
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].get_item("item1").meta["OTHER"], []
        )
        tf.close()

    def test_sets_the_overflow_type_for_items(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("    OVERFLOW TRUNCATE\n")
        tf.write("  ITEM item2 8 8 UINT\n")
        tf.write("    OVERFLOW SATURATE\n")
        tf.write("  ITEM item3 16 8 UINT\n")
        tf.write("    OVERFLOW ERROR\n")
        tf.write("  ITEM item4 24 8 INT\n")
        tf.write("    OVERFLOW ERROR_ALLOW_HEX\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].get_item("item1").overflow, "TRUNCATE"
        )
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].get_item("item2").overflow, "SATURATE"
        )
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].get_item("item3").overflow, "ERROR"
        )
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].get_item("item4").overflow,
            "ERROR_ALLOW_HEX",
        )
        tf.close()

    def test_allows_item_overlap(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt2 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("    OVERLAP\n")
        tf.write("  ITEM item2 0 2 UINT\n")
        tf.write("    OVERLAP\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(0, len(self.pc.warnings))
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  ITEM item2 0 2 UINT\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            "Bit definition overlap at bit offset 0 for packet TGT1 PKT1 items ITEM1 and ITEM2",
            self.pc.warnings[0],
        )
        tf.close()

    def test_required_only_applies_to_a_command_parameter(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("    REQUIRED\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "REQUIRED only applies to command parameters"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  REQUIRED\n")
        tf.seek(0)
        with self.assertRaisesRegex(ConfigParser.Error, "No current item for REQUIRED"):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_marks_a_command_parameter_as_required(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  PARAMETER item1 0 8 UINT 0 1 1\n")
        tf.write("    REQUIRED\n")
        tf.write("  PARAMETER item2 0 8 UINT 0 1 1\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertTrue(self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].required)
        self.assertFalse(self.pc.commands["TGT1"]["PKT1"].items["ITEM2"].required)
        tf.close()

    def test_min_max_defaul_complains_if_used_on_telemetry_items(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  APPEND_ITEM item1 16 UINT\n")
        tf.write("    MINIMUM_VALUE 1\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "MINIMUM_VALUE only applies to command parameters"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  APPEND_ITEM item1 16 UINT\n")
        tf.write("    MAXIMUM_VALUE 3\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "MAXIMUM_VALUE only applies to command parameters"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  APPEND_ITEM item1 16 UINT\n")
        tf.write("    DEFAULT_VALUE 2\n")
        tf.seek(0)
        with self.assertRaisesRegex(
            ConfigParser.Error, "DEFAULT_VALUE only applies to command parameters"
        ):
            self.pc.process_file(tf.name, "TGT1")
        tf.close()

    def test_allows_overriding_the_defined_value(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  APPEND_PARAMETER item1 16 UINT 0 1 1\n")
        tf.write('  APPEND_PARAMETER item2 16 STRING "HI"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.commands["TGT1"]["PKT1"].restore_defaults()
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), 1)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].minimum, 0)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].maximum, 1)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM2"), "HI")
        tf.close()

        # Now override the values from above
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("SELECT_COMMAND tgt1 pkt1\n")
        tf.write("SELECT_PARAMETER item1\n")
        tf.write("  MINIMUM_VALUE 1\n")
        tf.write("  MAXIMUM_VALUE 3\n")
        tf.write("  DEFAULT_VALUE 2\n")
        tf.write("SELECT_PARAMETER item2\n")
        tf.write('  DEFAULT_VALUE "NO"\n')
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.pc.commands["TGT1"]["PKT1"].restore_defaults()
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM1"), 2)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].minimum, 1)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].items["ITEM1"].maximum, 3)
        self.assertEqual(self.pc.commands["TGT1"]["PKT1"].read("ITEM2"), "NO")
        tf.close()

    def test_allows_appending_derived_items(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  APPEND_ITEM item1 0 DERIVED\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(
            self.pc.telemetry["TGT1"]["PKT1"].items["ITEM1"].data_type, "DERIVED"
        )
        tf.close()

    def test_detects_overlapping_items_without_IGNORE_OVERLAP(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  ITEM item2 4 4 UINT\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertIn(
            "Bit definition overlap at bit offset 4 for packet TGT1 PKT1 items ITEM2 and ITEM1",
            self.pc.warnings,
        )
        tf.close()

    def test_ignores_overlapping_items_with_IGNORE_OVERLAP(self):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "Packet"\n')
        tf.write("  IGNORE_OVERLAP\n")
        tf.write("  ITEM item1 0 8 UINT\n")
        tf.write("  ITEM item2 4 4 UINT\n")
        tf.seek(0)
        self.pc.process_file(tf.name, "TGT1")
        self.assertEqual(len(self.pc.warnings), 0)
        tf.close()
