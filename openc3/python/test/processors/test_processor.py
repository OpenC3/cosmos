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
from openc3.processors.processor import Processor


class TestProcessor(unittest.TestCase):
    def test_stores_an_optional_value_type(self):
        a = Processor("RAW")
        self.assertEqual(a.value_type, "RAW")
        b = Processor()
        self.assertEqual(b.value_type, "CONVERTED")

    def test_raises_an_exception(self):
        with self.assertRaisesRegex(
            RuntimeError, "call method must be defined by subclass"
        ):
            Processor().call(0, 0)

    def test_returns_a_string(self):
        self.assertEqual(str(Processor()), "Processor")

    def test_has_an_assignable_name(self):
        a = Processor()
        a.name = "Test"
        self.assertEqual(a.name, "TEST")
