# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
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
from openc3.conversions.bit_reverse_conversion import BitReverseConversion


class TestBitReverseConversion(unittest.TestCase):
    def test_takes_converted_type_and_converted_bit_size(self):
        brc = BitReverseConversion("UINT", 8)
        self.assertEqual(brc.converted_type, "UINT")
        self.assertEqual(brc.converted_bit_size, 8)

    def test_complains_about_invalid_converted_type(self):
        with self.assertRaisesRegex(RuntimeError, "Float Bit Reverse Not Yet Supported"):
            BitReverseConversion("FLOAT", 8)

    def test_reverses_the_bits(self):
        brc = BitReverseConversion("UINT", 8)
        self.assertEqual(brc.call(0x11, None, None), 0x88)
        brc = BitReverseConversion("UINT", 16)
        self.assertEqual(brc.call(0x1234, None, None), 0x2C48)
        brc = BitReverseConversion("UINT", 32)
        self.assertEqual(brc.call(0x87654321, None, None), 0x84C2A6E1)

    def test_returns_the_conversion_string(self):
        self.assertEqual(str(BitReverseConversion("UINT", 8)), "BitReverseConversion UINT 8")

    def test_returns_a_read_config_snippit(self):
        brc = BitReverseConversion("UINT", 8).to_config("READ").strip()
        self.assertEqual(brc, "READ_CONVERSION openc3/conversions/bit_reverse_conversion.py UINT 8")

    def test_creates_a_reproducable_format(self):
        brc = BitReverseConversion("UINT", "8")
        json = brc.as_json()
        self.assertEqual(json["class"], "BitReverseConversion")
        self.assertEqual(json["converted_type"], "UINT")
        self.assertEqual(json["converted_bit_size"], 8)
        new_brc = BitReverseConversion(json["converted_type"], json["converted_bit_size"])
        self.assertEqual(brc.converted_type, (new_brc.converted_type))
        self.assertEqual(brc.converted_bit_size, (new_brc.converted_bit_size))
        self.assertEqual(brc.call(0x11, None, None), 0x88)
        self.assertEqual(new_brc.call(0x11, None, None), 0x88)
