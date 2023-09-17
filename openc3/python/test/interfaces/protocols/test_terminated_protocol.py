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
from openc3.interfaces.protocols.terminated_protocol import TerminatedProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream


class TestTerminatedProtocol(unittest.TestCase):
    buffer = b""

    class TerminatedStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestTerminatedProtocol.buffer

        def write(self, data):
            TestTerminatedProtocol.buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        TestTerminatedProtocol.buffer = b""
        self.interface = TestTerminatedProtocol.MyInterface()

    def test_initializes_attributes(self):
        self.interface.add_protocol(
            TerminatedProtocol, ["0xABCD", "0xABCD"], "READ_WRITE"
        )
        self.assertEqual(self.interface.read_protocols[0].data, b"")

    def test_handles_multiple_reads(self):
        class MultiTerminatedStream(TestTerminatedProtocol.TerminatedStream):
            index = 0

            def read(self):
                match MultiTerminatedStream.index:
                    case 0:
                        MultiTerminatedStream.index += 1
                        return b"\x01\x02"
                    case 1:
                        MultiTerminatedStream.index += 1
                        return b"\xAB"
                    case 2:
                        MultiTerminatedStream.index += 1
                        return b"\xCD"

        self.interface.stream = MultiTerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", True], "READ_WRITE"
        )
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")

    def test_strip_handles_empty_packets(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", True], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\xAB\xCD\x01\x02\xAB\xCD"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 0)
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")

    def test_strip_handles_no_sync_pattern(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", True], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\x00\x01\x02\xAB\xCD\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x01\x02")

    def test_strip_handles_a_sync_pattern_inside_the_packet(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", True, 0, "DEAD"], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\xDE\xAD\x00\x01\x02")

    def test_strip_handles_a_sync_pattern_outside_the_packet(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", True, 2, "DEAD"], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x01\x02")

    def test_keep_handles_empty_packets(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", False], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\xAB\xCD\x01\x02\xAB\xCD"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\xAB\xCD")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\xAB\xCD")

    def test_keep_handles_no_sync_pattern(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", False], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\x00\x01\x02\xAB\xCD\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x01\x02\xAB\xCD")

    def test_keep_handles_a_sync_pattern_inside_the_packet(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", False, 0, "DEAD"], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\xDE\xAD\x00\x01\x02\xAB\xCD")

    def test_keep_handles_a_sync_pattern_outside_the_packet(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["", "0xABCD", False, 2, "DEAD"], "READ_WRITE"
        )
        TestTerminatedProtocol.buffer = b"\xDE\xAD\x00\x01\x02\xAB\xCD\x44\x02\x03"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x01\x02\xAB\xCD")

    def test_appends_termination_characters_to_the_packet(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(TerminatedProtocol, ["0xCDEF", ""], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestTerminatedProtocol.buffer, b"\x00\x01\x02\x03\xCD\xEF")

    def test_complains_if_the_packet_buffer_contains_the_termination_characters(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(TerminatedProtocol, ["0xCDEF", ""], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\xCD\xEF\x03"
        with self.assertRaisesRegex(
            RuntimeError, "Packet contains termination characters!"
        ):
            self.interface.write(pkt)

    def test_handles_writing_the_sync_field_inside_the_packet(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["0xCDEF", "", True, 0, "DEAD", True], "READ_WRITE"
        )
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(TestTerminatedProtocol.buffer, b"\xDE\xAD\x02\x03\xCD\xEF")

    def test_handles_writing_the_sync_field_outside_the_packet(self):
        self.interface.stream = TestTerminatedProtocol.TerminatedStream()
        self.interface.add_protocol(
            TerminatedProtocol, ["0xCDEF", "", True, 2, "DEAD", True], "READ_WRITE"
        )
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        self.interface.write(pkt)
        self.assertEqual(
            TestTerminatedProtocol.buffer, b"\xDE\xAD\x00\x01\x02\x03\xCD\xEF"
        )
