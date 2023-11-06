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

from datetime import datetime
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.utilities.time import *
from zoneinfo import ZoneInfo


class TestTime(unittest.TestCase):
    @patch("openc3.utilities.time.OPENC3_TIMEZONE", "UTC")
    def test_timezone_utc(self):
        self.assertEqual(openc3_timezone(), timezone.utc)

    @patch("openc3.utilities.time.OPENC3_TIMEZONE", "local")
    def test_timezone_local(self):
        self.assertEqual(openc3_timezone(), datetime.now().astimezone().tzinfo)

    @patch("openc3.utilities.time.OPENC3_TIMEZONE", "US/Mountain")
    def test_timezone_mst(self):
        self.assertEqual(openc3_timezone(), ZoneInfo("US/Mountain"))

    def test_from_nsec_from_epoch(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=openc3_timezone())
        self.assertEqual(from_nsec_from_epoch(1656718485123456000), date)

    def test_to_nsec_from_epoch(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=openc3_timezone())
        self.assertEqual(to_nsec_from_epoch(date), 1656718485123456000)

    def test_to_timestamp(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=openc3_timezone())
        self.assertEqual(to_timestamp(date), "20220701233445123456000")

    def test_formatted(self):
        date = datetime(2022, 7, 1, 23, 34, 45, 123456, tzinfo=openc3_timezone())
        self.assertEqual(formatted(date), "2022/07/01 23:34:45.123")
