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
from openc3.interfaces.protocols.length_protocol import LengthProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream


class TestLengthProtocol(unittest.TestCase):
    buffer = b""

    class LengthStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestLengthProtocol.buffer

        def write(self, data):
            TestLengthProtocol.buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        TestLengthProtocol.buffer = b""
        self.interface = TestLengthProtocol.MyInterface()

    def test_initializes_attributes(self):
        self.interface.add_protocol(
            LengthProtocol,
            [16, 32, 16, 2, "LITTLE_ENDIAN", 2, "0xDEADBEEF", 100, True],
            "READ_WRITE",
        )
        self.assertEqual(self.interface.read_protocols[0].data, b"")
        self.assertEqual(self.interface.read_protocols[0].length_bit_offset, 16)
        self.assertEqual(self.interface.read_protocols[0].length_bit_size, 32)
        self.assertEqual(self.interface.read_protocols[0].length_value_offset, 16)
        self.assertEqual(self.interface.read_protocols[0].length_bytes_per_count, 2)
        self.assertEqual(
            self.interface.read_protocols[0].length_endianness, "LITTLE_ENDIAN"
        )
        self.assertEqual(self.interface.read_protocols[0].discard_leading_bytes, 2)
        self.assertEqual(
            self.interface.read_protocols[0].sync_pattern, b"\xDE\xAD\xBE\xEF"
        )
        self.assertEqual(self.interface.read_protocols[0].max_length, 100)
        self.assertTrue(self.interface.read_protocols[0].fill_fields)

    def test_caches_data_for_reads_correctly(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                0,  # bit offset
                8,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x02\x03\x02\x05"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 2)
        self.assertEqual(packet.buffer, b"\x02\x03")
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 2)
        self.assertEqual(packet.buffer, b"\x02\x05")
        self.assertEqual(
            self.interface.read_protocols[0].read_data(b"\x03\x01\x02\x03\x04\x05"),
            (b"\x03\x01\x02", None),
        )
        self.assertEqual(
            self.interface.read_protocols[0].read_data(b""), (b"\x03\x04\x05", None)
        )
        self.assertEqual(
            self.interface.read_protocols[0].read_data(b""), ("STOP", None)
        )

    # This test match uses two length protocols to verify that data flows correctly between the two protocols and that earlier data
    # is removed correctly using discard leading bytes.  In general it is not typical to use two different length protocols, but it could
    # be useful to pull out a packet inside of a packet.
    def test_caches_data_for_reads_correctly_with_multiple_protocols(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                0,  # bit offset
                8,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        self.interface.add_protocol(
            LengthProtocol,
            [
                0,  # bit offset
                8,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                1,
            ],
            "READ_WRITE",
        )  # Discard leading bytes set to 1
        # The second protocol above will receive the two byte packets from the first protocol and
        # then drop the length field.
        TestLengthProtocol.buffer = b"\x02\x03\x02\x05"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 1)
        self.assertEqual(packet.buffer, b"\x03")
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 1)
        self.assertEqual(packet.buffer, b"\x05")

    def test_reads_little_endian_length_fields_from_the_stream(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "LITTLE_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x01\x06\x00\x03\x04"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 6)

    def test_reads_little_endian_bit_fields_from_the_stream(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                19,  # bit offset
                5,  # bit size
                0,  # length offset
                1,  # bytes per count
                "LITTLE_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x01\x05\x03\x04"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 5)

    def test_read_adjusts_length_by_offset(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                1,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x01\x00\x05\x03\x04"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 6)

    def test_read_adjusts_length_by_bytes_per_count(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                1,  # length offset
                2,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x01\x00\x05\x03\x04\x05\x06\x07\x08\x09"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 11)

    def test_accesses_length_at_odd_offset_and_bit_sizes(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                19,  # bit offset
                5,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x01\x05\x03\x04"
        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 5)

    def test_raises_an_error_with_a_packet_length_of_0(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x01\x00\x00\x03\x04\x05\x06\x07\x08\x09"
        with self.assertRaisesRegex(
            AttributeError, "Calculated packet length of 0 bits"
        ):
            self.interface.read()

    def test_raises_an_error_if_packet_length_not_enough_to_support_offset_and_size(
        self,
    ):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                3,  # length offset of 3 not enough to support 2 byte length field at offset 2 bytes
                1,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x01\x00\x00\x03\x04\x05\x06\x07\x08\x09"
        with self.assertRaisesRegex(
            AttributeError, "Calculated packet length of 24 bits"
        ):
            self.interface.read()

    def test_processes_a_0_length_with_a_non_zero_length_offset(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                0,  # bit offset
                16,  # bit size
                4,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
            ],
            "READ_WRITE",
        )
        TestLengthProtocol.buffer = b"\x00\x00\x01\x02\x00\x00\x03\x04"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x00\x01\x02")
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x00\x03\x04")

    def test_validates_length_against_the_maximum_length(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard
                None,  # sync
                50,
            ],
            "READ_WRITE",
        )  # max_length
        TestLengthProtocol.buffer = b"\x00\x01\xFF\xFF\x03\x04"
        with self.assertRaisesRegex(
            AttributeError, "Length value received larger than max_length= 65535 > 50"
        ):
            self.interface.read()

    def test_handles_a_sync_value_in_the_packet(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard
                "DEAD",
            ],
            "READ_WRITE",
        )  # sync
        TestLengthProtocol.buffer = b"\x00\xDE\xAD\x00\x08\x01\x02\x03\x04\x05\x06"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\xDE\xAD\x00\x08\x01\x02\x03\x04")

    def test_handles_a_sync_value_that_is_discarded(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset (past the discard)
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                2,  # discard
                "DEAD",
            ],
            "READ_WRITE",
        )  # sync
        TestLengthProtocol.buffer = (
            b"\x00\xDE\xAD\x00\x08\x01\x02\x03\x04\x05\x06\x07\x08"
        )
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x00\x08\x01\x02\x03\x04")

    def test_handles_a_length_value_that_is_discarded(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                8,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                4,  # discard
                None,
            ],
            "READ_WRITE",
        )  # sync
        TestLengthProtocol.buffer = b"\x00\x00\x08\x00\x01\x02\x03\x04\x05\x06\x07\x08"
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04")

    def test_handles_a_sync_and_length_value_that_are_discarded(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                8,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                4,  # discard
                "DEAD",
            ],
            "READ_WRITE",
        )  # sync
        TestLengthProtocol.buffer = (
            b"\x00\xDE\xAD\x0A\x00\x01\x02\x03\x04\x05\x06\x07\x08"
        )
        packet = self.interface.read()
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04\x05\x06")

    def test_sends_data_directly_to_the_stream_if_no_fill(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                32,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard no leading bytes
                "DEAD",  # sync
                None,  # max length
                False,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02"
        self.interface.write(packet)
        self.assertEqual(TestLengthProtocol.buffer, b"\x01\x02")

    def test_complains_if_not_enough_data_to_write_the_sync_and_length_fields(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                32,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard no leading bytes
                "DEAD",  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04"
        # 4 bytes are not enough since we expect the length field at offset 32
        with self.assertRaisesRegex(AttributeError, "buffer insufficient"):
            self.interface.write(packet)

    def test_write_adjusts_length_by_offset(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                2,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard no leading bytes
                None,  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06"
        self.interface.write(packet)
        # Length is 4 instead of 6 due to length offset
        self.assertEqual(packet.buffer, b"\x01\x02\x00\x04\x05\x06")
        self.assertEqual(TestLengthProtocol.buffer, b"\x01\x02\x00\x04\x05\x06")

    def test_write_adjusts_length_by_bytes_per_count(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                0,  # bit offset
                16,  # bit size
                0,  # length offset
                2,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard no leading bytes
                None,  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06"
        self.interface.write(packet)
        # Length is 3 instead of 6 due to bytes per count
        self.assertEqual(packet.buffer, b"\x00\x03\x03\x04\x05\x06")
        self.assertEqual(TestLengthProtocol.buffer, b"\x00\x03\x03\x04\x05\x06")

    def test_writes_length_at_odd_offset_and_bit_sizes(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                19,  # bit offset
                5,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard no leading bytes
                None,  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x55\xAA\x00\xAA\x55\xAA"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\x55\xAA\x06\xAA\x55\xAA")
        self.assertEqual(TestLengthProtocol.buffer, b"\x55\xAA\x06\xAA\x55\xAA")

    def test_validates_length_against_the_maximum_length_1(self):
        # Length inside packet
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                0,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard
                None,  # sync
                4,  # max_length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06"
        with self.assertRaisesRegex(
            AttributeError, "Calculated length 6 larger than max_length 4"
        ):
            packet = self.interface.write(packet)

    def test_validates_length_against_the_maximum_length_2(self):
        # Length outside packet (data stream)
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                0,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                2,  # discard
                None,  # sync
                4,  # max_length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06"
        with self.assertRaisesRegex(
            AttributeError, "Calculated length 8 larger than max_length 4"
        ):
            packet = self.interface.write(packet)

    def test_inserts_the_sync_and_length_fields_into_the_packet_1(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard no leading bytes
                "DEAD",  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06\x07\x08"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\xDE\xAD\x00\x08\x05\x06\x07\x08")
        self.assertEqual(TestLengthProtocol.buffer, b"\xDE\xAD\x00\x08\x05\x06\x07\x08")

    def test_inserts_the_sync_and_length_fields_into_the_packet_2(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                64,  # bit offset
                32,  # bit size
                12,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                0,  # discard no leading bytes
                "BA5EBA11CAFEBABE",
                None,
                True,
            ],
            "READ_WRITE",
        )
        packet = Packet(None, None)
        # The packet buffer contains the sync and length fields which are overwritten by the write call
        packet.buffer = (
            b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04"
        )
        self.interface.write(packet)
        # Since we discarded 0 leading bytes, they are simply written over by the write call
        self.assertEqual(
            packet.buffer,
            b"\xBA\x5E\xBA\x11\xCA\xFE\xBA\xBE\x00\x00\x00\x04\x01\x02\x03\x04",
        )
        self.assertEqual(
            TestLengthProtocol.buffer,
            b"\xBA\x5E\xBA\x11\xCA\xFE\xBA\xBE\x00\x00\x00\x04\x01\x02\x03\x04",
        )

    def test_inserts_the_length_field_into_the_packet_and_sync_into_data_stream_1(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                2,  # discard sync
                "DEAD",  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\x00\x08\x03\x04\x05\x06")
        self.assertEqual(TestLengthProtocol.buffer, b"\xDE\xAD\x00\x08\x03\x04\x05\x06")

    def test_inserts_the_length_field_into_the_packet_and_sync_into_data_stream_2(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                32,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                4,  # discard sync
                "BA5EBA11",  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\x00\x0A\x03\x04\x05\x06")
        self.assertEqual(
            TestLengthProtocol.buffer, b"\xBA\x5E\xBA\x11\x00\x0A\x03\x04\x05\x06"
        )

    def test_inserts_the_length_field_into_the_packet_and_sync_into_data_stream_3(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                64,  # bit offset
                32,  # bit size
                12,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                8,  # discard 8 leading bytes (sync)
                "BA5EBA11CAFEBABE",
                None,
                True,
            ],
            "READ_WRITE",
        )
        packet = Packet(None, None)
        # The packet buffer contains the length field which is overwritten by the write call
        packet.buffer = b"\x00\x00\x00\x00\x01\x02\x03\x04"
        self.interface.write(packet)
        # Since we discarded 8 leading bytes, they are put back in the final stream data
        self.assertEqual(packet.buffer, b"\x00\x00\x00\x04\x01\x02\x03\x04")
        self.assertEqual(
            TestLengthProtocol.buffer,
            b"\xBA\x5E\xBA\x11\xCA\xFE\xBA\xBE\x00\x00\x00\x04\x01\x02\x03\x04",
        )

    def test_inserts_the_length_field_into_the_data_stream_1(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                8,  # bit offset
                16,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                4,  # discard
                None,  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04")
        self.assertEqual(TestLengthProtocol.buffer, b"\x00\x00\x08\x00\x01\x02\x03\x04")

    def test_inserts_the_length_field_into_the_data_stream_2(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                8,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                4,  # discard
                None,  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A")
        self.assertEqual(
            TestLengthProtocol.buffer,
            b"\x00\x00\x0E\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A",
        )

    def test_inserts_the_sync_and_length_fields_into_the_data_stream_1(self):
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                16,  # bit offset
                8,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                4,  # discard
                "0xDEAD",  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04\x05\x06"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04\x05\x06")
        self.assertEqual(
            TestLengthProtocol.buffer, b"\xDE\xAD\x0A\x00\x01\x02\x03\x04\x05\x06"
        )

    def test_inserts_the_sync_and_length_fields_into_the_data_stream_2(self):
        TestLengthProtocol.buffer = ""
        self.interface.stream = TestLengthProtocol.LengthStream()
        self.interface.add_protocol(
            LengthProtocol,
            [
                32,  # bit offset
                8,  # bit size
                0,  # length offset
                1,  # bytes per count
                "BIG_ENDIAN",
                5,  # discard
                "BA5EBA11",  # sync
                None,  # max length
                True,
            ],
            "READ_WRITE",
        )  # fill fields
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02\x03\x04"
        self.interface.write(packet)
        self.assertEqual(packet.buffer, b"\x01\x02\x03\x04")
        self.assertEqual(
            TestLengthProtocol.buffer, b"\xBA\x5E\xBA\x11\x09\x01\x02\x03\x04"
        )
