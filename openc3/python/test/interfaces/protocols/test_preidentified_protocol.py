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

import json
import struct
import datetime
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.preidentified_protocol import PreidentifiedProtocol
from openc3.streams.stream import Stream


class TestPreidentifiedProtocol(unittest.TestCase):
    buffer = None

    class PreStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestPreidentifiedProtocol.buffer

        def write(self, data):
            TestPreidentifiedProtocol.buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    @classmethod
    def setUpClass(cls):
        setup_system()

    def setUp(self):
        self.interface = TestPreidentifiedProtocol.MyInterface()
        TestPreidentifiedProtocol.buffer = None

    def setup_stream_pkt(self, args=[]):
        self.interface.stream = TestPreidentifiedProtocol.PreStream()
        self.interface.add_protocol(PreidentifiedProtocol, args, "READ_WRITE")
        pkt = System.telemetry.packet("SYSTEM", "META").clone()
        time = datetime.datetime(2020, 1, 31, 12, 15, 30, 500_000)
        pkt.received_time = time
        return (time, pkt)

    def verify_time_tgt_pkt_buffer(self, offset, time, pkt):
        self.assertEqual(
            struct.unpack(
                ">I", TestPreidentifiedProtocol.buffer[offset : (offset + 4)]
            )[0],
            int(time.timestamp()),
        )
        self.assertEqual(
            struct.unpack(
                ">I", TestPreidentifiedProtocol.buffer[(offset + 4) : (offset + 8)]
            )[0],
            500000,
        )
        offset += 8  # time fields
        tgt_name_length = TestPreidentifiedProtocol.buffer[offset]
        offset += 1  # for the length field
        self.assertEqual(
            TestPreidentifiedProtocol.buffer[offset : (offset + tgt_name_length)],
            b"SYSTEM",
        )
        offset += tgt_name_length
        pkt_name_length = TestPreidentifiedProtocol.buffer[offset]
        offset += 1  # for the length field
        self.assertEqual(
            TestPreidentifiedProtocol.buffer[offset : (offset + pkt_name_length)],
            b"META",
        )
        offset += pkt_name_length
        self.assertEqual(
            struct.unpack(
                ">I", TestPreidentifiedProtocol.buffer[offset : (offset + 4)]
            )[0],
            len(pkt.buffer),
        )
        offset += 4
        self.assertEqual(TestPreidentifiedProtocol.buffer[offset:], pkt.buffer)

    def test_handles_receiving_a_bad_packet_length(self):
        self.interface.stream = TestPreidentifiedProtocol.PreStream()
        self.interface.add_protocol(PreidentifiedProtocol, [None, 5], "READ_WRITE")
        pkt = System.telemetry.packet("SYSTEM", "META")
        pkt.received_time = datetime.datetime.now()
        self.interface.write(pkt)
        with self.assertRaises(RuntimeError):
            self.interface.read()

    def test_initializes_attributes(self):
        self.interface.add_protocol(
            PreidentifiedProtocol, ["0xDEADBEEF", 100], "READ_WRITE"
        )
        self.assertEqual(self.interface.read_protocols[0].data, b"")
        self.assertEqual(
            self.interface.read_protocols[0].sync_pattern, b"\xDE\xAD\xBE\xEF"
        )
        self.assertEqual(self.interface.read_protocols[0].max_length, 100)

    def test_write_creates_a_packet_header(self):
        time, pkt = self.setup_stream_pkt()
        self.interface.write(pkt)
        self.assertEqual(TestPreidentifiedProtocol.buffer[0], 0)
        self.verify_time_tgt_pkt_buffer(1, time, pkt)

    def test_write2_creates_a_packet_header(self):
        time, pkt = self.setup_stream_pkt(args=[None, 5, 2])
        self.interface.write(pkt)
        self.verify_time_tgt_pkt_buffer(0, time, pkt)

    def test_write_creates_a_packet_header_with_stored(self):
        time, pkt = self.setup_stream_pkt()
        pkt.stored = True
        self.interface.write(pkt)
        self.assertEqual(TestPreidentifiedProtocol.buffer[0], 0x80)
        self.verify_time_tgt_pkt_buffer(1, time, pkt)

    def test_write_creates_a_packet_header_with_extra(self):
        time, pkt = self.setup_stream_pkt()
        pkt.stored = False
        extra_data = {"vcid": 2}
        pkt.extra = extra_data
        self.interface.write(pkt)
        offset = 0
        self.assertEqual(TestPreidentifiedProtocol.buffer[0], 0x40)
        json_extra = json.dumps(extra_data)
        offset += 1
        self.assertEqual(
            struct.unpack(
                ">I", TestPreidentifiedProtocol.buffer[offset : (offset + 4)]
            )[0],
            len(json_extra),
        )
        offset += 4
        self.assertEqual(
            TestPreidentifiedProtocol.buffer[offset : (offset + len(json_extra))],
            bytes(json_extra, "ascii"),
        )
        offset += len(json_extra)
        self.verify_time_tgt_pkt_buffer(offset, time, pkt)

    def test_write_creates_a_packet_header_with_stored_and_extra(self):
        time, pkt = self.setup_stream_pkt()
        pkt.stored = True
        extra_data = {"vcid": 3}
        pkt.extra = extra_data
        self.interface.write(pkt)
        self.assertEqual(TestPreidentifiedProtocol.buffer[0], 0xC0)
        json_extra = json.dumps(extra_data)
        offset = 1
        self.assertEqual(
            struct.unpack(
                ">I", TestPreidentifiedProtocol.buffer[offset : (offset + 4)]
            )[0],
            len(json_extra),
        )
        offset += 4
        self.assertEqual(
            TestPreidentifiedProtocol.buffer[offset : (offset + len(json_extra))],
            bytes(json_extra, "ascii"),
        )
        offset += len(json_extra)
        self.verify_time_tgt_pkt_buffer(offset, time, pkt)

    def test_write_handles_a_sync_pattern(self):
        time, pkt = self.setup_stream_pkt(args=["DEAD"])
        self.interface.write(pkt)
        self.assertEqual(TestPreidentifiedProtocol.buffer[0:2], b"\xDE\xAD")
        self.assertEqual(TestPreidentifiedProtocol.buffer[2], 0)
        self.verify_time_tgt_pkt_buffer(3, time, pkt)

    def test_write2_handles_a_sync_pattern(self):
        time, pkt = self.setup_stream_pkt(args=["DEAD", None, 2])
        self.interface.write(pkt)
        self.assertEqual(TestPreidentifiedProtocol.buffer[0:2], b"\xDE\xAD")
        self.verify_time_tgt_pkt_buffer(2, time, pkt)

    def test_write_handles_a_sync_pattern_with_stored_and_extra(self):
        time, pkt = self.setup_stream_pkt(args=["DEAD"])
        pkt.stored = True
        extra_data = {"vcid": 4}
        pkt.extra = extra_data
        self.interface.write(pkt)
        self.assertEqual(TestPreidentifiedProtocol.buffer[0:2], b"\xDE\xAD")
        self.assertEqual(TestPreidentifiedProtocol.buffer[2], 0xC0)
        json_extra = json.dumps(extra_data)
        offset = 3
        self.assertEqual(
            struct.unpack(
                ">I", TestPreidentifiedProtocol.buffer[offset : (offset + 4)]
            )[0],
            len(json_extra),
        )
        offset += 4
        self.assertEqual(
            TestPreidentifiedProtocol.buffer[offset : (offset + len(json_extra))],
            bytes(json_extra, "ascii"),
        )
        offset += len(json_extra)
        self.verify_time_tgt_pkt_buffer(offset, time, pkt)

    def test_read_handles_a_sync_pattern(self):
        for args in [["0x1234"], ["0x1234", None, 2]]:
            _, pkt = self.setup_stream_pkt(args=args)
            pkt.write("OPENC3_VERSION", "TEST")
            self.interface.write(pkt)
            self.assertEqual(TestPreidentifiedProtocol.buffer[0], 0x12)
            self.assertEqual(TestPreidentifiedProtocol.buffer[1], 0x34)
            packet = self.interface.read()
            self.assertEqual(packet.target_name, "SYSTEM")
            self.assertEqual(packet.packet_name, "META")
            self.assertTrue(packet.identified())
            self.assertFalse(packet.defined())

            pkt2 = System.telemetry.update("SYSTEM", "META", packet.buffer)
            self.assertEqual(pkt2.read("OPENC3_VERSION"), "TEST")
            self.assertTrue(pkt2.identified())
            self.assertTrue(pkt2.defined())

    def test_read_returns_a_packet(self):
        for args in [[], [None, None, 2]]:
            _, pkt = self.setup_stream_pkt(args=args)
            pkt.write("OPENC3_VERSION", "TEST2")
            self.interface.write(pkt)
            packet = self.interface.read()
            self.assertEqual(packet.target_name, "SYSTEM")
            self.assertEqual(packet.packet_name, "META")
            self.assertTrue(packet.identified())
            self.assertFalse(packet.defined())

            pkt2 = System.telemetry.update("SYSTEM", "META", packet.buffer)
            self.assertEqual(pkt2.read("OPENC3_VERSION"), "TEST2")
            self.assertTrue(pkt2.identified())
            self.assertTrue(pkt2.defined())
