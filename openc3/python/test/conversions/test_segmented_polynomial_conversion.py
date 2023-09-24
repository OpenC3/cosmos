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
from openc3.conversions.segmented_polynomial_conversion import (
    SegmentedPolynomialConversion,
)


class TestSegmentedPolynomialConversion(unittest.TestCase):
    def test_initializes_converted_type_and_converted_bit_size(self):
        gc = SegmentedPolynomialConversion()
        self.assertEqual(gc.converted_type, "FLOAT")
        self.assertEqual(gc.converted_bit_size, 64)

    def test_performs_the_conversion_and_return_the_result(self):
        gc = SegmentedPolynomialConversion()
        gc.add_segment(10, 1, 2)
        gc.add_segment(5, 2, 2)
        gc.add_segment(15, 3, 2)
        self.assertEqual(gc.call(1, None, None), 4.0)
        self.assertEqual(gc.call(5, None, None), 12.0)
        self.assertEqual(gc.call(11, None, None), 23.0)
        self.assertEqual(gc.call(20, None, None), 43.0)

    def test_returns_the_equations(self):
        self.assertEqual(str(SegmentedPolynomialConversion()), "")
        gc = SegmentedPolynomialConversion()
        gc.add_segment(10, 1)
        gc.add_segment(5, 2, 2)
        gc.add_segment(15, 3, 2, 3)
        self.assertEqual(
            str(gc),
            "Lower Bound= 15 Polynomial= 3 + 2x + 3x^2\nLower Bound= 10 Polynomial= 1\nLower Bound= 5 Polynomial= 2 + 2x",
        )

    def test_creates_a_reproducable_format(self):
        spc = SegmentedPolynomialConversion()
        spc.add_segment(10, 1, 2)
        spc.add_segment(5, 2, 2)
        spc.add_segment(15, 3, 2)
        json = spc.as_json()
        self.assertEqual(json["class"], "SegmentedPolynomialConversion")
        new_spc = SegmentedPolynomialConversion(*json["params"])
        for index, segment in enumerate(spc.segments):
            self.assertEqual(segment, new_spc.segments[index])
        self.assertEqual(spc.converted_type, (new_spc.converted_type))
        self.assertEqual(spc.converted_bit_size, (new_spc.converted_bit_size))
        self.assertEqual(spc.converted_array_size, (new_spc.converted_array_size))
        self.assertEqual(spc.call(1, None, None), new_spc.call(1, None, None))
        self.assertEqual(spc.call(5, None, None), new_spc.call(5, None, None))
        self.assertEqual(spc.call(11, None, None), new_spc.call(11, None, None))
        self.assertEqual(spc.call(20, None, None), new_spc.call(20, None, None))
