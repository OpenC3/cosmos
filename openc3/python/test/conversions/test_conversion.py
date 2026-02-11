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

from openc3.conversions.conversion import Conversion
from test.test_helper import *


class TestConversion(unittest.TestCase):
    def test_raises_an_exception(self):
        with self.assertRaisesRegex(RuntimeError, "call method must be defined by subclass"):
            Conversion().call(0, 0, 0)

    def test_returns_a_string(self):
        self.assertEqual(str(Conversion()), "Conversion")
