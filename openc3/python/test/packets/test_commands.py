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
from openc3.system.target import Target
from openc3.packets.packet import Packet
from openc3.packets.commands import Commands
from openc3.packets.packet_config import PacketConfig


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
        tf.write('  APPEND_PARAMETER item2 8 UINT 0 200 2 "Item2"\n')
        tf.write('  APPEND_PARAMETER item3 8 UINT 0 200 3 "Item3"\n')
        tf.write('  APPEND_PARAMETER item4 8 UINT 0 200 4 "Item4"\n')
        tf.write('COMMAND tgt1 pkt2 LITTLE_ENDIAN "TGT1 PKT2 Description"\n')
        tf.write('  APPEND_ID_PARAMETER item1 8 UINT 2 2 2 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 8 UINT 0 255 2 "Item2"\n')
        tf.write('    STATE BAD1 0 HAZARDOUS "Hazardous"\n')
        tf.write("    STATE BAD2 1 HAZARDOUS\n")
        tf.write("    STATE GOOD 2 DISABLE_MESSAGES\n")
        tf.write('  APPEND_PARAMETER item3 32 FLOAT 0 1 0 "Item3"\n')
        tf.write('    STATE S1 0.0\n')
        tf.write('    STATE S2 0.25\n')
        tf.write('    STATE S3 0.5\n')
        tf.write('    STATE S4 0.75\n')
        tf.write('    STATE S5 1.0\n')
        tf.write('  APPEND_PARAMETER item4 40 STRING "HELLO"\n')
        tf.write('    STATE HI HELLO\n')
        tf.write('    STATE WO WORLD\n')
        tf.write('    STATE JA JASON\n')
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
        tf.write('COMMAND tgt2 pkt6 BIG_ENDIAN "TGT2 PKT6 Description"\n')
        tf.write('  APPEND_ID_PARAMETER item1 16 UINT 6 6 6 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 16 UINT MIN MAX 0 "Item2" LITTLE_ENDIAN\n')
        tf.write('  APPEND_PARAMETER item3 16 UINT MIN MAX 0 "Item3"\n')
        tf.write('COMMAND tgt2 pkt7 BIG_ENDIAN "TGT2 PKT7 Description"\n')
        tf.write('  APPEND_ID_PARAMETER item1 16 UINT 6 6 6 "Item1"\n')
        tf.write('  APPEND_PARAMETER item2 16 UINT MIN MAX 0 "Item2" LITTLE_ENDIAN\n')
        tf.write('  APPEND_PARAMETER item3 16 UINT MIN MAX 0 "Item3"\n')
        tf.write('    OBFUSCATE\n')
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
        with self.assertRaisesRegex(RuntimeError, "Command target 'TGTX' does not exist"):
            self.cmd.packets("tgtX")

    def test_packets_returns_all_packets_target_tgt1(self):
        pkts = self.cmd.packets("TGT1")
        self.assertEqual(len(pkts), 2)
        self.assertIn("PKT1", pkts.keys())
        self.assertIn("PKT2", pkts.keys())

    def test_packets_returns_all_packets_target_tgt2(self):
        pkts = self.cmd.packets("TGT2")
        self.assertEqual(len(pkts), 5)
        self.assertIn("PKT3", pkts.keys())
        self.assertIn("PKT4", pkts.keys())
        self.assertIn("PKT5", pkts.keys())
        self.assertIn("PKT6", pkts.keys())
        self.assertIn("PKT7", pkts.keys())

    def test_params_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Command target 'TGTX' does not exist"):
            self.cmd.params("TGTX", "PKT1")

    def test_params_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Command packet 'TGT1 PKTX' does not exist"):
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
        with self.assertRaisesRegex(RuntimeError, "Command target 'TGTX' does not exist"):
            self.cmd.packet("tgtX", "pkt1")

    def test_packet_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Command packet 'TGT1 PKTX' does not exist"):
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

    def test_identify_logs_an_invalid_sized_buffer1(self):
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

    def test_identify_logs_an_invalid_sized_buffer2(self):
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
        for range_checking in [True, False]:
            for raw in [True, False]:
                with self.assertRaisesRegex(RuntimeError, "Command target 'TGTX' does not exist"):
                    self.cmd.build_cmd("tgtX", "pkt1", {}, range_checking, raw)

    def test_build_cmd_complains_about_non_existant_packets(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                with self.assertRaisesRegex(RuntimeError, "Command packet 'TGT1 PKTX' does not exist"):
                    self.cmd.build_cmd("tgt1", "pktX", {}, range_checking, raw)

    def test_build_cmd_complains_about_non_existant_items(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                with self.assertRaisesRegex(RuntimeError, "Packet item 'TGT1 PKT1 ITEMX' does not exist"):
                    self.cmd.build_cmd("tgt1", "pkt1", {"itemX": 1}, range_checking, raw)

    def test_build_cmd_complains_about_missing_required_parameters(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                with self.assertRaisesRegex(RuntimeError, "Required command parameter 'TGT2 PKT3 ITEM2' not given"):
                    self.cmd.build_cmd("tgt2", "pkt3", {}, range_checking, raw)

    def test_creates_a_command_packet_with_mixed_endianness(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                items = { "ITEM2": 0xABCD, "ITEM3": 0x6789 }
                cmd = self.cmd.build_cmd("TGT2", "PKT6", items, range_checking, raw)
                self.assertEqual(cmd.read("item1"), 6)
                self.assertEqual(cmd.read("item2"), 0xABCD)
                self.assertEqual(cmd.read("item3"), 0x6789)
                self.assertEqual(cmd.buffer, b"\x00\x06\xCD\xAB\x67\x89")

    def test_build_cmd_resets_the_buffer_size(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                packet = self.cmd.packet("TGT1", "PKT1")
                packet.buffer = b"\x00" * (packet.defined_length + 1)
                self.assertEqual(len(packet.buffer), 5)
                items = {"ITEM2": 10}
                cmd = self.cmd.build_cmd("TGT1", "PKT1", items, range_checking, raw)
                self.assertEqual(cmd.read("ITEM2"), 10)
                self.assertEqual(len(cmd.buffer), 4)

    def test_build_cmd_creates_a_populated_command_packet_with_default_values(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                cmd = self.cmd.build_cmd("TGT1", "PKT1", {}, range_checking, raw)
                self.assertEqual(cmd.read("item1"), 1)
                self.assertEqual(cmd.read("item2"), 2)
                self.assertEqual(cmd.read("item3"), 3)
                self.assertEqual(cmd.read("item4"), 4)

    def test_build_cmd_creates_a_command_packet_with_override_item_values(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                items = {"ITEM2": 10, "ITEM4": 11}
                cmd = self.cmd.build_cmd("TGT1", "PKT1", items, range_checking, raw)
                self.assertEqual(cmd.read("item1"), 1)
                self.assertEqual(cmd.read("item2"), 10)
                self.assertEqual(cmd.read("item3"), 3)
                self.assertEqual(cmd.read("item4"), 11)

    def test_build_cmd_creates_a_command_packet_with_override_item_value_states(self):
        for range_checking in [True, False]:
            for raw in [True, False]:
                if raw:
                    items = {"ITEM2": 2, "ITEM3": 0.5, "ITEM4": "WORLD"}
                else:
                    # Converted (not raw) can take either states or values
                    items = {"ITEM2": 2, "ITEM3": "S3", "ITEM4": "WO"}
                cmd = self.cmd.build_cmd("TGT1", "PKT2", items, range_checking, raw)
                self.assertEqual(cmd.read("item1"), 2)
                self.assertEqual(cmd.read("item2"), "GOOD")
                self.assertEqual(cmd.read("ITEM2", "RAW"), 2)
                self.assertEqual(cmd.read("item3"), "S3")
                self.assertEqual(cmd.read("ITEM3", "RAW"), 0.5)
                self.assertEqual(cmd.read("item4"), "WO")
                self.assertEqual(cmd.read("ITEM4", "RAW"), "WORLD")

    def test_build_cmd_complains_about_out_of_range_item_values(self):
        for raw in [True, False]:
            with self.assertRaisesRegex(
                RuntimeError,
                "Command parameter 'TGT1 PKT1 ITEM2' = 255 not in valid range of 0 to 200",
            ):
                self.cmd.build_cmd("tgt1", "pkt1", {"item2": 255}, True, raw)

    def test_build_cmd_complains_about_out_of_range_item_states(self):
        for raw in [True, False]:
            items = { "ITEM2": 3, "ITEM3": 0.0, "ITEM4": "WORLD" }
            if raw:
                with self.assertRaisesRegex(
                RuntimeError,
                "Command parameter 'TGT1 PKT2 ITEM2' = 3 not one of 0, 1, 2",
                ):
                    self.cmd.build_cmd("tgt1", "pkt2", items, True, raw)
            else:
                with self.assertRaisesRegex(
                RuntimeError,
                "Command parameter 'TGT1 PKT2 ITEM2' = 3 not one of BAD1, BAD2, GOOD",
                ):
                    self.cmd.build_cmd("tgt1", "pkt2", items, True, raw)

            items = { "ITEM2": 0, "ITEM3": 2.0, "ITEM4": "WORLD" }
            if raw:
                with self.assertRaisesRegex(
                RuntimeError,
                "Command parameter 'TGT1 PKT2 ITEM3' = 2.0 not one of 0.0, 0.25, 0.5, 0.75, 1.0",
                ):
                    self.cmd.build_cmd("tgt1", "pkt2", items, True, raw)
            else:
                with self.assertRaisesRegex(
                RuntimeError,
                "Command parameter 'TGT1 PKT2 ITEM3' = 2.0 not one of S1, S2, S3, S4, S5",
                ):
                    self.cmd.build_cmd("tgt1", "pkt2", items, True, raw)

            items = { "ITEM2": 0, "ITEM3": 0.0, "ITEM4": "TESTY" }
            if raw:
                with self.assertRaisesRegex(
                RuntimeError,
                "Command parameter 'TGT1 PKT2 ITEM4' = TESTY not one of HELLO, WORLD, JASON",
                ):
                    self.cmd.build_cmd("tgt1", "pkt2", items, True, raw)
            else:
                with self.assertRaisesRegex(
                RuntimeError,
                "Command parameter 'TGT1 PKT2 ITEM4' = TESTY not one of HI, WO, JA",
                ):
                    self.cmd.build_cmd("tgt1", "pkt2", items, True, raw)

    def test_build_cmd_ignores_about_out_of_range_item_values(self):
        for raw in [True, False]:
            cmd = self.cmd.build_cmd("tgt1", "pkt1", {"item2": 255}, False, raw)
            self.assertEqual(cmd.read("item1"), 1)
            self.assertEqual(cmd.read("item2"), 255)
            self.assertEqual(cmd.read("item3"), 3)
            self.assertEqual(cmd.read("item4"), 4)


    def test_build_cmd_ignores_out_of_range_item_states(self):
        for raw in [True, False]:
            items = { "ITEM2": 3, "ITEM3": 0.0, "ITEM4": "WORLD" }
            cmd = self.cmd.build_cmd("tgt1", "pkt2", items, False, raw)
            self.assertEqual(cmd.read("item2", 'RAW'), 3)
            self.assertEqual(cmd.read("item3", 'RAW'), 0.0)
            self.assertEqual(cmd.read("item4", 'RAW'), 'WORLD')

            items = { "ITEM2": 0, "ITEM3": 2.0, "ITEM4": "WORLD" }
            cmd = self.cmd.build_cmd("tgt1", "pkt2", items, False, raw)
            self.assertEqual(cmd.read("item2", 'RAW'), 0)
            self.assertEqual(cmd.read("item3", 'RAW'), 2.0)
            self.assertEqual(cmd.read("item4", 'RAW'), 'WORLD')

            items = { "ITEM2": 0, "ITEM3": 0.0, "ITEM4": "TESTY" }
            cmd = self.cmd.build_cmd("tgt1", "pkt2", items, False, raw)
            self.assertEqual(cmd.read("item2", 'RAW'), 0)
            self.assertEqual(cmd.read("item3", 'RAW'), 0.0)
            self.assertEqual(cmd.read("item4", 'RAW'), 'TESTY')

    def test_build_cmd_supports_building_raw_commands(self):
        items = {"ITEM2": 10}
        cmd = self.cmd.build_cmd("TGT2", "PKT5", items, False, False)
        self.assertEqual(cmd.raw, False)
        self.assertEqual(cmd.read("ITEM2"), 20)
        items = {"ITEM2": 10}
        cmd = self.cmd.build_cmd("TGT1", "PKT1", items, False, True)
        self.assertEqual(cmd.raw, True)
        self.assertEqual(cmd.read("ITEM2"), 10)

    def test_format_creates_a_string_representation_of_a_command(self):
        pkt = self.cmd.packet("TGT1", "PKT1")
        self.assertEqual(
            self.cmd.format(pkt),
            'cmd("TGT1 PKT1 with ITEM1 0, ITEM2 0, ITEM3 0, ITEM4 0")',
        )

        pkt = self.cmd.packet("TGT2", "PKT4")
        pkt.write("ITEM2", "HELLO WORLD")
        self.assertEqual(self.cmd.format(pkt), "cmd(\"TGT2 PKT4 with ITEM1 0, ITEM2 'HELLO WORLD'\")")

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
        with self.assertRaisesRegex(RuntimeError, "Command target 'TGTX' does not exist"):
            self.cmd.cmd_hazardous("tgtX", "pkt1")

    def test_cmd_hazardous_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Command packet 'TGT1 PKTX' does not exist"):
            self.cmd.cmd_hazardous("tgt1", "pktX")

    def test_cmd_hazardous_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(RuntimeError, "Packet item 'TGT1 PKT1 ITEMX' does not exist"):
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

    def test_returns_all_packets(self):
        self.assertEqual(list(self.cmd.all().keys()), ["UNKNOWN", "TGT1", "TGT2"])

    def test_handles_obfuscated_items(self):
        pkt = self.cmd.packet("TGT2", "PKT7")
        self.assertEqual(
            self.cmd.format(pkt, []),
            'cmd("TGT2 PKT7 with ITEM1 0, ITEM2 0, ITEM3 *****")',
        )

    def test_identify_with_subpackets_false_excludes_subpackets(self):
        # Create config with normal command and subpacket
        import tempfile

        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write("COMMAND TGT1 PKT1 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 8 UINT 1 1 1\n")
        tf.write("COMMAND TGT1 SUB1 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 8 UINT 10 10 10\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "TGT1")
        tf.close()

        # Create commands with this config
        from openc3.packets.commands import Commands
        from openc3.system.system import System

        cmd = Commands(pc, System)

        # Packet with ID 1 should identify as PKT1, not SUB1
        packet_data = b"\x01"
        identified = cmd.identify(packet_data, ["TGT1"], subpackets=False)
        self.assertIsNotNone(identified)
        self.assertEqual(identified.packet_name, "PKT1")

    def test_identify_with_subpackets_true_only_identifies_subpackets(self):
        # Create config with normal command and subpacket
        import tempfile

        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write("COMMAND TGT1 PKT1 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 8 UINT 1 1 1\n")
        tf.write("COMMAND TGT1 SUB1 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 8 UINT 10 10 10\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "TGT1")
        tf.close()

        # Create commands with this config
        from openc3.packets.commands import Commands
        from openc3.system.system import System

        cmd = Commands(pc, System)

        # Packet with ID 10 should identify as SUB1
        packet_data = b"\x0A"
        identified = cmd.identify(packet_data, ["TGT1"], subpackets=True)
        self.assertIsNotNone(identified)
        self.assertEqual(identified.packet_name, "SUB1")

        # Packet with ID 1 should NOT be identified when looking for subpackets
        packet_data = b"\x01"
        identified = cmd.identify(packet_data, ["TGT1"], subpackets=True)
        self.assertIsNone(identified)

    def test_cmd_unique_id_mode_returns_mode_for_target(self):
        import tempfile

        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        # Two packets with same ID but different layouts triggers unique_id_mode
        tf.write("COMMAND TGT1 PKT1 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 8 UINT 1 1 1\n")
        tf.write("COMMAND TGT1 PKT2 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 16 UINT 1 1 1\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "TGT1")
        tf.close()

        from openc3.packets.commands import Commands
        from openc3.system.system import System

        cmd = Commands(pc, System)
        self.assertTrue(cmd.cmd_unique_id_mode("TGT1"))

    def test_cmd_subpacket_unique_id_mode_returns_mode_for_target(self):
        import tempfile

        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        # Two subpackets with same ID but different layouts triggers subpacket unique_id_mode
        tf.write("COMMAND TGT1 SUB1 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 8 UINT 1 1 1\n")
        tf.write("COMMAND TGT1 SUB2 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_PARAMETER ITEM1 16 UINT 1 1 1\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "TGT1")
        tf.close()

        from openc3.packets.commands import Commands
        from openc3.system.system import System

        cmd = Commands(pc, System)
        self.assertTrue(cmd.cmd_subpacket_unique_id_mode("TGT1"))