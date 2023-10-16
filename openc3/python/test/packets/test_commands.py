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

import math
import tempfile
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.config.config_parser import ConfigParser
from openc3.system.target import Target
from openc3.packets.packet import Packet
from openc3.packets.commands import Commands
from openc3.packets.packet_config import PacketConfig
from openc3.packets.packet_item import PacketItem
from openc3.processors.processor import Processor
from openc3.conversions.generic_conversion import GenericConversion
from openc3.accessors.binary_accessor import BinaryAccessor
from openc3.conversions.packet_time_seconds_conversion import (
    PacketTimeSecondsConversion,
)
from openc3.conversions.received_time_seconds_conversion import (
    ReceivedTimeSecondsConversion,
)
from datetime import datetime


class TestCommands(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        # setup_system()
        System.instance_obj = None

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("# This is a comment\n")
        tf.write("#\n")
        tf.write('COMMAND tgt1 pkt1 LITTLE_ENDIAN "TGT1 PKT1 Description"\n')
        tf.write('  APPEND_ID_PARAMETER item1 8 UINT 1 1 1 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 8 UINT 0 254 2 "Item2"\n')
        tf.write('  APPEND_PARAMETER item3 8 UINT 0 254 3 "Item3"\n')
        tf.write('  APPEND_PARAMETER item4 8 UINT 0 254 4 "Item4"\n')
        tf.write('COMMAND tgt1 pkt2 LITTLE_ENDIAN "TGT1 PKT2 Description"\n')
        tf.write('  APPEND_ID_PARAMETER item1 8 UINT 2 2 2 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 8 UINT 0 255 2 "Item2"\n')
        tf.write('    STATE BAD1 0 HAZARDOUS "Hazardous"\n')
        tf.write("    STATE BAD2 1 HAZARDOUS\n")
        tf.write("    STATE GOOD 2 DISABLE_MESSAGES\n")
        tf.write('COMMAND tgt2 pkt3 LITTLE_ENDIAN "TGT2 PKT3 Description"\n')
        tf.write('  HAZARDOUS "Hazardous"\n')
        tf.write('  APPEND_ID_PARAMETER item1 8 UINT 3 3 3 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 8 UINT 0 255 2 "Item2"\n')
        tf.write("    REQUIRED\n")
        tf.write('COMMAND tgt2 pkt4 LITTLE_ENDIAN "TGT2 PKT4 Description"\n')
        tf.write('  APPEND_ID_PARAMETER item1 8 UINT 4 4 4 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 2056 STRING "Item2"\n')
        tf.write("    OVERFLOW TRUNCATE\n")
        tf.write('COMMAND tgt2 pkt5 LITTLE_ENDIAN "TGT2 PKT5 Description"\n')
        tf.write('  APPEND_ID_PARAMETER item1 8 UINT 5 5 5 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 8 UINT 0 100 0 "Item2"\n')
        tf.write("    POLY_WRITE_CONVERSION 0 2\n")
        tf.seek(0)

        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        System.targets["TGT1"] = Target("TGT1", os.getcwd())
        self.cmd = Commands(pc, System)
        tf.close()

    def test_target_names_returns_an_empty_array_if_no_targets(self):
        self.assertEqual(len(Commands(PacketConfig(), System).warnings()), 0)
        self.assertEqual(Commands(PacketConfig(), System).target_names(), [])

    def test_target_names_returns_all_target_names(self):
        self.assertEqual(self.cmd.target_names(), ["TGT1", "TGT2"])

    def test_packets_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command target 'TGTX' does not exist"
        ):
            self.cmd.packets("tgtX")

    def test_packets_returns_all_packets_target_tgt1(self):
        pkts = self.cmd.packets("TGT1")
        self.assertEqual(len(pkts), 2)
        self.assertIn("PKT1", pkts.keys())
        self.assertIn("PKT2", pkts.keys())

    def test_packets_returns_all_packets_target_tgt2(self):
        pkts = self.cmd.packets("TGT2")
        self.assertEqual(len(pkts), 3)
        self.assertIn("PKT3", pkts.keys())
        self.assertIn("PKT4", pkts.keys())
        self.assertIn("PKT5", pkts.keys())

    def test_params_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command target 'TGTX' does not exist"
        ):
            self.cmd.params("TGTX", "PKT1")

    def test_params_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command packet 'TGT1 PKTX' does not exist"
        ):
            self.cmd.params("TGT1", "PKTX")

    def test_params_returns_all_items_from_packet_tgt1_pkt1(self):
        items = self.cmd.params("TGT1", "PKT1")
        self.assertEqual(len(items), 9)
        for reserved in Packet.RESERVED_ITEM_NAMES:
            self.assertIn(reserved, [item.name for item in items])
        self.assertEqual(items[5].name, "ITEM1")
        self.assertEqual(items[6].name, "ITEM2")
        self.assertEqual(items[7].name, "ITEM3")
        self.assertEqual(items[8].name, "ITEM4")

    def test_packet_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command target 'TGTX' does not exist"
        ):
            self.cmd.packet("tgtX", "pkt1")

    def test_packet_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command packet 'TGT1 PKTX' does not exist"
        ):
            self.cmd.packet("TGT1", "PKTX")

    def test_packet_returns_the_specified_packet(self):
        pkt = self.cmd.packet("TGT1", "PKT1")
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")

    def test_identify_return_None_with_a_None_buffer(self):
        self.assertIsNone(self.cmd.identify(None))

    def test_identify_only_checks_the_targets_given(self):
        buffer = b"\x01\x02\x03\x04"
        pkt = self.cmd.identify(buffer, ["TGT1"])
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 3)
        self.assertEqual(pkt.read("item4"), 4)

    def test_identify_works_in_unique_id_mode_or_not(self):
        System.targets["TGT1"] = Target("TGT1", os.getcwd())
        target = System.targets["TGT1"]
        target.cmd_unique_id_mode = False
        buffer = b"\x01\x02\x03\x04"
        pkt = self.cmd.identify(buffer, ["TGT1"])
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 3)
        self.assertEqual(pkt.read("item4"), 4)
        target.cmd_unique_id_mode = True
        buffer = b"\x01\x02\x01\x02"
        pkt = self.cmd.identify(buffer, ["TGT1"])
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 1)
        self.assertEqual(pkt.read("item4"), 2)
        target.cmd_unique_id_mode = False

    def test_identify_returns_None_with_unknown_targets_given(self):
        buffer = b"\x01\x02\x03\x04"
        self.assertIsNone(self.cmd.identify(buffer, ["TGTX"]))

    def test_identify_logs_an_invalid_sized_buffer(self):
        for stdout in capture_io():
            buffer = b"\x01\x02\x03"
            pkt = self.cmd.identify(buffer)
            self.assertEqual(pkt.read("item1"), 1)
            self.assertEqual(pkt.read("item2"), 2)
            self.assertEqual(pkt.read("item3"), 3)
            self.assertEqual(pkt.read("item4"), 0)
            self.assertIn(
                "TGT1 PKT1 buffer (<class 'bytes'>) received with actual packet length of 3 but defined length of 4",
                stdout.getvalue(),
            )

    def test_identify_logs_an_invalid_sized_buffer(self):
        for stdout in capture_io():
            buffer = b"\x01\x02\x03\x04\x05"
            pkt = self.cmd.identify(buffer)
            self.assertEqual(pkt.read("item1"), 1)
            self.assertEqual(pkt.read("item2"), 2)
            self.assertEqual(pkt.read("item3"), 3)
            self.assertEqual(pkt.read("item4"), 4)
            self.assertIn(
                "TGT1 PKT1 buffer (<class 'bytes'>) received with actual packet length of 5 but defined length of 4",
                stdout.getvalue(),
            )

    def test_identifies_tgt1_pkt1_but_not_affect_the_latest_data_table(self):
        buffer = b"\x01\x02\x03\x04"
        pkt = self.cmd.identify(buffer)
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 3)
        self.assertEqual(pkt.read("item4"), 4)

        # Now request the packet from the latest data table
        pkt = self.cmd.packet("TGT1", "PKT1")
        self.assertEqual(pkt.read("item1"), 0)
        self.assertEqual(pkt.read("item2"), 0)
        self.assertEqual(pkt.read("item3"), 0)
        self.assertEqual(pkt.read("item4"), 0)

    def test_identifies_tgt1_pkt2(self):
        buffer = b"\x02\x02"
        pkt = self.cmd.identify(buffer)
        self.assertEqual(pkt.read("item1"), 2)
        self.assertEqual(pkt.read("item2"), "GOOD")

    def test_identifies_tgt2_pkt1(self):
        buffer = b"\x03\x02"
        pkt = self.cmd.identify(buffer)
        self.assertEqual(pkt.read("item1"), 3)
        self.assertEqual(pkt.read("item2"), 2)

    def test_build_cmd_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command target 'TGTX' does not exist"
        ):
            self.cmd.build_cmd("tgtX", "pkt1")

    def test_build_cmd_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command packet 'TGT1 PKTX' does not exist"
        ):
            self.cmd.build_cmd("tgt1", "pktX")

    def test_build_cmd_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            AttributeError, f"Packet item 'TGT1 PKT1 ITEMX' does not exist"
        ):
            self.cmd.build_cmd("tgt1", "pkt1", {"itemX": 1})

    def test_build_cmd_creates_a_populated_command_packet_with_default_values(self):
        cmd = self.cmd.build_cmd("TGT1", "PKT1")
        self.assertEqual(cmd.read("item1"), 1)
        self.assertEqual(cmd.read("item2"), 2)
        self.assertEqual(cmd.read("item3"), 3)
        self.assertEqual(cmd.read("item4"), 4)

    def test_build_cmd_complains_about_out_of_range_item_values(self):
        with self.assertRaisesRegex(
            RuntimeError,
            f"Command parameter 'TGT1 PKT1 ITEM2' = 1000 not in valid range of 0 to 254",
        ):
            self.cmd.build_cmd("tgt1", "pkt1", {"item2": 1000})

    def test_build_cmd_ignores_out_of_range_item_values_if_requested(self):
        cmd = self.cmd.build_cmd("tgt1", "pkt1", {"item2": 255}, False)
        self.assertEqual(cmd.read("item1"), 1)
        self.assertEqual(cmd.read("item2"), 255)
        self.assertEqual(cmd.read("item3"), 3)
        self.assertEqual(cmd.read("item4"), 4)

    def test_build_cmd_creates_a_command_packet_with_override_item_values(self):
        items = {"ITEM2": 10, "ITEM4": 11}
        cmd = self.cmd.build_cmd("TGT1", "PKT1", items)
        self.assertEqual(cmd.read("item1"), 1)
        self.assertEqual(cmd.read("item2"), 10)
        self.assertEqual(cmd.read("item3"), 3)
        self.assertEqual(cmd.read("item4"), 11)

    def test_build_cmd_creates_a_command_packet_with_override_item_value_states(self):
        items = {"ITEM2": "GOOD"}
        cmd = self.cmd.build_cmd("TGT1", "PKT2", items)
        self.assertEqual(cmd.read("item1"), 2)
        self.assertEqual(cmd.read("item2"), "GOOD")
        self.assertEqual(cmd.read("ITEM2", "RAW"), 2)

    def test_build_cmd_complains_about_missing_required_parameters(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Required command parameter 'TGT2 PKT3 ITEM2' not given"
        ):
            self.cmd.build_cmd("tgt2", "pkt3")

    def test_build_cmd_supports_building_raw_commands(self):
        items = {"ITEM2": 10}
        cmd = self.cmd.build_cmd("TGT2", "PKT5", items, False, False)
        self.assertEqual(cmd.raw, False)
        self.assertEqual(cmd.read("ITEM2"), 20)
        items = {"ITEM2": 10}
        cmd = self.cmd.build_cmd("TGT1", "PKT1", items, False, True)
        self.assertEqual(cmd.raw, True)
        self.assertEqual(cmd.read("ITEM2"), 10)

    def test_build_cmd_resets_the_buffer_size(self):
        packet = self.cmd.packet("TGT1", "PKT1")
        packet.buffer = b"\x00" * (packet.defined_length + 1)
        self.assertEqual(len(packet.buffer), 5)
        items = {"ITEM2": 10}
        cmd = self.cmd.build_cmd("TGT1", "PKT1", items)
        self.assertEqual(cmd.read("ITEM2"), 10)
        self.assertEqual(len(cmd.buffer), 4)

    def test_format_creates_a_string_representation_of_a_command(self):
        pkt = self.cmd.packet("TGT1", "PKT1")
        self.assertEqual(
            self.cmd.format(pkt),
            'cmd("TGT1 PKT1 with ITEM1 0, ITEM2 0, ITEM3 0, ITEM4 0")',
        )

        pkt = self.cmd.packet("TGT2", "PKT4")
        pkt.write("ITEM2", "HELLO WORLD")
        self.assertEqual(
            self.cmd.format(pkt), "cmd(\"TGT2 PKT4 with ITEM1 0, ITEM2 'HELLO WORLD'\")"
        )

        pkt = self.cmd.packet("TGT2", "PKT4")
        pkt.write("ITEM2", "HELLO WORLD")
        pkt.raw = True
        self.assertEqual(
            self.cmd.format(pkt),
            "cmd_raw(\"TGT2 PKT4 with ITEM1 0, ITEM2 'HELLO WORLD'\")",
        )

        # If the string is too big it should truncate it
        string = ""
        for i in range(0, 256):
            string += "A"
        pkt.write("ITEM2", string)
        pkt.raw = False
        result = self.cmd.format(pkt)
        self.assertIn("cmd(\"TGT2 PKT4 with ITEM1 0, ITEM2 'AAAAAAAAAAA", result)
        self.assertIn("AAAAAAAAAAA...", result)

    def test_format_ignores_parameters(self):
        pkt = self.cmd.packet("TGT1", "PKT1")
        self.assertEqual(
            self.cmd.format(pkt, ["ITEM3", "ITEM4"]),
            'cmd("TGT1 PKT1 with ITEM1 0, ITEM2 0")',
        )

    def test_cmd_hazardous_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command target 'TGTX' does not exist"
        ):
            self.cmd.cmd_hazardous("tgtX", "pkt1")

    def test_cmd_hazardous_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(
            RuntimeError, f"Command packet 'TGT1 PKTX' does not exist"
        ):
            self.cmd.cmd_hazardous("tgt1", "pktX")

    def test_cmd_hazardous_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            AttributeError, f"Packet item 'TGT1 PKT1 ITEMX' does not exist"
        ):
            self.cmd.cmd_hazardous("tgt1", "pkt1", {"itemX": 1})

    def test_cmd_hazardous_returns_true_if_the_command_overall_is_hazardous(self):
        hazardous, description = self.cmd.cmd_hazardous("TGT1", "PKT1")
        self.assertFalse(hazardous)
        self.assertIsNone(description)
        hazardous, description = self.cmd.cmd_hazardous("tgt2", "pkt3")
        self.assertTrue(hazardous)
        self.assertEqual(description, "Hazardous")

    def test_cmd_hazardous_returns_true_if_a_command_parameter_is_hazardous(self):
        hazardous, description = self.cmd.cmd_hazardous("TGT1", "PKT2", {"ITEM2": 0})
        self.assertTrue(hazardous)
        self.assertEqual(description, "Hazardous")
        hazardous, description = self.cmd.cmd_hazardous("TGT1", "PKT2", {"ITEM2": 1})
        self.assertTrue(hazardous)
        self.assertEqual(description, "")
        hazardous, description = self.cmd.cmd_hazardous("TGT1", "PKT2", {"ITEM2": 2})
        self.assertFalse(hazardous)
        self.assertIsNone(description)

    def test_clears_the_received_counters_in_all_packets(self):
        self.cmd.packet("TGT1", "PKT1").received_count = 1
        self.cmd.packet("TGT1", "PKT2").received_count = 2
        self.cmd.packet("TGT2", "PKT3").received_count = 3
        self.cmd.packet("TGT2", "PKT4").received_count = 4
        self.cmd.clear_counters()
        self.assertEqual(self.cmd.packet("TGT1", "PKT1").received_count, 0)
        self.assertEqual(self.cmd.packet("TGT1", "PKT2").received_count, 0)
        self.assertEqual(self.cmd.packet("TGT2", "PKT3").received_count, 0)
        self.assertEqual(self.cmd.packet("TGT2", "PKT4").received_count, 0)

    def test_returns_all_packets(self):
        self.assertEqual(list(self.cmd.all().keys()), ["UNKNOWN", "TGT1", "TGT2"])
