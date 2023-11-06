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
from openc3.script.metadata import *
from openc3.utilities.time import openc3_timezone

global gData


class Proxy:
    def request(*args, **kwargs):
        global gData
        global gStatus

        mock = Mock()
        match args[0]:
            case "post":
                mock.status_code = 201
                gData = kwargs["data"]
                mock.text = json.dumps(kwargs["data"]["metadata"])
            case "get":
                mock.status_code = 200
                gData["start"] = datetime.now(openc3_timezone()).timestamp()
                mock.text = json.dumps(gData)
            case "put":
                mock.status_code = 200
                gData = kwargs["data"]
                mock.text = json.dumps(gData)
        return mock


@patch("openc3.script.API_SERVER", Proxy)
class TestMetadata(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_metadata(self):
        global gData
        meta = {"key1": "value1"}
        metadata_set(meta)
        # Color gets set if not set
        self.assertEqual(gData["color"], "#003784")
        json = metadata_all()
        self.assertEqual(meta, json["metadata"])
        json = metadata_get()
        self.assertEqual(meta, json["metadata"])
        meta["key1"] = "value2"
        metadata_update(meta, color="#123456")
        json = metadata_get()
        self.assertEqual(meta, json["metadata"])
        self.assertEqual("#123456", json["color"])

    def test_metadata_set(self):
        with self.assertRaisesRegex(RuntimeError, "metadata must be a dict"):
            metadata_set("hello")

        global gData
        meta = {"key1": "value1"}
        metadata_set(meta)
        # Color gets set if not set
        self.assertEqual(gData["color"], "#003784")
        metadata_set(meta, color="#123456")
        self.assertEqual(gData["color"], "#123456")
        # Set explicit start time
        start = datetime.now(openc3_timezone())
        metadata_set(meta, start=start.timestamp())
        # It would be nice to simply do this: start.strftime("%a %b %-d %H:%M:%S %Y")
        # But according to https://docs.python.org/3/library/time.html#time.asctime:
        # The day field is two characters long and is space padded if the day is a single digit
        # e.g.: 'Wed Jun  9 04:26:40 1993'.
        # So we have to create this format string in order to do the day formatting :-/
        formatted = "{dt:%a} {dt:%b} {day:2d} {dt:%H}:{dt:%M}:{dt:%S} {dt:%Y}".format(
            dt=start, day=start.day
        )
        self.assertEqual(gData["start"], formatted)

    def test_metadata_update(self):
        global gData
        meta = {"key1": "value1"}
        metadata_set(meta)

        meta["key1"] = "value2"
        metadata_update(meta)
        json = metadata_get()
        self.assertEqual(meta, json["metadata"])
        self.assertEqual("#003784", json["color"])

        # Set explicit color
        meta["key1"] = "value3"
        metadata_update(meta, color="#123456")
        json = metadata_get()
        self.assertEqual(meta, json["metadata"])
        self.assertEqual("#123456", json["color"])

        # Set explicit start time
        start = datetime.now(openc3_timezone())
        meta["key1"] = "value4"
        metadata_update(meta, start=start.timestamp())
        formatted = "{dt:%a} {dt:%b} {day:2d} {dt:%H}:{dt:%M}:{dt:%S} {dt:%Y}".format(
            dt=start, day=start.day
        )
        self.assertEqual(gData["start"], formatted)

    def test_metadata_input(self):
        with self.assertRaises(RuntimeError):
            metadata_input()
