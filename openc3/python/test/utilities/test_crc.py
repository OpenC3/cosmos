# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *

from openc3.utilities.crc import Crc8, Crc16, Crc32, Crc64
from test.test_helper import *


class TestCrc(unittest.TestCase):
    # CRC 'answers' were found at
    # http=//www.tty1.net/pycrc/crc-models_en.html

    def test_calculates_a_8_bit_crc(self):
        self.crc = Crc8()
        self.assertEqual(self.crc.calc("123456789"), 0xBC)

    def test_calculates_a_16_bit_crc(self):
        self.crc = Crc16()
        self.assertEqual(self.crc.calc("123456789"), 0x29B1)

    def test_calculates_a_custom_16_bit_crc(self):
        crc = Crc16(0x8005, 0, True, True)
        self.assertEqual(crc.calc(b"\x00\x01\x02\x03"), 0x5EEF)

    def test_calculates_a_32_bit_crc(self):
        self.crc = Crc32()
        self.assertEqual(self.crc.calc("123456789"), 0xCBF43926)

    def test_uses_the_configured_seed_when_passed_none(self):
        self.crc = Crc32()
        self.assertEqual(self.crc.calc("123456789", None), 0xCBF43926)

    def test_calculates_a_64_bit_crc(self):
        self.crc = Crc64()
        self.assertEqual(self.crc.calc("123456789"), 0x995DC9BBDF1939FA)

    def test_reflected_tables_match_the_byte_at_a_time_algorithm(self):
        algorithms = [
            Crc8(0xD5, 0xA5, True, True),
            Crc16(0x8005, 0x1234, True, True),
            Crc32(),
            Crc64(),
        ]
        payload = bytes(range(32))
        for crc in algorithms:
            for length in range(18):
                data = payload[:length]
                with self.subTest(bit_size=crc.bit_size, length=length):
                    self.assertEqual(crc.calc(data), self._original_calc(crc, data))

    def test_non_reflected_tables_match_the_byte_at_a_time_algorithm(self):
        algorithms = [Crc8(), Crc16(), Crc32(reflect=False), Crc64(reflect=False)]
        data = bytes(range(17))
        for crc in algorithms:
            with self.subTest(bit_size=crc.bit_size):
                self.assertEqual(crc.calc(data), self._original_calc(crc, data))

    def test_accepts_an_explicit_zero_seed(self):
        crc = Crc32()
        data = b"123456789"
        self.assertEqual(crc.calc(data, 0), self._original_calc(crc, data, 0))

    @staticmethod
    def _original_calc(crc, data, seed=None):
        """The previous byte-at-a-time implementation, retained as an oracle."""
        if seed is None:
            seed = crc.seed
        value = seed
        if crc.reflect:
            for byte in data:
                value = ((value << 8) & crc.filter_mask) ^ crc.table[
                    (value >> crc.right_shift) ^ crc.bit_reverse_8(byte)
                ]
            value = crc.bit_reverse(value)
        else:
            for byte in data:
                value = ((value << 8) & crc.filter_mask) ^ crc.table[(value >> crc.right_shift) ^ byte]
        return value ^ crc.filter_mask if crc.xor else value
