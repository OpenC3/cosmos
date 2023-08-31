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
from openc3.interfaces.protocols.burst_protocol import BurstProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream
from openc3.utilities.string import formatted


class TestBurstProtocol(unittest.TestCase):
    data = b"\x01\x02\x03\x04"

    class StreamStub(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestBurstProtocol.data

        def write(self, data):
            TestBurstProtocol.data = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        TestBurstProtocol.data = b"\x01\x02\x03\x04"
        self.interface = TestBurstProtocol.MyInterface()

    def test_initializes_attributes(self):
        self.interface.add_protocol(
            BurstProtocol, [1, "0xDEADBEEF", True], "READ_WRITE"
        )
        self.assertEqual(self.interface.read_protocols[0].data, b"")
        self.assertEqual(self.interface.read_protocols[0].discard_leading_bytes, 1)
        self.assertEqual(
            self.interface.read_protocols[0].sync_pattern, b"\xDE\xAD\xBE\xEF"
        )
        self.assertTrue(self.interface.read_protocols[0].fill_fields)

    def test_connect_clears_the_data(self):
        self.interface.add_protocol(
            BurstProtocol, [1, "0xDEADBEEF", True], "READ_WRITE"
        )
        self.interface.read_protocols[0].data = b"\x00\x01\x02\x03"
        self.interface.connect()
        self.assertEqual(self.interface.read_protocols[0].data, b"")

    def test_disconnect_clears_the_data(self):
        self.interface.add_protocol(
            BurstProtocol, [1, "0xDEADBEEF", True], "READ_WRITE"
        )
        self.interface.read_protocols[0].data = b"\x00\x01\x02\x03"
        self.interface.disconnect()
        self.assertEqual(self.interface.read_protocols[0].data, b"")

    def test_reads_data_from_the_stream(self):
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        pkt = self.interface.read()
        self.assertEqual(pkt.length(), 4)

    # def test_handles_timeouts_from_the_stream(self):
    #     class TimeoutStream(TestBurstProtocol.StreamStub):
    #       def read; raise Timeout='E'rror; end:
    #     self.interface.stream, TimeoutStream()
    #     self.interface.add_protocol(BurstProtocol, [], 'READ_WRITE')
    #     self.assertIsNone(self.interface.read)

    def test_discards_leading_bytes_from_the_stream(self):
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [2], "READ_WRITE")
        pkt = self.interface.read()
        self.assertEqual(pkt.length(), 2)
        self.assertIn("03 04", formatted(pkt.buffer))

    # The sync pattern is NOT part of the data
    def test_discards_the_entire_sync_pattern(self):
        TestBurstProtocol.data = b"\x12\x34\x56\x78\x9A\xBC"
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [2, "0x1234"], "READ_WRITE")
        pkt = self.interface.read()
        self.assertEqual(pkt.length(), 4)
        self.assertIn("56 78 9A BC", formatted(pkt.buffer))

    # The sync pattern is partially part of the data
    def test_discards_part_of_the_sync_pattern(self):
        TestBurstProtocol.data = b"\x12\x34\x56\x78\x9A\xBC"
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [1, "0x123456"], "READ_WRITE")
        pkt = self.interface.read()
        self.assertEqual(pkt.length(), 5)
        self.assertIn("34 56 78 9A BC", formatted(pkt.buffer))

    # The sync pattern is completely part of the data
    def test_handles_a_sync_pattern(self):
        class SyncStream1(TestBurstProtocol.StreamStub):
            read_cnt = 0

            def read(self):
                SyncStream1.read_cnt += 1
                match SyncStream1.read_cnt:
                    case 1:
                        return b"\x00\x00\x00\x00\x00\x00"
                    case 2:
                        return b"\x00\x12\x34\x10\x20"
                    case 3:
                        return b""

        self.interface.stream = SyncStream1()
        self.interface.add_protocol(BurstProtocol, [0, "0x1234"], "READ_WRITE")
        pkt = self.interface.read()
        self.assertEqual(pkt.length(), 4)  # sync plus two bytes
        self.assertIn("12 34 10 20", formatted(pkt.buffer))

    def test_handles_a_sync_pattern_split_across_reads(self):
        class SyncStream2(TestBurstProtocol.StreamStub):
            read_cnt = 0

            def read(self):
                SyncStream2.read_cnt += 1
                match SyncStream2.read_cnt:
                    case 1:
                        return b"\x00\x00\x00\x00\x00\x00\x00\x12"
                    case 2:
                        return b"\x34\x20"
                    case 3:
                        return b""

        self.interface.stream = SyncStream2()
        self.interface.add_protocol(BurstProtocol, [0, "0x1234"], "READ_WRITE")
        pkt = self.interface.read()
        self.assertEqual(pkt.length(), 3)  # sync plus one byte)

    def test_handles_a_false_positive_sync_pattern(self):
        class SyncStream3(TestBurstProtocol.StreamStub):
            read_cnt = 0

            def read(self):
                SyncStream3.read_cnt += 1
                match SyncStream3.read_cnt:
                    case 1:
                        return b"\x00\x00\x12\x00\x00\x12"
                    case 2:
                        return b"\x34\x20"
                    case 3:
                        return b""

        self.interface.stream = SyncStream3()
        self.interface.add_protocol(BurstProtocol, [0, "0x1234"], "READ_WRITE")
        pkt = self.interface.read()
        self.assertEqual(pkt.length(), 3)  # sync plus one byte)

    def test_handle_auto_allow_empty_data_correctly(self):
        self.interface.add_protocol(BurstProtocol, [0, None, False, None], "READ_WRITE")
        self.assertEqual(
            self.interface.read_protocols[0].read_data(b""), ("STOP", None)
        )
        self.assertEqual(self.interface.read_protocols[0].read_data(b"A"), (b"A", None))
        self.interface.add_protocol(BurstProtocol, [0, None, False, None], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].read_data(b""), (b"", None))
        self.assertEqual(
            self.interface.read_protocols[1].read_data(b""), ("STOP", None)
        )
        self.assertEqual(self.interface.read_protocols[0].read_data(b"A"), (b"A", None))
        self.assertEqual(self.interface.read_protocols[1].read_data(b"A"), (b"A", None))
        self.interface.add_protocol(BurstProtocol, [0, None, False, None], "READ_WRITE")
        self.assertEqual(self.interface.read_protocols[0].read_data(b""), (b"", None))
        self.assertEqual(self.interface.read_protocols[1].read_data(b""), (b"", None))
        self.assertEqual(
            self.interface.read_protocols[2].read_data(b""), ("STOP", None)
        )
        self.assertEqual(self.interface.read_protocols[0].read_data(b"A"), (b"A", None))
        self.assertEqual(self.interface.read_protocols[1].read_data(b"A"), (b"A", None))
        self.assertEqual(self.interface.read_protocols[2].read_data(b"A"), (b"A", None))

    def test_doesnt_change_the_data_if_fill_fields_is_false(self):
        TestBurstProtocol.data = b""
        data = Packet(None, None, "BIG_ENDIAN", None, b"\x00\x01\x02\x03")
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [0, "0x1234"], "READ_WRITE")
        data = self.interface.write(data)
        self.assertEqual(TestBurstProtocol.data, b"\x00\x01\x02\x03")

    def test_complains_if_the_data_isnt_big_enough_to_hold_the_sync_pattern(self):
        TestBurstProtocol.data = b""
        data = Packet(None, None, "BIG_ENDIAN", None, b"\x00\x00")
        # Don't discard bytes, include and fill the sync pattern
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(
            BurstProtocol, [0, "0x12345678", True], "READ_WRITE"
        )
        # 2 bytes are not enough to hold the 4 byte sync
        with self.assertRaisesRegex(AttributeError, "buffer insufficient"):
            self.interface.write(data)

    def test_fills_the_sync_pattern_in_the_data(self):
        TestBurstProtocol.data = b""
        data = Packet(None, None, "BIG_ENDIAN", None, b"\x00\x01\x02\x03")
        # Don't discard bytes, include and fill the sync pattern
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [0, "0x1234", True], "READ_WRITE")
        self.interface.write(data)
        self.assertEqual(TestBurstProtocol.data, b"\x12\x34\x02\x03")

    def test_adds_the_sync_pattern_to_the_data_stream(self):
        TestBurstProtocol.data = b""
        data = Packet(None, None, "BIG_ENDIAN", None, b"\x00\x01\x02\x03")
        # Discard first 2 bytes (the sync pattern), include and fill the sync pattern
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(
            BurstProtocol, [2, "0x12345678", True], "READ_WRITE"
        )
        self.interface.write(data)
        self.assertEqual(TestBurstProtocol.data, b"\x12\x34\x56\x78\x02\x03")

    def test_adds_part_of_the_sync_pattern_to_the_data_stream(self):
        TestBurstProtocol.data = b""
        data = Packet(None, None, "BIG_ENDIAN", None, b"\x00\x00\x02\x03")
        # Discard first byte (part of the sync pattern), include and fill the sync pattern
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [1, "0x123456", True], "READ_WRITE")
        self.interface.write(data)
        self.assertEqual(TestBurstProtocol.data, b"\x12\x34\x56\x02\x03")

    def test_write_raw_doesnt_change_the_data(self):
        TestBurstProtocol.data = b""
        # Discard first 2 bytes (the sync pattern), include and fill the sync pattern
        self.interface.stream = TestBurstProtocol.StreamStub()
        self.interface.add_protocol(BurstProtocol, [2, "0x1234", True], "READ_WRITE")
        self.interface.write_raw(b"\x00\x01\x02\x03")
        self.assertEqual(TestBurstProtocol.data, b"\x00\x01\x02\x03")
