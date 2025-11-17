# Copyright 2025 OpenC3, Inc.
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

import os
import tempfile
import unittest
from unittest.mock import Mock
from test.test_helper import mock_redis, setup_system, capture_io
from openc3.system.target import Target
from openc3.system.system import System
from openc3.packets.packet import Packet
from openc3.packets.packet_config import PacketConfig
from openc3.packets.telemetry import Telemetry


class TestTelemetry(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("# This is a comment\n")
        tf.write("#\n")
        tf.write('TELEMETRY tgt1 pkt1 LITTLE_ENDIAN "TGT1 PKT1 Description"\n')
        tf.write('  APPEND_ID_ITEM item1 8 UINT 1 "Item1"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 1 2 4 5\n")
        tf.write('  APPEND_ITEM item2 8 UINT "Item2"\n')
        tf.write("    LIMITS DEFAULT 1 ENABLED 1 2 4 5\n")
        tf.write('  APPEND_ITEM item3 8 UINT "Item3"\n')
        tf.write("    POLY_READ_CONVERSION 0 2\n")
        tf.write('  APPEND_ITEM item4 8 UINT "Item4"\n')
        tf.write("    POLY_READ_CONVERSION 0 2\n")
        tf.write('TELEMETRY tgt1 pkt2 LITTLE_ENDIAN "TGT1 PKT2 Description"\n')
        tf.write('  APPEND_ID_ITEM item1 8 UINT 2 "Item1"\n')
        tf.write('  APPEND_ITEM item2 8 UINT "Item2"\n')
        tf.write('TELEMETRY tgt2 pkt1 LITTLE_ENDIAN "TGT2 PKT1 Description"\n')
        tf.write('  APPEND_ID_ITEM item1 8 UINT 3 "Item1"\n')
        tf.write('  APPEND_ITEM item2 8 UINT "Item2"\n')
        tf.seek(0)

        # Verify initially that everything is empty
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        System.targets["TGT1"] = Target("TGT1", os.getcwd())
        System.targets["TGT2"] = Target("TGT2", os.getcwd())
        self.tlm = Telemetry(pc, System)
        tf.close()

    def test_has_no_warnings(self):
        self.assertEqual(Telemetry(PacketConfig(), System).warnings(), [])

    def test_returns_an_empty_array_if_no_targets(self):
        self.assertEqual(Telemetry(PacketConfig(), System).target_names(), [])

    def test_returns_all_target_names(self):
        self.assertEqual(self.tlm.target_names(), ["TGT1", "TGT2"])

    def test_packets_complains_about_non_existent_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry target 'TGTX' does not exist"):
            self.tlm.packets("tgtX")

    def test_packets_returns_all_packets_target_tgt1(self):
        pkts = self.tlm.packets("TGT1")
        self.assertEqual(len(pkts), 2)
        self.assertIn("PKT1", pkts.keys())
        self.assertIn("PKT2", pkts.keys())

    def test_packets_returns_all_packets_target_tgt2(self):
        pkts = self.tlm.packets("TGT2")
        self.assertEqual(len(pkts), 1)
        self.assertIn("PKT1", pkts.keys())

    def test_packet_complains_about_non_existent_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry target 'TGTX' does not exist"):
            self.tlm.packet("tgtX", "pkt1")

    def test_packet_complains_about_non_existent_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry packet 'TGT1 PKTX' does not exist"):
            self.tlm.packet("TGT1", "PKTX")

    def test_packet_complains_about_the_latest_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry packet 'TGT1 LATEST' does not exist"):
            self.tlm.packet("TGT1", "LATEST")

    def test_packet_returns_the_specified_packet(self):
        pkt = self.tlm.packet("TGT1", "PKT1")
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")

    def test_identify_returns_None_with_a_None_buffer(self):
        self.assertIsNone(self.tlm.identify_and_set_buffer(None))

    def test_identify_only_checks_the_targets_given(self):
        buffer = b"\x01\x02\x03\x04"
        self.tlm.identify_and_set_buffer(buffer, ["TGT1"])
        pkt = self.tlm.packet("TGT1", "PKT1")
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 6.0)
        self.assertEqual(pkt.read("item4"), 8.0)

    def test_identify_works_in_unique_id_mode_and_not(self):
        System.targets["TGT1"] = Target("TGT1", os.getcwd())
        target = System.targets["TGT1"]
        buffer = b"\x01\x02\x03\x04"
        target.tlm_unique_id_mode = False
        pkt = self.tlm.identify_and_set_buffer(buffer, ["TGT1"])
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 6.0)
        self.assertEqual(pkt.read("item4"), 8.0)
        buffer = b"\x01\x02\x01\x02"
        target.tlm_unique_id_mode = True
        self.tlm.identify_and_set_buffer(buffer, ["TGT1"])
        pkt = self.tlm.packet("TGT1", "PKT1")
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 2.0)
        self.assertEqual(pkt.read("item4"), 4.0)
        target.tlm_unique_id_mode = False

    def test_identify_returns_None_with_unknown_targets_given(self):
        buffer = b"\x01\x02\x03\x04"
        self.assertIsNone(self.tlm.identify_and_set_buffer(buffer, ["TGTX"]))

    def test_identify_identify_logs_an_invalid_sized_buffer(self):
        for stdout in capture_io():
            buffer = b"\x01\x02\x03\x04\x05"
            self.tlm.identify_and_set_buffer(buffer)
            pkt = self.tlm.packet("TGT1", "PKT1")
            self.assertEqual(pkt.read("item1"), 1)
            self.assertEqual(pkt.read("item2"), 2)
            self.assertEqual(pkt.read("item3"), 6.0)
            self.assertEqual(pkt.read("item4"), 8.0)
            self.assertIn(
                "TGT1 PKT1 buffer (<class 'bytes'>) received with actual packet length of 5 but defined length of 4",
                stdout.getvalue(),
            )

    def test_identify_identifies_tgt1_pkt1(self):
        buffer = b"\x01\x02\x03\x04"
        self.tlm.identify_and_set_buffer(buffer)
        pkt = self.tlm.packet("TGT1", "PKT1")
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 6.0)
        self.assertEqual(pkt.read("item4"), 8.0)

    def test_identify_identifies_tgt1_pkt2(self):
        buffer = b"\x02\x02"
        self.tlm.identify_and_set_buffer(buffer)
        pkt = self.tlm.packet("TGT1", "PKT2")
        self.assertEqual(pkt.read("item1"), 2)
        self.assertEqual(pkt.read("item2"), 2)

    def test_identify_identifies_tgt2_pkt1(self):
        buffer = b"\x03\x02"
        self.tlm.identify_and_set_buffer(buffer)
        pkt = self.tlm.packet("TGT2", "PKT1")
        self.assertEqual(pkt.read("item1"), 3)
        self.assertEqual(pkt.read("item2"), 2)

    def test_identify_and_define_identifies_packets(self):
        unknown = Packet(None, None)
        unknown.buffer = b"\x01\x02\x03\x04"
        pkt = self.tlm.identify_and_define_packet(unknown)
        self.assertEqual(pkt.target_name, "TGT1")
        self.assertEqual(pkt.packet_name, "PKT1")
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 6.0)
        self.assertEqual(pkt.read("item4"), 8.0)

    def test_identify_and_define_returns_None_for_unidentified(self):
        unknown = Packet(None, None)
        unknown.buffer = b"\xFF\xFF\xFF\xFF"
        pkt = self.tlm.identify_and_define_packet(unknown)
        self.assertIsNone(pkt)

    def test_identify_and_define_defines_packets(self):
        unknown = Packet("TGT1", "PKT1")
        unknown.buffer = b"\x01\x02\x03\x04"
        pkt = self.tlm.identify_and_define_packet(unknown)
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 6.0)
        self.assertEqual(pkt.read("item4"), 8.0)
        # It simply returns the packet if it is already identified and defined
        pkt2 = self.tlm.identify_and_define_packet(pkt)
        self.assertEqual(pkt2, pkt)

    def test_identify_and_define_returns_None_for_undefined(self):
        unknown = Packet("TGTX", "PKTX")
        unknown.buffer = b"\x01\x02\x03\x04"
        pkt = self.tlm.identify_and_define_packet(unknown)
        self.assertIsNone(pkt)

    def test_update_complains_about_non_existent_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry target 'TGTX' does not exist"):
            self.tlm.update("TGTX", "PKT1", b"\x00")

    def test_update_complains_about_non_existent_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry packet 'TGT1 PKTX' does not exist"):
            self.tlm.update("TGT1", "PKTX", b"\x00")

    def test_update_complains_about_the_latest_packet(self):
        with self.assertRaisesRegex(RuntimeError, "Telemetry packet 'TGT1 LATEST' does not exist"):
            self.tlm.update("TGT1", "LATEST", b"\x00")

    def test_update_complains_with_a_None_buffer(self):
        with self.assertRaisesRegex(TypeError, "Buffer class is NoneType but must be bytearray"):
            self.tlm.update("TGT1", "PKT1", None)

    def test_update_update_logs_an_invalid_sized_buffer(self):
        for stdout in capture_io():
            buffer = b"\x01\x02\x03\x04\x05"
            self.tlm.update("TGT1", "PKT1", buffer)
            pkt = self.tlm.packet("TGT1", "PKT1")
            self.assertEqual(pkt.read("item1"), 1)
            self.assertEqual(pkt.read("item2"), 2)
            self.assertEqual(pkt.read("item3"), 6.0)
            self.assertEqual(pkt.read("item4"), 8.0)
            self.assertIn(
                "TGT1 PKT1 buffer (<class 'bytes'>) received with actual packet length of 5 but defined length of 4",
                stdout.getvalue(),
            )

    def test_update_updates_a_packet_with_the_given_data(self):
        self.tlm.update("TGT1", "PKT1", b"\x01\x02\x03\x04")
        pkt = self.tlm.packet("TGT1", "PKT1")
        self.assertEqual(pkt.read("item1"), 1)
        self.assertEqual(pkt.read("item2"), 2)
        self.assertEqual(pkt.read("item3"), 6.0)
        self.assertEqual(pkt.read("item4"), 8.0)

    def test_assigns_a_callback_to_each_packet(self):
        callback = Mock()
        self.tlm.set_limits_change_callback(callback)
        self.tlm.update("TGT1", "PKT1", b"\x01\x02\x03\x04")
        self.tlm.update("TGT1", "PKT2", b"\x05\x06")
        self.tlm.update("TGT2", "PKT1", b"\x07\x08")
        self.tlm.packet("TGT1", "PKT1").check_limits()
        self.tlm.packet("TGT1", "PKT2").check_limits()
        self.tlm.packet("TGT2", "PKT1").check_limits()
        callback.assert_called()

    def test_reset_resets_all_packets(self):
        for _name, pkt in self.tlm.packets("TGT1").items():
            pkt.received_count = 1
        for _name, pkt in self.tlm.packets("TGT2").items():
            pkt.received_count = 1
        self.tlm.reset()
        for _name, pkt in self.tlm.packets("TGT1").items():
            self.assertEqual(pkt.received_count, 0)
        for _name, pkt in self.tlm.packets("TGT2").items():
            self.assertEqual(pkt.received_count, 0)

    def test_all_returns_all_packets(self):
        self.assertEqual(list(self.tlm.all().keys()), ["UNKNOWN", "TGT1", "TGT2"])

    def test_identify_with_subpackets_false_excludes_subpackets(self):
        # Create config with normal packet and subpacket
        import tempfile
        from openc3.packets.packet_config import PacketConfig

        pc = PacketConfig()
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write("TELEMETRY TGT1 PKT1 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_ITEM ITEM1 8 UINT 1\n")
        tf.write("TELEMETRY TGT1 SUB1 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_ITEM ITEM1 8 UINT 10\n")
        tf.seek(0)
        pc.process_file(tf.name, "TGT1")
        tf.close()

        # Create telemetry with this config
        from openc3.packets.telemetry import Telemetry
        from openc3.system.system import System

        tlm = Telemetry(pc, System)

        # Packet with ID 1 should identify as PKT1, not SUB1
        packet_data = b"\x01"
        identified = tlm.identify(packet_data, ["TGT1"], subpackets=False)
        self.assertIsNotNone(identified)
        self.assertEqual(identified.packet_name, "PKT1")

    def test_identify_with_subpackets_true_only_identifies_subpackets(self):
        # Create config with normal packet and subpacket
        import tempfile
        from openc3.packets.packet_config import PacketConfig

        pc = PacketConfig()
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write("TELEMETRY TGT1 PKT1 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_ITEM ITEM1 8 UINT 1\n")
        tf.write("TELEMETRY TGT1 SUB1 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_ITEM ITEM1 8 UINT 10\n")
        tf.seek(0)
        pc.process_file(tf.name, "TGT1")
        tf.close()

        # Create telemetry with this config
        from openc3.packets.telemetry import Telemetry
        from openc3.system.system import System

        tlm = Telemetry(pc, System)

        # Packet with ID 10 should identify as SUB1
        packet_data = b"\x0A"
        identified = tlm.identify(packet_data, ["TGT1"], subpackets=True)
        self.assertIsNotNone(identified)
        self.assertEqual(identified.packet_name, "SUB1")

        # Packet with ID 1 should NOT be identified when looking for subpackets
        packet_data = b"\x01"
        identified = tlm.identify(packet_data, ["TGT1"], subpackets=True)
        self.assertIsNone(identified)

    def test_tlm_unique_id_mode_returns_mode_for_target(self):
        import tempfile
        from openc3.packets.packet_config import PacketConfig

        pc = PacketConfig()
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        # Two packets with same ID but different layouts triggers unique_id_mode
        tf.write("TELEMETRY TGT1 PKT1 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_ITEM ITEM1 8 UINT 1\n")
        tf.write("TELEMETRY TGT1 PKT2 BIG_ENDIAN\n")
        tf.write("  APPEND_ID_ITEM ITEM1 16 UINT 1\n")
        tf.seek(0)
        pc.process_file(tf.name, "TGT1")
        tf.close()

        from openc3.packets.telemetry import Telemetry
        from openc3.system.system import System

        tlm = Telemetry(pc, System)
        self.assertTrue(tlm.tlm_unique_id_mode("TGT1"))

    def test_tlm_subpacket_unique_id_mode_returns_mode_for_target(self):
        import tempfile
        from openc3.packets.packet_config import PacketConfig

        pc = PacketConfig()
        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        # Two subpackets with same ID but different layouts triggers subpacket unique_id_mode
        tf.write("TELEMETRY TGT1 SUB1 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_ITEM ITEM1 8 UINT 1\n")
        tf.write("TELEMETRY TGT1 SUB2 BIG_ENDIAN\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_ITEM ITEM1 16 UINT 1\n")
        tf.seek(0)
        pc.process_file(tf.name, "TGT1")
        tf.close()

        from openc3.packets.telemetry import Telemetry
        from openc3.system.system import System

        tlm = Telemetry(pc, System)
        self.assertTrue(tlm.tlm_subpacket_unique_id_mode("TGT1"))
