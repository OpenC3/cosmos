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
from openc3.conversions.polynomial_conversion import PolynomialConversion


class TestPolynomialConversion(unittest.TestCase):
    def test_takes_a_coefficents_array(self):
        gc = PolynomialConversion(1, 2, 3)
        self.assertEqual(gc.converted_type, "FLOAT")
        self.assertEqual(gc.converted_bit_size, 64)

    def test_calls_the_code_to_eval_and_return_the_result(self):
        gc = PolynomialConversion(1, 2, 3)
        self.assertEqual(gc.call(1, None, None), 6.0)

    def test_str_returns_the_equation(self):
        self.assertEqual(str(PolynomialConversion(1, 2, 3)), "1.0 + 2.0x + 3.0x^2")

    def test_as_jsoncreates_a_reproducable_format(self):
        pc = PolynomialConversion(1, 2, 3)
        json = pc.as_json()
        self.assertEqual(json["class"], "PolynomialConversion")
        new_pc = PolynomialConversion(*json["params"])
        self.assertEqual(pc.coeffs, (new_pc.coeffs))
        self.assertEqual(pc.converted_type, (new_pc.converted_type))
        self.assertEqual(pc.converted_bit_size, (new_pc.converted_bit_size))
        self.assertEqual(pc.converted_array_size, (new_pc.converted_array_size))
        self.assertEqual(pc.call(1, None, None), 6.0)
        self.assertEqual(new_pc.call(1, None, None), 6.0)
