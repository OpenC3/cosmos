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

import time
import tempfile
import threading
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.template_protocol import TemplateProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream
from openc3.packets.packet_config import PacketConfig
from openc3.packets.telemetry import Telemetry


class TestTemplateProtocol(unittest.TestCase):
    read_buffer = None
    write_buffer = None

    class TemplateStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestTemplateProtocol.read_buffer

        def write(self, data):
            TestTemplateProtocol.write_buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        TestTemplateProtocol.read_buffer = None
        TestTemplateProtocol.write_buffer = None
        self.interface = TestTemplateProtocol.MyInterface()

    def test_initializes_attributes(self):
        self.interface.add_protocol(
            TemplateProtocol, ["0xABCD", "0xABCD"], "READ_WRITE"
        )
        self.assertEqual(self.interface.read_protocols[0].data, b"")

    def test_supports_an_initial_read_delay(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol, ["0xABCD", "0xABCD", 0, 2], "READ_WRITE"
        )
        start = time.time()
        self.interface.connect()
        self.assertTrue(
            self.interface.read_protocols[0].connect_complete_time >= (start + 2.0)
        )

    # def test_unblocks_writes_waiting_for_responses(self):
    #     self.interface.stream = TestTemplateProtocol.TemplateStream()
    #     self.interface.add_protocol(
    #         TemplateProtocol, ["0xABCD", "0xABCD"], "READ_WRITE"
    #     )
    #     packet = Packet("TGT", "CMD")
    #     packet.append_item("CMD_TEMPLATE", 1024, "STRING")
    #     packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT'"
    #     packet.append_item("RSP_TEMPLATE", 1024, "STRING")
    #     packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
    #     packet.append_item("RSP_PACKET", 1024, "STRING")
    #     packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
    #     packet.restore_defaults()
    #     # write blocks waiting for the response so spawn a thread
    #     thread = threading.Thread(target=self.interface.write, args=[packet])
    #     thread.start()
    #     time.sleep(0.1)
    #     self.interface.disconnect()
    #     time.sleep(0.1)
    #     thread.join()

    def test_ignores_all_data_during_the_connect_period(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol, ["0xABCD", "0xABCD", 0, 1.5], "READ_WRITE"
        )
        start = time.time()
        self.interface.connect()
        TestTemplateProtocol.read_buffer = b"\x31\x30\xAB\xCD"
        data = self.interface.read()
        self.assertAlmostEqual(time.time() - start, 1.5, places=1)
        self.assertEqual(data.buffer, b"\x31\x30")

    def test_waits_before_writing_during_the_initial_delay_period(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol, ["0xABCD", "0xABCD", 0, 1.5], "READ_WRITE"
        )
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 1
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 2
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.restore_defaults()
        self.interface.connect()
        write = time.time()
        self.interface.write(packet)
        self.assertAlmostEqual(time.time() - write, 1.5, places=1)

    def test_works_without_a_response(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol, ["0xABCD", "0xABCD"], "READ_WRITE"
        )
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 1
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 2
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.restore_defaults()
        self.interface.write(packet)
        self.assertEqual(
            TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 1, (self.2)\xAB\xCD"
        )

    def test_logs_an_error_if_it_doesnt_receive_a_response(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xA", "0xA", 0, None, 1, True, 0, None, False, 1.5],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "GO"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "DATA"
        packet.restore_defaults()
        self.interface.connect()
        start = time.time()
        for stdout in capture_io():
            self.interface.write(packet)
            self.assertIn(
                "Timeout waiting for response",
                stdout.getvalue(),
            )
        self.assertAlmostEqual(time.time() - start, 1.5, places=1)

    def test_disconnects_if_it_doesnt_receive_a_response(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xA", "0xA", 0, None, 1, True, 0, None, False, 1.5, 0.02, True],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "GO"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "DATA"
        packet.restore_defaults()
        self.interface.connect()
        start = time.time()
        with self.assertRaisesRegex(RuntimeError, "Timeout waiting for response"):
            self.interface.write(packet)
        self.assertAlmostEqual(time.time() - start, 1.5, places=1)

    def test_doesnt_expect_responses_for_empty_response_fields(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xA", "0xA", 0, None, 1, True, 0, None, False, None],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "GO"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = ""
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = ""
        packet.restore_defaults()
        self.interface.connect()
        self.interface.write(packet)

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_processes_responses_with_no_id_fields(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w+t")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xABCD", 0, None, 1, True, 0, None, False, None, None],
            "READ_WRITE",
        )
        # Add extra target names to the interface to ensure we grab the correct one
        self.interface.target_names = ["BLAH", "TGT", "OTHER"]
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 1
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        self.interface.connect()
        self.read_result = None
        TestTemplateProtocol.read_buffer = b"\x31\x30\xAB\xCD"  # ASCII 31, 30 is '10'

        def do_read(self):
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        self.interface.write(packet)
        time.sleep(0.55)
        self.assertEqual(
            TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.1)\xAB\xCD"
        )
        self.assertEqual(self.read_result.read("VOLTAGE"), (10))

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_sets_the_response_id_to_the_defined_id_value(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ID_ITEM PKT_ID 16 UINT 1\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xABCD", 0, None, 1, True, 0, None, False, None, None],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item(
            "CMD_ID", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 1
        )  # ID == 1
        packet.get_item("CMD_ID").default = 1
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 1
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        self.interface.connect()
        self.read_result = None
        TestTemplateProtocol.read_buffer = b"\x31\x30\xAB\xCD"  # ASCII 31, 30 is '10'

        def do_read(self):
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        self.interface.write(packet)
        time.sleep(0.55)
        self.assertEqual(
            TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.1)\xAB\xCD"
        )
        self.assertEqual(
            self.read_result.read("PKT_ID"), (1)
        )  # Result ID set to the defined value)
        self.assertEqual(self.read_result.read("VOLTAGE"), (10))

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_handles_multiple_response_ids(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ID_ITEM APID 16 UINT 10\n")
        tf.write("  APPEND_ID_ITEM PKTID 16 UINT 20\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xABCD", 0, None, 1, True, 0, None, False, None, None],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item(
            "APID", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 1
        )  # ID == 1
        packet.get_item("APID").default = 1
        packet.append_item(
            "PKTID", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 2
        )  # ID == 2
        packet.get_item("PKTID").default = 2
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 1
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        # Explicitly write in values to the ID items different than the defaults
        packet.write("APID", 10)
        packet.write("PKTID", 20)
        self.interface.connect()
        self.read_result = None
        TestTemplateProtocol.read_buffer = b"\x31\x30\xAB\xCD"  # ASCII 31, 30 is '10'

        def do_read(self):
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()

        self.interface.write(packet)
        time.sleep(0.55)
        self.assertEqual(
            TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.1)\xAB\xCD"
        )
        self.assertEqual(
            self.read_result.read("APID"), (10)
        )  # ID item set to the defined value)
        self.assertEqual(
            self.read_result.read("PKTID"), (20)
        )  # ID item set to the defined value)

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_handles_templates_with_more_values_than_the_response(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xABCD", 0, None, 1, True, 0, None, False, None],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 12
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 2
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>;<CURRENT>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        self.interface.connect()
        TestTemplateProtocol.read_buffer = b"\x31\x30\xAB\xCD"  # ASCII 31, 30 is '10'

        def do_read(self):
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        for stdout in capture_io():
            self.interface.write(packet)
            time.sleep(0.55)
            self.assertIn(
                "Unexpected response:",
                stdout.getvalue(),
            )

        self.assertEqual(
            TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 12, (self.2)\xAB\xCD"
        )

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_handles_responses_with_more_values_than_the_template(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xABCD", 0, None, 1, True, 0, None, False, None],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 12
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 2
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        self.interface.connect()
        TestTemplateProtocol.read_buffer = (
            b"\x31\x30\x3B\x31\x31\xAB\xCD"  # ASCII is '10;11'
        )

        def do_read(self):
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()

        for stdout in capture_io():
            self.interface.write(packet)
            time.sleep(0.55)
            self.assertIn(
                "Could not write value 10;11",
                stdout.getvalue(),
            )

        self.assertEqual(
            TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 12, (self.2)\xAB\xCD"
        )

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_ignores_response_lines(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xAD", "0xA", 1], "READ_WRITE")
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 20
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item(
            "CMD_TEMPLATE"
        ).default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        self.interface.connect()
        self.read_result = None
        TestTemplateProtocol.read_buffer = (
            b"\x31\x30\x0A\x31\x32\x0A"  # ASCII: 30:'0', 31:'1', etc
        )

        def do_read(self):
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        self.interface.write(packet)
        self.assertEqual(
            TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.20)\xAD"
        )
        self.assertEqual(self.read_result.read("VOLTAGE"), 12)

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_allows_multiple_response_lines(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT DATA BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM STRING 512 STRINg\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol, ["0xAD", "0xA", 0, None, 2], "READ_WRITE"
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "GO"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<STRING>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "DATA"
        packet.restore_defaults()
        self.interface.connect()
        self.read_result = None
        TestTemplateProtocol.read_buffer = b"\x4F\x70\x65\x0A\x6E\x43\x33\x0A"  # ASCII

        def do_read(self):
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()

        self.interface.write(packet)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"GO\xAD")
        self.assertEqual(self.read_result.read("STRING"), "OpenC3")
