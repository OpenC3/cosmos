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
import threading
import time
import unittest
from unittest.mock import *

from openc3.interfaces.protocols.template_protocol import TemplateProtocol
from openc3.interfaces.stream_interface import StreamInterface
from openc3.packets.packet import Packet
from openc3.packets.packet_config import PacketConfig
from openc3.packets.telemetry import Telemetry
from openc3.streams.stream import Stream
from test.test_helper import *


class FakeClock:
    """Virtual clock standing in for the time module of TemplateProtocol.

    The protocol measures its delays with time.time() and waits with
    time.sleep(), both looked up on the module, so patching the module's time
    with this makes sleeps advance the clock instantly by exactly the duration
    the protocol asked to wait. That is how the tests check a delay is not
    longer than configured, which cannot be asserted against the wall clock
    without failing on a loaded machine. It proves nothing about the wait
    really happening, so the tests using it are paired with a wall clock test
    that asserts the protocol blocks for at least the configured time.

    Code that waits without sleeping never advances this clock and would spin
    forever, so time() raises once it is clear that is happening.
    """

    MAX_READS = 100000

    def __init__(self):
        self.now = 0.0
        self.reads = 0

    def time(self):
        self.reads += 1
        if self.reads > self.MAX_READS:
            raise RuntimeError("clock never advanced: does the code under test still wait with time.sleep()?")
        return self.now

    def sleep(self, seconds):
        self.reads = 0
        self.now += seconds


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
        mock_redis(self)
        TestTemplateProtocol.read_buffer = None
        TestTemplateProtocol.write_buffer = None
        self.interface = TestTemplateProtocol.MyInterface()

        # The stub streams below return data forever so cap the read queue
        # rather than letting the read thread buffer the full default budget
        self.interface.set_option("READ_QUEUE_MAX_SIZE", ["65536"])

    def tearDown(self):
        # Stop the StreamInterface read thread started by reading
        self.interface.stop_read_queue_thread()

    def _command_packet(self, cmd_template, rsp_template=None, rsp_packet=None, **items):
        """Build a TGT CMD packet with the given 16 bit UINT items and templates.

        Items are appended in the order given, each defaulting to its value,
        followed by the CMD_TEMPLATE, RSP_TEMPLATE and RSP_PACKET strings the
        TemplateProtocol reads. A template left as None is not appended.
        """
        packet = Packet("TGT", "CMD")
        for name, default in items.items():
            packet.append_item(name, 16, "UINT")
            packet.get_item(name).default = default
        templates = {"CMD_TEMPLATE": cmd_template, "RSP_TEMPLATE": rsp_template, "RSP_PACKET": rsp_packet}
        for name, default in templates.items():
            if default is None:
                continue
            packet.append_item(name, 1024, "STRING")
            packet.get_item(name).default = default
        packet.restore_defaults()
        return packet

    def test_initializes_attributes(self):
        self.interface.add_protocol(TemplateProtocol, ["0xABCD", "0xABCD"], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].data, b"")

    def test_supports_an_initial_read_delay(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xABCD", "0xABCD", 0, 0.02], "READ_WRITE")
        start = time.time()
        self.interface.connect()
        self.assertGreaterEqual(self.interface.read_protocols[0].connect_complete_time, (start + 0.02))
        self.assertLessEqual(self.interface.read_protocols[0].connect_complete_time, (start + 0.05))

    def test_unblocks_writes_waiting_for_responses(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xABCD", "0xABCD"], "READ_WRITE")
        packet = Packet("TGT", "CMD")
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT'"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        # write blocks waiting for the response so spawn a thread
        thread = threading.Thread(target=self.interface.write, args=[packet])
        thread.start()
        time.sleep(0.001)
        self.interface.disconnect()
        thread.join()

    def test_ignores_all_data_during_the_connect_period(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xABCD", "0xABCD", 0, 0.1], "READ_WRITE")
        start = time.time()
        TestTemplateProtocol.read_buffer = b"\x31\x30\xab\xcd"
        self.interface.connect()
        protocol = self.interface.read_protocols[0]
        # Data arriving during the connect period is dropped, not buffered
        self.assertEqual(protocol.read_data(b"\x39\x39\xab\xcd"), ("STOP", None))
        self.assertEqual(protocol.data, b"")
        # The read keeps dropping data until the connect period has really elapsed
        data = self.interface.read()
        self.assertGreaterEqual(time.time() - start, 0.1)
        self.assertEqual(data.buffer, b"\x31\x30")

    def test_waits_before_writing_during_the_initial_delay_period(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xABCD", "0xABCD", 0, 0.02], "READ_WRITE")
        packet = self._command_packet("SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)", VOLTAGE=1, CHANNEL=2)
        self.interface.connect()
        write = time.time()
        self.interface.write(packet)
        # The write really blocks until the initial delay has elapsed. Only the
        # lower bound can be checked here because a loaded machine can take
        # arbitrarily longer; test_waits_no_longer_than_the_initial_delay_before_writing
        # covers the protocol not waiting longer than it was configured to
        self.assertGreaterEqual(time.time() - write, 0.02)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 1, (self.2)\xab\xcd")

    def test_works_without_a_response(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xABCD", "0xABCD"], "READ_WRITE")
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 1
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 2
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.restore_defaults()
        self.interface.write(packet)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 1, (self.2)\xab\xcd")

    def test_logs_an_error_if_it_doesnt_receive_a_response(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xA", "0xA", 0, None, 1, True, 0, None, False, 0.03],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = self._command_packet("GO", "<VOLTAGE>", "DATA")
        self.interface.connect()
        start = time.time()
        for stdout in capture_io():
            self.interface.write(packet)
            self.assertIn(
                "Timeout waiting for response",
                stdout.getvalue(),
            )
        # The write really blocks for the response timeout before giving up
        self.assertGreaterEqual(time.time() - start, 0.03)

    def test_disconnects_if_it_doesnt_receive_a_response(self):
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xA", "0xA", 0, None, 1, True, 0, None, False, 0.04, 0.02, True],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = self._command_packet("GO", "<VOLTAGE>", "DATA")
        self.interface.connect()
        start = time.time()
        with self.assertRaisesRegex(RuntimeError, "Timeout waiting for response"):
            self.interface.write(packet)
        # The write really blocks for the response timeout before raising
        self.assertGreaterEqual(time.time() - start, 0.04)

    def test_waits_no_longer_than_the_initial_delay_before_writing(self):
        # The wall clock can only show that the write waited at least the
        # initial delay. Run the same write against a virtual clock, which the
        # protocol advances by exactly the durations it sleeps, to show it does
        # not wait any longer than it was configured to
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xABCD", "0xABCD", 0, 0.02], "READ_WRITE")
        packet = self._command_packet("SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)", VOLTAGE=1, CHANNEL=2)
        clock = FakeClock()
        with patch("openc3.interfaces.protocols.template_protocol.time", clock):
            self.interface.connect()
            write = clock.now
            self.interface.write(packet)
            elapsed = clock.now - write
        self.assertAlmostEqual(elapsed, 0.02, places=6)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 1, (self.2)\xab\xcd")

    def test_times_out_within_one_polling_period_of_the_response_timeout(self):
        # Same idea for the response timeout: the virtual clock shows the
        # timeout fires on the first poll at or after it expires rather than
        # some multiple of it
        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xA", "0xA", 0, None, 1, True, 0, None, False, 0.04, 0.02, True],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = self._command_packet("GO", "<VOLTAGE>", "DATA")
        clock = FakeClock()
        with patch("openc3.interfaces.protocols.template_protocol.time", clock):
            self.interface.connect()
            start = clock.now
            with self.assertRaisesRegex(RuntimeError, "Timeout waiting for response"):
                self.interface.write(packet)
            elapsed = clock.now - start
        self.assertGreaterEqual(elapsed, 0.04)
        self.assertLess(elapsed, 0.04 + 0.02)  # response_polling_period

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
        mock_system.telemetry = Telemetry(pc, mock_system)

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
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        TestTemplateProtocol.read_buffer = b"\x31\x30\xab\xcd"  # ASCII 31, 30 is '10'
        self.interface.connect()
        self.read_result = None

        def do_read(self):
            time.sleep(0.001)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        self.interface.write(packet)
        time.sleep(0.003)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.1)\xab\xcd")
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
        mock_system.telemetry = Telemetry(pc, mock_system)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xABCD", 0, None, 1, True, 0, None, False, None, None],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("CMD_ID", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 1)  # ID == 1
        packet.get_item("CMD_ID").default = 1
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 1
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        TestTemplateProtocol.read_buffer = b"\x31\x30\xab\xcd"  # ASCII 31, 30 is '10'
        self.interface.connect()
        self.read_result = None

        def do_read(self):
            time.sleep(0.001)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        self.interface.write(packet)
        time.sleep(0.003)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.1)\xab\xcd")
        self.assertEqual(self.read_result.read("PKT_ID"), (1))  # Result ID set to the defined value)
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
        mock_system.telemetry = Telemetry(pc, mock_system)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xABCD", 0, None, 1, True, 0, None, False, None, None],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("APID", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 1)  # ID == 1
        packet.get_item("APID").default = 1
        packet.append_item("PKTID", 16, "UINT", None, "BIG_ENDIAN", "ERROR", None, None, None, 2)  # ID == 2
        packet.get_item("PKTID").default = 2
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 1
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        # Explicitly write in values to the ID items different than the defaults
        packet.write("APID", 10)
        packet.write("PKTID", 20)
        TestTemplateProtocol.read_buffer = b"\x31\x30\xab\xcd"  # ASCII 31, 30 is '10'
        self.interface.connect()
        self.read_result = None

        def do_read(self):
            time.sleep(0.001)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()

        self.interface.write(packet)
        time.sleep(0.003)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.1)\xab\xcd")
        self.assertEqual(self.read_result.read("APID"), (10))  # ID item set to the defined value)
        self.assertEqual(self.read_result.read("PKTID"), (20))  # ID item set to the defined value)

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_handles_templates_with_more_values_than_the_response(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock_system)

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
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>;<CURRENT>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        TestTemplateProtocol.read_buffer = b"\x31\x30\xab\xcd"  # ASCII 31, 30 is '10'
        self.interface.connect()

        def do_read(self):
            time.sleep(0.001)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        for stdout in capture_io():
            self.interface.write(packet)
            time.sleep(0.003)
            self.assertIn(
                "Unexpected response:",
                stdout.getvalue(),
            )

        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 12, (self.2)\xab\xcd")

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_handles_responses_with_more_values_than_the_template(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock_system)

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
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        TestTemplateProtocol.read_buffer = b"\x31\x30\x3b\x31\x31\xab\xcd"  # ASCII is '10;11'
        self.interface.connect()

        def do_read(self):
            time.sleep(0.001)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()

        for stdout in capture_io():
            self.interface.write(packet)
            time.sleep(0.003)
            self.assertIn(
                "Could not write value 10;11",
                stdout.getvalue(),
            )

        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 12, (self.2)\xab\xcd")

    @patch("openc3.interfaces.protocols.template_protocol.System")
    def test_ignores_response_lines(self, mock_system):
        tf = tempfile.NamedTemporaryFile(mode="w")
        tf.write("TELEMETRY TGT READ_VOLTAGE BIG_ENDIAN\n")
        tf.write("  APPEND_ITEM VOLTAGE 16 UINT\n")
        tf.seek(0)
        pc = PacketConfig()
        pc.process_file(tf.name, "SYSTEM")
        tf.close()
        mock_system.telemetry = Telemetry(pc, mock_system)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xAD", "0xA", 1], "READ_WRITE")
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("VOLTAGE", 16, "UINT")
        packet.get_item("VOLTAGE").default = 11
        packet.append_item("CHANNEL", 16, "UINT")
        packet.get_item("CHANNEL").default = 20
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "SOUR'VOLT' <VOLTAGE>, (self.<CHANNEL>)"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<VOLTAGE>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "READ_VOLTAGE"
        packet.restore_defaults()
        TestTemplateProtocol.read_buffer = b"\x31\x30\x0a\x31\x32\x0a"  # ASCII: 30:'0', 31:'1', etc
        self.interface.connect()
        self.read_result = None

        def do_read(self):
            time.sleep(0.001)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()
        self.interface.write(packet)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"SOUR'VOLT' 11, (self.20)\xad")
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
        mock_system.telemetry = Telemetry(pc, mock_system)

        self.interface.stream = TestTemplateProtocol.TemplateStream()
        self.interface.add_protocol(TemplateProtocol, ["0xAD", "0xA", 0, None, 2], "READ_WRITE")
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "CMD")
        packet.append_item("CMD_TEMPLATE", 1024, "STRING")
        packet.get_item("CMD_TEMPLATE").default = "GO"
        packet.append_item("RSP_TEMPLATE", 1024, "STRING")
        packet.get_item("RSP_TEMPLATE").default = "<STRING>"
        packet.append_item("RSP_PACKET", 1024, "STRING")
        packet.get_item("RSP_PACKET").default = "DATA"
        packet.restore_defaults()
        TestTemplateProtocol.read_buffer = b"\x4f\x70\x65\x0a\x6e\x43\x33\x0a"  # ASCII
        self.interface.connect()
        self.read_result = None

        def do_read(self):
            time.sleep(0.001)
            self.read_result = self.interface.read()

        thread = threading.Thread(target=do_read, args=[self])
        thread.start()

        self.interface.write(packet)
        self.assertEqual(TestTemplateProtocol.write_buffer, b"GO\xad")
        self.assertEqual(self.read_result.read("STRING"), "OpenC3")

    def test_write_details_returns_correct_information(self):
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xDCBA", 2, None, 1, True, 0, None, False, 0.5, 0.1, False],
            "READ_WRITE",
        )
        protocol = self.interface.write_protocols[0]
        details = protocol.write_details()

        # Check that it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check base protocol fields from super()
        self.assertIn("name", details)
        self.assertEqual(details["name"], "TemplateProtocol")
        self.assertIn("write_data_input_time", details)
        self.assertIn("write_data_input", details)
        self.assertIn("write_data_output_time", details)
        self.assertIn("write_data_output", details)

        # Check template protocol specific fields
        self.assertIn("response_template", details)
        self.assertIn("response_packet", details)
        self.assertIn("response_target_name", details)
        self.assertIn("ignore_lines", details)
        self.assertEqual(details["ignore_lines"], 2)
        self.assertIn("response_lines", details)
        self.assertEqual(details["response_lines"], 1)
        self.assertIn("initial_read_delay", details)
        self.assertIn("response_timeout", details)
        self.assertEqual(details["response_timeout"], 0.5)
        self.assertIn("response_polling_period", details)
        self.assertEqual(details["response_polling_period"], 0.1)
        self.assertIn("connect_complete_time", details)
        self.assertIn("raise_exceptions", details)
        self.assertEqual(details["raise_exceptions"], False)

    def test_read_details_returns_correct_information(self):
        self.interface.add_protocol(
            TemplateProtocol,
            ["0xABCD", "0xDCBA", 2, None, 1, True, 0, None, False, 0.5, 0.1, False],
            "READ_WRITE",
        )
        protocol = self.interface.read_protocols[0]
        details = protocol.read_details()

        # Check that it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check base protocol fields from super()
        self.assertIn("name", details)
        self.assertEqual(details["name"], "TemplateProtocol")
        self.assertIn("read_data_input_time", details)
        self.assertIn("read_data_input", details)
        self.assertIn("read_data_output_time", details)
        self.assertIn("read_data_output", details)

        # Check template protocol specific fields (same as write_details for this protocol)
        self.assertIn("response_template", details)
        self.assertIn("response_packet", details)

    def test_accepts_hex_string_for_ignore_lines(self):
        self.interface.add_protocol(
            TemplateProtocol,
            [
                "0xABCD",  # write termination
                "0xABCD",  # read termination
                "0x2",  # ignore_lines as hex string (2 in decimal)
            ],
            "READ_WRITE",
        )
        self.assertEqual(self.interface.read_protocols[0].ignore_lines, 2)

    def test_accepts_hex_string_for_response_lines(self):
        self.interface.add_protocol(
            TemplateProtocol,
            [
                "0xABCD",  # write termination
                "0xABCD",  # read termination
                0,  # ignore_lines
                None,  # initial_read_delay
                "0x3",  # response_lines as hex string (3 in decimal)
            ],
            "READ_WRITE",
        )
        self.assertEqual(self.interface.read_protocols[0].response_lines, 3)
