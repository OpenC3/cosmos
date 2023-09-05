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
from openc3.interfaces.protocols.cobs_protocol import CobsProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream


class TestCobsProtocol(unittest.TestCase):
    buffer = b""

    class CobsStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestCobsProtocol.buffer

        def write(self, data):
            TestCobsProtocol.buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        TestCobsProtocol.buffer = b""
        self.interface = TestCobsProtocol.MyInterface()

    # Test vectors from= https=//en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing
    def build_example_data(self):
        self.examples = [
            [b"\x00", b"\x01\x01\x00"],
            [b"\x00\x00", b"\x01\x01\x01\x00"],
            [b"\x00\x11\x00", b"\x01\x02\x11\x01\x00"],
            [b"\x11\x22\x00\x33", b"\x03\x11\x22\x02\x33\x00"],
            [b"\x11\x22\x33\x44", b"\x05\x11\x22\x33\x44\x00"],
            [b"\x11\x00\x00\x00", b"\x02\x11\x01\x01\x01\x00"],
        ]
        data = b""
        for char in range(1, 255):
            data += char.to_bytes(1, byteorder="big")
        result = b"\xFF" + data + b"\x00"
        self.examples.append([data, result])
        data = b""
        for char in range(0, 255):
            data += char.to_bytes(1, byteorder="big")
        result = b"\x01\xFF" + data[1:] + b"\x00"
        self.examples.append([data, result])
        data = b""
        for char in range(1, 256):
            data += char.to_bytes(1, byteorder="big")
        result = b"\xFF" + data[0:-1] + b"\x02\xFF\x00"
        self.examples.append([data, result])
        data = b""
        for char in range(2, 256):
            data += char.to_bytes(1, byteorder="big")
        data += b"\x00"
        result = b"\xFF" + data[0:-1] + b"\x01\x01\x00"
        self.examples.append([data, result])
        data = b""
        for char in range(3, 256):
            data += char.to_bytes(1, byteorder="big")
        data += b"\x00\x01"
        result = b"\xFE" + data[0:-2] + b"\x02\x01\x00"
        self.examples.append([data, result])

    def test_handles_multiple_reads(self):
        class TerminatedCobsStream(TestCobsProtocol.CobsStream):
            index = 0

            def read(self):
                match TerminatedCobsStream.index:
                    case 0:
                        TerminatedCobsStream.index += 1
                        return b"\x03\x01\x02"
                    case 1:
                        TerminatedCobsStream.index += 1
                        return b"\x00"

        self.interface.stream = TerminatedCobsStream()
        self.interface.add_protocol(CobsProtocol, [], "READ_WRITE")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")

    def test_handles_multiple_reads_and_packets(self):
        class MultiTerminatedCobsStream(TestCobsProtocol.CobsStream):
            index = 0

            def read(self):
                match MultiTerminatedCobsStream.index:
                    case 0:
                        MultiTerminatedCobsStream.index += 1
                        return b"\x03"
                    case 1:
                        MultiTerminatedCobsStream.index += 1
                        return b"\x01\x02"
                    case 2:
                        MultiTerminatedCobsStream.index += 1
                        return b"\x00"
                    case 3:
                        MultiTerminatedCobsStream.index += 1
                        return b"\x05\x03\x04"
                    case 4:
                        MultiTerminatedCobsStream.index += 1
                        return b"\x01\x02"
                    case 5:
                        MultiTerminatedCobsStream.index += 1
                        return b"\x00"

        self.interface.stream = MultiTerminatedCobsStream()
        self.interface.add_protocol(CobsProtocol, [], "READ_WRITE")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x03\x04\x01\x02")

    def test_handles_empty_packets(self):
        self.interface.stream = TestCobsProtocol.CobsStream()
        self.interface.add_protocol(CobsProtocol, [], "READ_WRITE")
        TestCobsProtocol.buffer = b"\x01\x00\x03\x01\x02\x00"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 0)
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02")

    def test_read_handles_examples(self):
        self.build_example_data()
        self.interface.stream = TestCobsProtocol.CobsStream()
        self.interface.add_protocol(CobsProtocol, [], "READ_WRITE")
        for decoded, encoded in self.examples:
            TestCobsProtocol.buffer = encoded
            packet = self.interface.read()
            self.assertEqual(packet.buffer, decoded)

    def test_write_handles_examples(self):
        self.build_example_data()
        self.interface.stream = TestCobsProtocol.CobsStream()
        self.interface.add_protocol(CobsProtocol, [], "READ_WRITE")
        pkt = Packet("tgt", "pkt")
        for decoded, encoded in self.examples:
            pkt.buffer = decoded
            self.interface.write(pkt)
            self.assertEqual(TestCobsProtocol.buffer, encoded)
