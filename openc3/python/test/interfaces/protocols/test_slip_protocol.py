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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.slip_protocol import SlipProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream


class TestSlipProtocol(unittest.TestCase):
    index = 0
    buffer = None

    class SlipStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestSlipProtocol.buffer

        def write(self, data):
            TestSlipProtocol.buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        TestSlipProtocol.buffer = None
        self.interface = TestSlipProtocol.MyInterface()

    def test_complains_if_given_invalid_params(self):
        with self.assertRaisesRegex(ValueError, "invalid value 5.1234 for start_char"):
            self.interface.add_protocol(SlipProtocol, ["5.1234"], "READ_WRITE")
        with self.assertRaisesRegex(
            RuntimeError, "read_strip_characters must be True or False"
        ):
            self.interface.add_protocol(SlipProtocol, [None, None], "READ_WRITE")
        with self.assertRaisesRegex(
            RuntimeError, "read_enable_escaping must be True or False"
        ):
            self.interface.add_protocol(SlipProtocol, [None, True, None], "READ_WRITE")
        with self.assertRaisesRegex(
            RuntimeError, "write_enable_escaping must be True or False"
        ):
            self.interface.add_protocol(
                SlipProtocol, [None, True, True, None], "READ_WRITE"
            )
        with self.assertRaisesRegex(ValueError, "invalid literal for int"):
            self.interface.add_protocol(
                SlipProtocol, [None, True, True, True, "5.1234"], "READ_WRITE"
            )
        with self.assertRaisesRegex(ValueError, "invalid literal for int"):
            self.interface.add_protocol(
                SlipProtocol, [None, True, True, None, "0xC0", "5.1234"], "READ_WRITE"
            )
        with self.assertRaisesRegex(ValueError, "invalid literal for int"):
            self.interface.add_protocol(
                SlipProtocol,
                [None, True, True, None, "0xC0", "0xDB", "5.1234"],
                "READ_WRITE",
            )
        with self.assertRaisesRegex(ValueError, "invalid literal for int"):
            self.interface.add_protocol(
                SlipProtocol,
                [None, True, True, None, "0xC0", "0xDB", "0xDC", "5.1234"],
                "READ_WRITE",
            )

    def test_handles_proper_params(self):
        protocol = self.interface.add_protocol(
            SlipProtocol,
            ["0xC0", "False", "True", "False", "0xC0", "0xDB", "0xDC", "0xDD"],
            "READ_WRITE",
        )
        self.assertEqual(protocol.start_char, b"\xC0")
        self.assertEqual(protocol.read_strip_characters, False)
        self.assertEqual(protocol.read_enable_escaping, True)
        self.assertEqual(protocol.write_enable_escaping, False)
        self.assertEqual(protocol.end_char, b"\xC0")
        self.assertEqual(protocol.esc_char, b"\xDB")
        self.assertEqual(protocol.esc_end_char, b"\xDC")
        self.assertEqual(protocol.esc_esc_char, b"\xDD")
        self.assertEqual(protocol.replace_end, b"\xDB\xDC")
        self.assertEqual(protocol.replace_esc, b"\xDB\xDD")

    def test_handles_multiple_reads(self):
        class TerminatedSlipStream(TestSlipProtocol.SlipStream):
            def read(self):
                match TestSlipProtocol.index:
                    case 0:
                        TestSlipProtocol.index += 1
                        return b"\x01\x02"
                    case 1:
                        TestSlipProtocol.index += 1
                        return b"\xC0"

        TestSlipProtocol.index = 0
        self.interface.stream = TerminatedSlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")

    def test_handles_multiple_reads_and_packets(self):
        class MultiTerminatedSlipStream(TestSlipProtocol.SlipStream):
            def read(self):
                match TestSlipProtocol.index:
                    case 0:
                        TestSlipProtocol.index += 1
                        return b"\xC0"
                    case 1:
                        TestSlipProtocol.index += 1
                        return b"\x01\x02"
                    case 2:
                        TestSlipProtocol.index += 1
                        return b"\xC0"
                    case 3:
                        TestSlipProtocol.index += 1
                        return b"\xC0\x03\x04"
                    case 4:
                        TestSlipProtocol.index += 1
                        return b"\x01\x02"
                    case 5:
                        TestSlipProtocol.index += 1
                        return b"\xC0"

        TestSlipProtocol.index = 0
        self.interface.stream = MultiTerminatedSlipStream()
        self.interface.add_protocol(SlipProtocol, ["0xC0"], "READ_WRITE")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x03\x04\x01\x02")

    def test_handles_empty_packets(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        TestSlipProtocol.buffer = b"\xC0\x01\x02\xC0"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 0)
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")

    def test_handles_no_start_char_pattern(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        TestSlipProtocol.buffer = b"\x00\x01\x02\xC0\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x01\x02")

    def test_handles_a_start_char_inside_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, ["0xC0", False], "READ_WRITE")
        TestSlipProtocol.buffer = b"\xC0\x00\x01\x02\xC0\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\xC0\x00\x01\x02\xC0")

    def test_handles_bad_data_before_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, ["0xC0", False], "READ_WRITE")
        TestSlipProtocol.buffer = b"\x00\x01\x02\xC0\x44\x02\x03\xC0"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\xC0\x44\x02\x03\xC0")

    def test_handles_escape_sequences(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        TestSlipProtocol.buffer = (
            b"\x00\xDB\xDC\x44\xDB\xDD\x02\xDB\xDC\x03\xDB\xDD\xC0"
        )
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\xC0\x44\xDB\x02\xC0\x03\xDB")

    def test_leaves_escape_sequences(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [None, True, False], "READ_WRITE")
        TestSlipProtocol.buffer = (
            b"\x00\xDB\xDC\x44\xDB\xDD\x02\xDB\xDC\x03\xDB\xDD\xC0"
        )
        packet = self.interface.read()
        self.assertEqual(
            packet.buffer, b"\x00\xDB\xDC\x44\xDB\xDD\x02\xDB\xDC\x03\xDB\xDD"
        )

    def test_appends_end_char_to_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestSlipProtocol.buffer, b"\x00\x01\x02\x03\xC0")

    def test_appends_a_different_end_char_to_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(
            SlipProtocol, [None, True, True, True, "0xEE"], "READ_WRITE"
        )
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestSlipProtocol.buffer, b"\x00\x01\x02\x03\xEE")

    def test_appends_start_char_and_end_char_to_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, ["0xC0"], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestSlipProtocol.buffer, b"\xC0\x00\x01\x02\x03\xC0")

    def test_handles_writing_the_end_char_inside_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\xC0\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestSlipProtocol.buffer, b"\x00\xDB\xDC\x02\x03\xC0")

    def test_handles_writing_the_esc_char_inside_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\xDB\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestSlipProtocol.buffer, b"\x00\xDB\xDD\x02\x03\xC0")

    def test_handles_writing_the_end_char_and_the_esc_char_inside_the_packet(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(SlipProtocol, [], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\xC0\xDB\xDB\xC0\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(
            TestSlipProtocol.buffer, b"\x00\xDB\xDC\xDB\xDD\xDB\xDD\xDB\xDC\x02\x03\xC0"
        )

    def test_handles_not_writing_escape_sequences(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(
            SlipProtocol, [None, True, True, False], "READ_WRITE"
        )
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\xC0\xDB\xDB\xC0\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestSlipProtocol.buffer, b"\x00\xC0\xDB\xDB\xC0\x02\x03\xC0")

    def test_handles_different_escape_sequences(self):
        self.interface.stream = TestSlipProtocol.SlipStream()
        self.interface.add_protocol(
            SlipProtocol,
            [None, True, True, True, "0xE0", "0xE1", "0xE2", "0xE3"],
            "READ_WRITE",
        )
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\xE0\xE1\xE1\xE0\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(
            TestSlipProtocol.buffer, b"\x00\xE1\xE2\xE1\xE3\xE1\xE3\xE1\xE2\x02\x03\xE0"
        )
