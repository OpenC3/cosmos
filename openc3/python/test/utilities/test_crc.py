#!/usr/bin/env python3

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
from openc3.utilities.crc import Crc8, Crc16, Crc32, Crc64


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

    def test_calculates_a_64_bit_crc(self):
        self.crc = Crc64()
        self.assertEqual(self.crc.calc("123456789"), 0x995DC9BBDF1939FA)
