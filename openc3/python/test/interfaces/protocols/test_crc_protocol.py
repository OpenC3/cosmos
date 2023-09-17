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

import struct
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.crc_protocol import CrcProtocol
from openc3.interfaces.protocols.burst_protocol import BurstProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream
from openc3.utilities.crc import Crc16, Crc32, Crc64


class TestCrcProtocol(unittest.TestCase):
    buffer = b""

    class CrcStream(Stream):
        def connect(self):
            pass

        def connected(self):
            return True

        def disconnect(self):
            pass

        def read(self):
            return TestCrcProtocol.buffer

        def write(self, data):
            TestCrcProtocol.buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    def setUp(self):
        TestCrcProtocol.buffer = b""
        self.interface = TestCrcProtocol.MyInterface()

    def test_complains_if_strip_crc_is_not_boolean(self):
        for strip_crc in ["ERROR", 0, None]:
            with self.assertRaisesRegex(ValueError, "Invalid strip CRC"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        strip_crc,  # strip crc
                        "ERROR",  # bad strategy
                        -16,  # bit offset
                        16,
                    ],  # bit size
                    "READ_WRITE",
                )

    def test_complains_if_bad_strategy_is_not_error_or_disconnect(self):
        for strategy in ["BAD", 0, None]:
            with self.assertRaisesRegex(ValueError, "Invalid bad CRC strategy"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "TRUE",  # strip crc
                        strategy,  # bad strategy
                        -16,  # bit offset
                        16,
                    ],  # bit size
                    "READ_WRITE",
                )

    def test_complains_if_bit_size_is_not_16_32_or_64(self):
        for bit_size in ["0", 0, None]:
            with self.assertRaisesRegex(ValueError, "Invalid bit size"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "TRUE",  # strip crc
                        "ERROR",  # bad strategy
                        128,  # bit offset
                        bit_size,
                    ],  # bit size
                    "READ_WRITE",
                )

    def test_accepts_a_string_bit_size_of_16_32_or_64(self):
        for bit_size in ["16", "32", "64"]:
            self.interface.add_protocol(
                CrcProtocol,
                [
                    None,  # item name
                    "TRUE",  # strip crc
                    "ERROR",  # bad strategy
                    -32,  # bit offset
                    bit_size,
                ],  # bit size
                "READ_WRITE",
            )
            self.assertEqual(self.interface.read_protocols[-1].bit_size, int(bit_size))

    def test_complains_if_bit_offset_is_not_byte_divisible(self):
        for offset in [None, 100, "100"]:
            with self.assertRaisesRegex(ValueError, "Invalid bit offset"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "TRUE",  # strip crc
                        "ERROR",  # bad strategy
                        offset,  # bit offset
                        16,
                    ],  # bit size
                    "READ_WRITE",
                )

    def test_accepts_a_string_for_bit_offset(self):
        for offset in ["0", "32", "-32"]:
            self.interface.add_protocol(
                CrcProtocol,
                [
                    None,  # item name
                    "TRUE",  # strip crc
                    "ERROR",  # bad strategy
                    offset,  # bit offset
                    16,
                ],  # bit size
                "READ_WRITE",
            )
            self.assertEqual(self.interface.read_protocols[-1].bit_offset, int(offset))

    def test_complains_if_the_endianness_is_not_big_endian_or_little_endian(self):
        for endianness in ["ENDIAN", 0, None]:
            with self.assertRaisesRegex(ValueError, "Invalid endianness"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "FALSE",  # strip crc
                        "ERROR",  # bad strategy
                        -16,  # bit offset
                        16,  # bit size
                        endianness,  # endianness
                        0xDEAD,  # poly
                        0x0,  # seed
                        "TRUE",  # xor
                        "TRUE",  # reflect
                    ],
                    "READ_WRITE",
                )

    def test_complains_if_the_poly_is_not_a_number(self):
        for poly in ["TRUE", "123abc"]:
            with self.assertRaisesRegex(ValueError, "Invalid poly"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "FALSE",  # strip crc
                        "ERROR",  # bad strategy
                        -16,  # bit offset
                        16,  # bit size
                        "BIG_ENDIAN",  # endianness
                        poly,  # poly
                        0x0,  # seed
                        "TRUE",  # xor
                        "TRUE",  # reflect
                    ],
                    "READ_WRITE",
                )

    def test_accepts_none_and_numeric_polynomials(self):
        for poly in ["0xABCD", 0xABCD, None, "", "NONE", "NULL"]:
            self.interface.add_protocol(
                CrcProtocol,
                [
                    None,  # item name
                    "FALSE",  # strip crc
                    "ERROR",  # bad strategy
                    -16,  # bit offset
                    16,  # bit size
                    "BIG_ENDIAN",  # endianness
                    poly,  # poly
                    0x0,  # seed
                    "TRUE",  # xor
                    "TRUE",  # reflect
                ],
                "READ_WRITE",
            )
            # If we get here we're good

    def test_complains_if_the_seed_is_not_a_number(self):
        for seed in ["TRUE", "123abc"]:
            with self.assertRaisesRegex(ValueError, "Invalid seed"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "FALSE",  # strip crc
                        "ERROR",  # bad strategy
                        -16,  # bit offset
                        16,  # bit size
                        "LITTLE_ENDIAN",  # endianness
                        0xABCD,  # poly
                        seed,  # seed
                        "TRUE",  # xor
                        "TRUE",  # reflect
                    ],
                    "READ_WRITE",
                )

    def test_accepts_none_and_numeric_seeds(self):
        for seed in ["0xABCD", 0xABCD, None, "", "NONE", "NULL"]:
            self.interface.add_protocol(
                CrcProtocol,
                [
                    None,  # item name
                    "FALSE",  # strip crc
                    "ERROR",  # bad strategy
                    -16,  # bit offset
                    16,  # bit size
                    "BIG_ENDIAN",  # endianness
                    None,  # poly
                    seed,  # seed
                    "TRUE",  # xor
                    "TRUE",  # reflect
                ],
                "READ_WRITE",
            )
            # If we get here we're good

    def test_accepts_none_true_false_for_xor(self):
        for xor in [None, "", "NONE", "NULL", "TRUE", "FALSE"]:
            self.interface.add_protocol(
                CrcProtocol,
                [
                    None,  # item name
                    "FALSE",  # strip crc
                    "ERROR",  # bad strategy
                    -16,  # bit offset
                    16,  # bit size
                    "BIG_ENDIAN",  # endianness
                    0xABCD,  # poly
                    0,  # seed
                    xor,  # xor
                    "TRUE",  # reflect
                ],
                "READ_WRITE",
            )
            # If we get here we're good

    def test_complains_if_the_xor_is_not_boolean(self):
        for xor in ["ERROR", 0]:
            with self.assertRaisesRegex(ValueError, "Invalid XOR value"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "FALSE",  # strip crc
                        "ERROR",  # bad strategy
                        -16,  # bit offset
                        16,  # bit size
                        "BIG_ENDIAN",  # endianness
                        0xABCD,  # poly
                        0,  # seed
                        xor,  # xor
                        "TRUE",  # reflect
                    ],
                    "READ_WRITE",
                )

    def test_accepts_none_true_false_for_reflect(self):
        for reflect in [None, "", "NONE", "NULL", "TRUE", "FALSE"]:
            self.interface.add_protocol(
                CrcProtocol,
                [
                    None,  # item name
                    "FALSE",  # strip crc
                    "ERROR",  # bad strategy
                    -16,  # bit offset
                    16,  # bit size
                    "BIG_ENDIAN",  # endianness
                    0xABCD,  # poly
                    0,  # seed
                    "TRUE",  # xor
                    reflect,  # reflect
                ],
                "READ_WRITE",
            )
            # If we get here we're good

    def test_complains_if_the_reflect_is_not_boolean(self):
        for reflect in ["ERROR", 0]:
            with self.assertRaisesRegex(ValueError, "Invalid reflect value"):
                self.interface.add_protocol(
                    CrcProtocol,
                    [
                        None,  # item name
                        "FALSE",  # strip crc
                        "ERROR",  # bad strategy
                        -16,  # bit offset
                        16,  # bit size
                        "BIG_ENDIAN",  # endianness
                        0xABCD,  # poly
                        0,  # seed
                        "TRUE",  # xor
                        reflect,  # reflect
                    ],
                    "READ_WRITE",
                )

    def test_does_nothing_if_protocol_added_as_write(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                None,  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")
        TestCrcProtocol.buffer = b"\x00\x01\x02\x03\x04\x05\x06\x07"

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 8)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer)

    def test_reads_the_16_bit_crc_field_and_compares_to_the_crc(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -16,  # bit offset
                16,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 16, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc16().calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">H", crc)  # [crc].pack("n")

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 6)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer)

    def test_reads_the_32_bit_crc_field_and_compares_to_the_crc(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc32().calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">I", crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 8)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer)

    def test_reads_the_64_bit_crc_field_and_compares_to_the_crc(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -64,  # bit offset
                64,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 64, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc64().calc(TestCrcProtocol.buffer)
        top_crc = crc >> 32
        bottom_crc = crc & 0xFFFFFFFF
        TestCrcProtocol.buffer += struct.pack(">I", top_crc)
        TestCrcProtocol.buffer += struct.pack(">I", bottom_crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 12)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer)

    #       context "with a specified CRC poly, seed, xor, and reflect"

    def test_reads_the_16_bit_crc_field_and_compares_to_the_crc2(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -16,  # bit offset
                16,  # bit size
                "BIG_ENDIAN",  # endianness
                0x8005,  # poly
                0x0,  # seed
                "TRUE",  # xor
                "TRUE",  # reflect
            ],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 16, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc16 = Crc16(0x8005, 0, True, True)
        crc = crc16.calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">H", crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 6)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer)

    def test_reads_the_32_bit_crc_field_and_compares_to_the_crc2(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,  # bit size
                "BIG_ENDIAN",  # endianness
                0x1EDC6F41,  # poly
                0x0,  # seed
                "FALSE",  # xor
                "FALSE",  # reflect
            ],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc32 = Crc32(0x1EDC6F41, 0, False, False)
        crc = crc32.calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">I", crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 8)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer)

    def test_reads_the_64_bit_crc_field_and_compares_to_the_crc2(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -64,  # bit offset
                64,  # bit size
                "BIG_ENDIAN",  # endianness
                0x000000000000001B,  # poly
                0x0,  # seed
                "FALSE",  # xor
                "FALSE",  # reflect
            ],
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 64, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc64 = Crc64(0x000000000000001B, 0, False, False)
        crc = crc64.calc(TestCrcProtocol.buffer)
        top_crc = crc >> 32
        bottom_crc = crc & 0xFFFFFFFF
        TestCrcProtocol.buffer += struct.pack(">I", top_crc)
        TestCrcProtocol.buffer += struct.pack(">I", bottom_crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 12)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer)

    @patch("openc3.utilities.logger.Logger", return_value=Mock())
    def test_logs_an_error_if_the_crc_does_not_match(self, logger):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc32().calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">I", crc)
        # Modify a bytes to change the CRC
        ba = bytearray(TestCrcProtocol.buffer)
        ba[0] = 1
        TestCrcProtocol.buffer = bytes(ba)

        for stdout in capture_io():
            packet = self.interface.read()
            self.assertEqual(len(packet.buffer), 8)
            self.assertEqual(packet.buffer, TestCrcProtocol.buffer)
            self.assertIn(
                "Invalid CRC detected",
                stdout.getvalue(),
            )

    def test_disconnects_if_the_crc_does_not_match(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "DISCONNECT",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc32().calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">I", crc)
        # Modify a bytes to change the CRC
        ba = bytearray(TestCrcProtocol.buffer)
        ba[0] = 1
        TestCrcProtocol.buffer = bytes(ba)

        for stdout in capture_io():
            packet = self.interface.read()
            self.assertIsNone(packet)  # thread disconnects when packet is None
            self.assertIn(
                "Invalid CRC detected",
                stdout.getvalue(),
            )

    def test_can_strip_the_16_bit_crc_at_the_end(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "TRUE",  # strip crc
                "ERROR",  # bad strategy
                -16,  # bit offset
                16,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 16, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc16().calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">H", crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 4)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer[0:4])

    def test_can_strip_the_32_bit_crc_at_the_end(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "TRUE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc32().calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">I", crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 4)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer[0:4])

    def test_can_strip_the_64_bit_crc_at_the_end(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "TRUE",  # strip crc
                "ERROR",  # bad strategy
                -64,  # bit offset
                64,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 64, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc64().calc(TestCrcProtocol.buffer)
        top_crc = crc >> 32
        bottom_crc = crc & 0xFFFFFFFF
        TestCrcProtocol.buffer += struct.pack(">I", top_crc)
        TestCrcProtocol.buffer += struct.pack(">I", bottom_crc)

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 4)
        self.assertEqual(packet.buffer, TestCrcProtocol.buffer[0:4])

    def test_can_strip_the_32_bit_crc_in_the_middle(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "TRUE",  # strip crc
                "ERROR",  # bad strategy
                32,  # bit offset
                16,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 16, "UINT")
        packet.append_item("TRAILER", 16, "UINT")

        TestCrcProtocol.buffer = b"\x00\x01\x02\x03"
        crc = Crc16().calc(TestCrcProtocol.buffer)
        TestCrcProtocol.buffer += struct.pack(">H", crc)
        TestCrcProtocol.buffer += b"\x04\x05"

        packet = self.interface.read()
        self.assertEqual(len(packet.buffer), 6)
        self.assertEqual(packet.buffer, b"\x00\x01\x02\x03\x04\x05")

    def test_does_nothing_if_protocol_added_as_read(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                None,  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = b"\x00\x01\x02\x03\x00\x00\x00\x00\x04\x05\x06\x07"
        self.interface.write(packet)
        self.assertEqual(len(TestCrcProtocol.buffer), 12)
        self.assertEqual(TestCrcProtocol.buffer, packet.buffer)

    def test_complains_if_the_item_does_not_exist(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "MYCRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = b"\x00\x01\x02\x03\x00\x00\x00\x00\x04\x05\x06\x07"
        with self.assertRaisesRegex(
            AttributeError, "Packet item 'TGT PKT MYCRC' does not exist"
        ):
            self.interface.write(packet)

    def test_calculates_and_writes_the_16_bit_crc_item(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -48,  # bit offset
                16,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 16, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = b"\x00\x01\x02\x03\x00\x00\x04\x05\x06\x07"
        self.interface.write(packet)
        buffer = b"\x00\x01\x02\x03"
        buffer += struct.pack(">H", Crc16().calc(b"\x00\x01\x02\x03"))
        buffer += b"\x04\x05\x06\x07"
        self.assertEqual(TestCrcProtocol.buffer, buffer)

    def test_calculates_and_writes_the_32_bit_crc_item(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = b"\x00\x01\x02\x03\x00\x00\x00\x00\x04\x05\x06\x07"
        self.interface.write(packet)
        buffer = b"\x00\x01\x02\x03"
        buffer += struct.pack(">I", Crc32().calc(b"\x00\x01\x02\x03"))
        buffer += b"\x04\x05\x06\x07"
        self.assertEqual(TestCrcProtocol.buffer, buffer)

    def test_calculates_and_writes_the_64_bit_crc_item(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                "CRC",  # item name
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -64,  # bit offset
                64,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 64, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = (
            b"\x00\x01\x02\x03\x00\x00\x00\x00\x00\x00\x00\x00\x04\x05\x06\x07"
        )
        self.interface.write(packet)
        buffer = b"\x00\x01\x02\x03"
        crc = Crc64().calc(buffer)
        top_crc = crc >> 32
        bottom_crc = crc & 0xFFFFFFFF
        buffer += struct.pack(">I", top_crc)
        buffer += struct.pack(">I", bottom_crc)
        buffer += b"\x04\x05\x06\x07"
        self.assertEqual(TestCrcProtocol.buffer, buffer)

    def test_appends_the_16_bit_crc_to_the_end(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                None,  # item name None means append
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -16,  # bit offset
                16,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = b"\x00\x01\x02\x03\x00\x00\x00\x00\x04\x05\x06\x07"
        buffer = packet.buffer
        buffer += struct.pack(">H", Crc16().calc(packet.buffer))
        self.interface.write(packet)
        self.assertEqual(len(TestCrcProtocol.buffer), 14)
        self.assertEqual(TestCrcProtocol.buffer, buffer)

    def test_appends_the_32_bit_crc_to_the_end(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                None,  # item name None means append
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -32,  # bit offset
                32,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = b"\x00\x01\x02\x03\x00\x00\x00\x00\x04\x05\x06\x07"
        buffer = packet.buffer
        buffer += struct.pack(">I", Crc32().calc(packet.buffer))
        self.interface.write(packet)
        self.assertEqual(len(TestCrcProtocol.buffer), 16)
        self.assertEqual(TestCrcProtocol.buffer, buffer)

    def test_appends_the_64_bit_crc_to_the_end(self):
        self.interface.stream = TestCrcProtocol.CrcStream()
        self.interface.add_protocol(BurstProtocol, [], "READ_WRITE")
        self.interface.add_protocol(
            CrcProtocol,
            [
                None,  # item name None means append
                "FALSE",  # strip crc
                "ERROR",  # bad strategy
                -64,  # bit offset
                64,
            ],  # bit size
            "READ_WRITE",
        )
        self.interface.target_names = ["TGT"]
        packet = Packet("TGT", "PKT")
        packet.append_item("DATA", 32, "UINT")
        packet.append_item("CRC", 32, "UINT")
        packet.append_item("TRAILER", 32, "UINT")
        packet.buffer = b"\x00\x01\x02\x03\x00\x00\x00\x00\x04\x05\x06\x07"
        buffer = packet.buffer
        crc = Crc64().calc(buffer)
        top_crc = crc >> 32
        bottom_crc = crc & 0xFFFFFFFF
        buffer += struct.pack(">I", top_crc)
        buffer += struct.pack(">I", bottom_crc)
        self.interface.write(packet)
        self.assertEqual(len(TestCrcProtocol.buffer), 20)
        self.assertEqual(TestCrcProtocol.buffer, buffer)
