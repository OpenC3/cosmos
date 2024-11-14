# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
import unittest
import threading
import tempfile
from unittest.mock import *
from test.test_helper import *
from openc3.packets.packet import Packet
from openc3.packets.packet_config import PacketConfig
from openc3.packets.telemetry import Telemetry
from openc3.accessors.template_accessor import TemplateAccessor
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.cmd_response_protocol import CmdResponseProtocol
from openc3.streams.stream import Stream


class TestCmdResponseProtocol(unittest.TestCase):
    write_buffer = ""
    read_buffer = ""

    class CmdResponseStream(Stream):

        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read_nonblock(self):
            return []

        def write(self, buffer):
            TestCmdResponseProtocol.write_buffer = buffer

        def read(self):
            return TestCmdResponseProtocol.read_buffer

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        self.interface = self.MyInterface()
        TestCmdResponseProtocol.write_buffer = ""
        TestCmdResponseProtocol.read_buffer = ""
        self.read_cnt = 0
        self.read_result = None

    def test_unblocks_writes_waiting_for_responses(self):
        self.interface.stream = self.CmdResponseStream()
        self.interface.add_protocol(CmdResponseProtocol, [], "READ_WRITE")
        packet = Packet("TGT", "CMD")
        packet.template = b"SOUR:VOLT"
        packet.response = ["TGT", "READ_VOLTAGE"]
        packet.restore_defaults()

        # write blocks waiting for the response so spawn a thread
        def my_write():
            self.interface.write(packet)

        thread = threading.Thread(target=my_write)
        thread.start()

        time.sleep(0.1)
        self.interface.disconnect()
        time.sleep(0.1)
        thread.join()

    def test_works_without_a_response(self):
        self.interface.stream = self.CmdResponseStream()
        self.interface.add_protocol(CmdResponseProtocol, [], "READ_WRITE")
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 1
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 2
        packet.template = b"SOUR:VOLT <VOLTAGE>, (@<CHANNEL>)"
        packet.accessor = TemplateAccessor(packet)
        packet.restore_defaults()
        self.interface.write(packet)
        self.assertEqual(TestCmdResponseProtocol.write_buffer, b"SOUR:VOLT 1, (@2)")

    def test_logs_an_error_if_it_doesnt_receive_a_response(self):
        self.interface.stream = self.CmdResponseStream()
        self.interface.add_protocol(CmdResponseProtocol, [1.5, 0.02, True], "READ_WRITE")
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.template = b"GO"
        packet.response = ["TGT", "DATA"]
        packet.restore_defaults()
        self.interface.connect()
        start = time.time()
        with self.assertRaisesRegex(RuntimeError, "Timeout waiting for response"):
            self.interface.write(packet)
        self.assertAlmostEqual(time.time() - start, 1.5, places=1)

    def test_disconnects_if_it_doesnt_receive_a_response(self):
        self.interface.stream = self.CmdResponseStream()
        self.interface.add_protocol(CmdResponseProtocol, [1.5, 0.02, True], "READ_WRITE")
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.template = b"GO"
        packet.response = ["TGT", "DATA"]
        packet.restore_defaults()
        self.interface.connect
        start = time.time()
        with self.assertRaisesRegex(RuntimeError, "Timeout waiting for response"):
            self.interface.write(packet)
        self.assertAlmostEqual(time.time() - start, 1.5, places=1)

    def test_doesnt_expect_responses_for_empty_response_fields(self):
        self.interface.stream = self.CmdResponseStream()
        self.interface.add_protocol(CmdResponseProtocol, [], "READ_WRITE")
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.template = b"GO"
        packet.restore_defaults()
        self.interface.connect
        self.interface.write(packet)

    @patch("openc3.interfaces.protocols.cmd_response_protocol.System")
    def test_processes_responses_with_no_id_fields(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  ACCESSOR TemplateAccessor\n")
        tf.write('  TEMPLATE "<VOLTAGE>"\n')
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()

        mock_system.telemetry = Telemetry(pc, mock_system)
        self.interface.stream = self.CmdResponseStream()
        self.interface.add_protocol(CmdResponseProtocol, [1.5, 0.02, True], "READ_WRITE")
        # Add extra target names to the interface to ensure we grab the correct one
        self.interface.target_names = ["BLAH", "TGT", "OTHER"]
        packet = Packet("TGT", "CMD")
        packet.accessor = TemplateAccessor(packet)
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 1
        packet.template = b"SOUR:VOLT <VOLTAGE>, (@<CHANNEL>)"
        packet.response = ["TGT", "READ_VOLTAGE"]
        packet.restore_defaults()
        self.interface.connect()
        self.read_result = None
        TestCmdResponseProtocol.read_buffer = b"\x31\x30"  # ASCII 31, 30 is '10'

        # write blocks waiting for the response so spawn a thread
        def my_read():
            time.sleep(0.5)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=my_read)
        thread.start()

        self.interface.write(packet)
        time.sleep(0.55)
        self.assertEqual(TestCmdResponseProtocol.write_buffer, b"SOUR:VOLT 11, (@1)")
        self.assertEqual(self.read_result.read("VOLTAGE"), (10))
