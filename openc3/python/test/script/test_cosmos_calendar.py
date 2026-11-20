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
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

import requests

import openc3.script
from openc3.script.cosmos_calendar import (
    create_timeline_activity,
    delete_timeline_activity,
    get_timeline_activities,
    update_timeline_activity,
)


class TestCosmosCalendar(unittest.TestCase):
    def setUp(self):
        self.orig_api_server = openc3.script.API_SERVER
        self.api_server = Mock()
        openc3.script.API_SERVER = self.api_server
        response = requests.Response()
        response.status_code = 200
        response._content = b"[]"
        self.api_server.request.return_value = response

    def tearDown(self):
        openc3.script.API_SERVER = self.orig_api_server

    def url(self):
        return self.api_server.request.call_args.args[1]

    def test_get_timeline_activities_joins_query_parameters(self):
        get_timeline_activities("TL", start=1700000000, stop=1800000000, limit=5)
        self.assertEqual(self.url(), "/openc3-api/timeline/TL/activities?start=1700000000&stop=1800000000&limit=5")
        get_timeline_activities("TL", limit=5)
        self.assertEqual(self.url(), "/openc3-api/timeline/TL/activities?limit=5")
        get_timeline_activities("TL")
        self.assertEqual(self.url(), "/openc3-api/timeline/TL/activities")

    def test_delete_timeline_activity_recurring(self):
        delete_timeline_activity("TL", 100, "UUID")
        self.assertEqual(self.url(), "/openc3-api/timeline/TL/activity/100/UUID")
        # With recurring the given (recurring group) UUID is sent unchanged
        delete_timeline_activity("TL", 100, "GROUP-UUID", recurring=True)
        self.assertEqual(self.url(), "/openc3-api/timeline/TL/activity/100/GROUP-UUID?recurring=true")

    def test_delete_timeline_activity_positional_scope(self):
        # The fourth positional argument is still scope and does not turn on recurring
        delete_timeline_activity("TL", 100, "UUID", "OTHER")
        self.assertEqual(self.url(), "/openc3-api/timeline/TL/activity/100/UUID")
        self.assertEqual(self.api_server.request.call_args.kwargs["scope"], "OTHER")
        delete_timeline_activity("TL", 100, "UUID", "OTHER", recurring=True)
        self.assertEqual(self.url(), "/openc3-api/timeline/TL/activity/100/UUID?recurring=true")
        self.assertEqual(self.api_server.request.call_args.kwargs["scope"], "OTHER")

    def test_activity_times_are_converted_to_utc(self):
        tz = timezone(timedelta(hours=-7))
        start = datetime(2030, 1, 1, 12, 0, tzinfo=tz)
        stop = start + timedelta(hours=1)
        create_timeline_activity("TL", kind="reserve", start=start, stop=stop)
        data = self.api_server.request.call_args.kwargs["data"]
        self.assertEqual(data["start"], "2030-01-01T19:00:00.000000Z")
        self.assertEqual(data["stop"], "2030-01-01T20:00:00.000000Z")

        update_timeline_activity("TL", 100, kind="reserve", start=start, stop=stop, uuid="UUID")
        data = self.api_server.request.call_args.kwargs["data"]
        self.assertEqual(data["start"], "2030-01-01T19:00:00.000000Z")

    def test_naive_activity_times_are_treated_as_utc(self):
        start = datetime(2030, 1, 1, 12, 0)
        create_timeline_activity("TL", kind="reserve", start=start, stop=start + timedelta(hours=1))
        data = self.api_server.request.call_args.kwargs["data"]
        self.assertEqual(data["start"], "2030-01-01T12:00:00.000000Z")
        self.assertEqual(data["stop"], "2030-01-01T13:00:00.000000Z")


if __name__ == "__main__":
    unittest.main()
