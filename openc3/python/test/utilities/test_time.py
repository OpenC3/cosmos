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
from datetime import datetime
from unittest.mock import *

from openc3.utilities.time import *
from test.test_helper import *


class TestTime(unittest.TestCase):
    def test_from_nsec_from_epoch(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=timezone.utc)
        self.assertEqual(from_nsec_from_epoch(1656718485123456000), date)

    def test_to_nsec_from_epoch(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=timezone.utc)
        self.assertEqual(to_nsec_from_epoch(date), 1656718485123456000)

    def test_to_timestamp(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=timezone.utc)
        self.assertEqual(to_timestamp(date), "20220701233445123456000")

    def test_formatted(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=timezone.utc)
        self.assertEqual(formatted(date), "2022/07/01 23:34:45.123")
