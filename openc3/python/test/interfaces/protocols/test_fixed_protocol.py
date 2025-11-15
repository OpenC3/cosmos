# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from datetime import datetime, timezone
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.fixed_protocol import FixedProtocol
from openc3.streams.stream import Stream


class TestFixedProtocol(unittest.TestCase):
    index = 0

    class FixedStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            match TestFixedProtocol.index:
                case 0:
                    return b"\x00"  # UNKNOWN
                case 1:
                    return b"\x01"  # SYSTEM META
                case 2:
                    return b"\x02"  # SYSTEM LIMITS

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        mock_redis(self)
        setup_system()
        self.interface = TestFixedProtocol.MyInterface()

    def test_initializes_attributes(self):
        self.interface.add_protocol(FixedProtocol, [2, 1, "0xDEADBEEF", False, True], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].data, b"")
        self.assertEqual(self.interface.read_protocols[0].min_id_size, 2)
        self.assertEqual(self.interface.read_protocols[0].discard_leading_bytes, 1)
        self.assertEqual(self.interface.read_protocols[0].sync_pattern, b"\xDE\xAD\xBE\xEF")
        self.assertFalse(self.interface.read_protocols[0].telemetry)
        self.assertTrue(self.interface.read_protocols[0].fill_fields)

    def test_returns_unknown_packets(self):
        self.interface.add_protocol(FixedProtocol, [1], "READ")
        self.interface.stream = TestFixedProtocol.FixedStream()
        self.interface.target_names = ["SYSTEM"]
        self.interface.cmd_target_names = ["SYSTEM"]
        self.interface.tlm_target_names = ["SYSTEM"]
        # Initialize the read with a packet identified as SYSTEM META
        TestFixedProtocol.index = 1
        packet = self.interface.read()
        self.assertNotEqual(packet.received_time.timestamp(), 0.0)
        self.assertEqual(packet.target_name, "SYSTEM")
        self.assertEqual(packet.packet_name, "META")
        self.assertEqual(packet.buffer[0], 1)
        # Return zeros which will not be identified
        TestFixedProtocol.index = 0
        packet = self.interface.read()
        self.assertIsNone(packet.received_time)
        self.assertIsNone(packet.target_name)
        self.assertIsNone(packet.packet_name)
        self.assertEqual(packet.buffer, b"\x00")

    # TODO: Only works when run by itself
    # def test_raises_an_exception_if_unknown_packet(self):
    #     self.interface.add_protocol(
    #         FixedProtocol, [1, 0, None, True, False, True], "READ"
    #     )
    #     self.interface.stream = TestFixedProtocol.FixedStream()
    #     self.interface.target_names = ["SYSTEM"]
    #     self.interface.cmd_target_names = ["SYSTEM"]
    #     self.interface.tlm_target_names = ["SYSTEM"]
    #     with self.assertRaisesRegex(RuntimeError, "Unknown data"):
    #         self.interface.read()

    def test_handles_targets_with_no_defined_telemetry(self):
        self.interface.add_protocol(FixedProtocol, [1], "READ")
        self.interface.stream = TestFixedProtocol.FixedStream()
        self.interface.target_names = ["EMPTY"]
        self.interface.cmd_target_names = ["EMPTY"]
        self.interface.tlm_target_names = ["EMPTY"]
        TestFixedProtocol.index = 1
        packet = self.interface.read()
        self.assertIsNone(packet.received_time)
        self.assertIsNone(packet.target_name)
        self.assertIsNone(packet.packet_name)
        self.assertEqual(packet.buffer, b"\x01")

    def test_reads_telemetry_data_from_the_stream(self):
        target = System.targets["SYSTEM"]
        self.interface.add_protocol(FixedProtocol, [1], "READ_WRITE")
        self.interface.stream = TestFixedProtocol.FixedStream()
        self.interface.target_names = ["SYSTEM"]
        self.interface.cmd_target_names = ["SYSTEM"]
        self.interface.tlm_target_names = ["SYSTEM"]
        TestFixedProtocol.index = 1
        packet = self.interface.read()
        self.assertLess(datetime.now(timezone.utc).timestamp() - packet.received_time.timestamp(), 0.1)
        self.assertEqual(packet.target_name, "SYSTEM")
        self.assertEqual(packet.packet_name, "META")
        TestFixedProtocol.index = 2
        packet = self.interface.read()
        self.assertLess(datetime.now(timezone.utc).timestamp() - packet.received_time.timestamp(), 0.1)
        self.assertEqual(packet.target_name, "SYSTEM")
        self.assertEqual(packet.packet_name, "LIMITS_CHANGE")
        target.tlm_unique_id_mode = True
        TestFixedProtocol.index = 1
        packet = self.interface.read()
        self.assertLess(datetime.now(timezone.utc).timestamp() - packet.received_time.timestamp(), 0.1)
        self.assertEqual(packet.target_name, "SYSTEM")
        self.assertEqual(packet.packet_name, "META")
        TestFixedProtocol.index = 2
        packet = self.interface.read()
        self.assertLess(datetime.now(timezone.utc).timestamp() - packet.received_time.timestamp(), 0.1)
        self.assertEqual(packet.target_name, "SYSTEM")
        self.assertEqual(packet.packet_name, "LIMITS_CHANGE")
        target.tlm_unique_id_mode = False

    def test_reads_command_data_from_the_stream(self):
        target = System.targets["SYSTEM"]
        packet = System.commands.packet("SYSTEM", "STARTLOGGING")
        packet.restore_defaults()
        buffer = packet.buffer[:]

        class FixedStream2(Stream):
            def connect(self):
                pass

            def connected(self):
                return True

            def read(self):
                # Prepend a matching sync pattern to test the discard
                return b"\x1A\xCF\xFC\x1D\x55\x55" + buffer

        # Require 8 bytes, discard 6 leading bytes, use 0x1ACFFC1D sync, telemetry = False (command)
        self.interface.add_protocol(FixedProtocol, [8, 6, "0x1ACFFC1D", False], "READ_WRITE")
        self.interface.stream = FixedStream2()
        self.interface.target_names = ["SYSTEM"]
        self.interface.cmd_target_names = ["SYSTEM"]
        self.interface.tlm_target_names = ["SYSTEM"]
        target.cmd_unique_id_mode = False
        packet = self.interface.read()
        self.assertLess(datetime.now(timezone.utc).timestamp() - packet.received_time.timestamp(), 0.1)
        self.assertEqual(packet.target_name, "SYSTEM")
        self.assertEqual(packet.packet_name, "STARTLOGGING")
        self.assertEqual(packet.buffer, buffer)
        target.cmd_unique_id_mode = True
        packet = self.interface.read()
        self.assertLess(datetime.now(timezone.utc).timestamp() - packet.received_time.timestamp(), 0.1)
        self.assertEqual(packet.target_name, "SYSTEM")
        self.assertEqual(packet.packet_name, "STARTLOGGING")
        self.assertEqual(packet.buffer, buffer)
        target.cmd_unique_id_mode = False

    def test_write_details_returns_correct_information(self):
        self.interface.add_protocol(FixedProtocol, [8, 2, "0xDEADBEEF", True, False, True], "READ_WRITE")
        protocol = self.interface.write_protocols[0]
        details = protocol.write_details()

        # Check that it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check base protocol fields from super()
        self.assertIn("name", details)
        self.assertEqual(details["name"], "FixedProtocol")
        self.assertIn("write_data_input_time", details)
        self.assertIn("write_data_input", details)
        self.assertIn("write_data_output_time", details)
        self.assertIn("write_data_output", details)

        # Check fixed protocol specific fields
        self.assertIn("min_id_size", details)
        self.assertEqual(details["min_id_size"], 8)
        self.assertIn("telemetry", details)
        self.assertEqual(details["telemetry"], True)
        self.assertIn("unknown_raise", details)
        self.assertEqual(details["unknown_raise"], True)

    def test_read_details_returns_correct_information(self):
        self.interface.add_protocol(FixedProtocol, [4, 1, "0xABCD", False, True, False], "READ_WRITE")
        protocol = self.interface.read_protocols[0]
        details = protocol.read_details()

        # Check that it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check base protocol fields from super()
        self.assertIn("name", details)
        self.assertEqual(details["name"], "FixedProtocol")
        self.assertIn("read_data_input_time", details)
        self.assertIn("read_data_input", details)
        self.assertIn("read_data_output_time", details)
        self.assertIn("read_data_output", details)

        # Check fixed protocol specific read fields (same as write for this protocol)
        self.assertIn("min_id_size", details)
        self.assertEqual(details["min_id_size"], 4)
        self.assertIn("telemetry", details)
        self.assertEqual(details["telemetry"], False)
        self.assertIn("unknown_raise", details)
        self.assertEqual(details["unknown_raise"], False)

    def test_identifies_normal_packets_but_not_subpackets(self):
        import tempfile
        from openc3.packets.packet_config import PacketConfig

        tf = tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False)
        tf.write("TELEMETRY TEST PKT1 BIG_ENDIAN 'Normal Packet'\n")
        tf.write("  APPEND_ID_ITEM item1 8 UINT 1 'Item1'\n")
        tf.write("  APPEND_ITEM item2 8 UINT 'Item2'\n")
        tf.write("TELEMETRY TEST SUB1 BIG_ENDIAN 'Subpacket'\n")
        tf.write("  SUBPACKET\n")
        tf.write("  APPEND_ID_ITEM item1 8 UINT 10 'Item1'\n")
        tf.write("  APPEND_ITEM item2 8 UINT 'Item2'\n")
        tf.write("TELEMETRY TEST VIRTUAL_PKT BIG_ENDIAN 'Virtual Packet'\n")
        tf.write("  VIRTUAL\n")
        tf.write("  APPEND_ID_ITEM item1 8 UINT 99 'Item1'\n")
        tf.write("  APPEND_ITEM item2 8 UINT 'Item2'\n")
        tf.seek(0)

        pc = PacketConfig()
        pc.process_file(tf.name, "TEST")
        tf.close()

        from openc3.system.system import System
        from openc3.packets.telemetry import Telemetry

        System.telemetry = Telemetry(pc, System)
        System.telemetry.config = pc

        # Create interface with fixed protocol
        from openc3.interfaces.stream_interface import StreamInterface
        from openc3.interfaces.protocols.fixed_protocol import FixedProtocol

        interface = StreamInterface()
        interface.add_protocol(FixedProtocol, [2, 0, None, True], "READ_WRITE")
        interface.target_names = ["TEST"]
        interface.tlm_target_names = ["TEST"]

        # Test normal packet PKT1 (ID=1)
        class MockStream1:
            def __init__(self):
                self.data = b"\x01\x05"
                self.index = 0

            def read(self, count=None):
                return self.data

            def connected(self):
                return True

        interface.stream = MockStream1()
        packet = interface.read()
        self.assertIsNotNone(packet)
        self.assertEqual(packet.buffer, b"\x01\x05")
        self.assertEqual(packet.target_name, "TEST")
        self.assertEqual(packet.packet_name, "PKT1")

        # Test subpacket SUB1 (ID=10) - should not be identified
        class MockStream2:
            def __init__(self):
                self.data = b"\x0A\x06"
                self.index = 0

            def read(self, count=None):
                return self.data

            def connected(self):
                return True

        interface.stream = MockStream2()
        packet = interface.read()
        self.assertIsNone(packet.target_name)
        self.assertIsNone(packet.packet_name)

        # Test virtual packet (ID=99) - should not be identified
        class MockStream3:
            def __init__(self):
                self.data = b"\x63\x07"
                self.index = 0

            def read(self, count=None):
                return self.data

            def connected(self):
                return True

        interface.stream = MockStream3()
        packet = interface.read()
        self.assertIsNone(packet.target_name)
        self.assertIsNone(packet.packet_name)
