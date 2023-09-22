#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
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
from openc3.conversions.generic_conversion import GenericConversion


class TestGenericConversion(unittest.TestCase):
    def test_takes_code_to_eval_converted_type_and_converted_bit_size(self):
        gc = GenericConversion("10 / 2", "UINT", 8)
        self.assertEqual(gc.code_to_eval, "10 / 2")
        self.assertEqual(gc.converted_type, "UINT")
        self.assertEqual(gc.converted_bit_size, 8)

    def test_complains_about_invalid_converted_type(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid type MINE"):
            GenericConversion("", "MINE", 8)

    def test_calls_the_code_to_eval_and_return_the_result(self):
        gc = GenericConversion("10 / 2", "UINT", 8)
        self.assertEqual(gc.call(0, 0, 0), 5)

    def test_returns_the_code_to_eval(self):
        self.assertEqual(str(GenericConversion("10 / 2")), "10 / 2")

    def test_creates_a_reproducable_format(self):
        gc = GenericConversion("10.0 / 2", "FLOAT", "32", "64")
        json = gc.as_json()
        self.assertEqual(json["class"], "GenericConversion")
        self.assertEqual(json["converted_type"], "FLOAT")
        self.assertEqual(json["converted_bit_size"], 32)
        self.assertEqual(json["converted_array_size"], 64)
        new_gc = GenericConversion(*json["params"])
        self.assertEqual(gc.code_to_eval, (new_gc.code_to_eval))
        self.assertEqual(gc.converted_type, (new_gc.converted_type))
        self.assertEqual(gc.converted_bit_size, (new_gc.converted_bit_size))
        self.assertEqual(gc.converted_array_size, (new_gc.converted_array_size))
        self.assertEqual(gc.call(0, 0, 0), 5.0)
        self.assertEqual(new_gc.call(0, 0, 0), 5.0)
