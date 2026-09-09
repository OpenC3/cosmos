# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import math
import unittest
from datetime import datetime
from unittest.mock import *

from openc3.utilities.json import JsonDecoder, JsonEncoder
from test.test_helper import *


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

    def test_decodes_ruby_special_floats(self):
        # Ruby's Float#as_json (openc3/io/json_rpc.rb) encodes non-finite floats as a
        # json_class Hash since bare NaN/Infinity are not valid JSON. Anything written
        # by Ruby and read by Python — a command's extra released from the Ruby queue
        # microservice, for one — arrives in this form.
        ruby_json = (
            '{"nan": {"json_class": "Float", "raw": "NaN"}, '
            '"inf": {"json_class": "Float", "raw": "Infinity"}, '
            '"ninf": {"json_class": "Float", "raw": "-Infinity"}, '
            '"normal": 1.5}'
        )
        decoded = json.loads(ruby_json, cls=JsonDecoder)
        self.assertTrue(math.isnan(decoded["nan"]))
        self.assertEqual(decoded["inf"], float("inf"))
        self.assertEqual(decoded["ninf"], float("-inf"))
        self.assertEqual(decoded["normal"], 1.5)

    def test_decodes_python_special_floats(self):
        # Python's json module writes bare NaN/Infinity literals and reads them back
        # natively, so both forms have to decode to the same values
        string = json.dumps({"nan": float("nan"), "inf": float("inf"), "ninf": float("-inf")}, cls=JsonEncoder)
        decoded = json.loads(string, cls=JsonDecoder)
        self.assertTrue(math.isnan(decoded["nan"]))
        self.assertEqual(decoded["inf"], float("inf"))
        self.assertEqual(decoded["ninf"], float("-inf"))

    def test_leaves_unknown_json_class_hashes_alone(self):
        decoded = json.loads('{"json_class": "Float", "raw": "bogus"}', cls=JsonDecoder)
        self.assertEqual(decoded, {"json_class": "Float", "raw": "bogus"})
        decoded = json.loads('{"json_class": "Object", "raw": [1, 2]}', cls=JsonDecoder)
        self.assertEqual(decoded, {"json_class": "Object", "raw": [1, 2]})
