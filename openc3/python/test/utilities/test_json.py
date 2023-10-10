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

import json
from datetime import datetime
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.utilities.json import JsonEncoder, JsonDecoder


class TestJson(unittest.TestCase):
    def test_encodes_datetime(self):
        time = datetime(2020, 1, 31, 12, 15, 30, 123_456)
        string = json.dumps(time, cls=JsonEncoder)
        self.assertEqual(string, '"2020-01-31 12:15:30.123456"')
        # TODO: Round trip the datetime?

    def test_encodes_bytearray(self):
        ba = bytearray(b"\x00\x01\x02\x03")
        string = json.dumps(ba, cls=JsonEncoder)
        self.assertEqual(string, '{"json_class": "String", "raw": [0, 1, 2, 3]}')
        new_ba = json.loads(string, cls=JsonDecoder)
        self.assertEqual(new_ba, ba)
