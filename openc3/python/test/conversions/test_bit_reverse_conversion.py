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

from openc3.conversions.bit_reverse_conversion import BitReverseConversion
from test.test_helper import *


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
        new_brc = BitReverseConversion(*json["params"])
        self.assertEqual(brc.converted_type, (new_brc.converted_type))
        self.assertEqual(brc.converted_bit_size, (new_brc.converted_bit_size))
        self.assertEqual(brc.call(0x11, None, None), 0x88)
        self.assertEqual(new_brc.call(0x11, None, None), 0x88)
