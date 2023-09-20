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

from datetime import datetime, timezone
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.models.notification_model import NotificationModel
from openc3.utilities.time import to_nsec_from_epoch


class TestNotificationModel(unittest.TestCase):
    def test_returns_a_notification(self):
        notification = NotificationModel(
            time=to_nsec_from_epoch(datetime.now(timezone.utc)),
            severity="INFO",
            url="/tools/limitsmonitor",
            title="test",
            body="foobar",
        )
        self.assertIsNotNone(notification.time)
        self.assertEqual(notification.severity, ("INFO"))
        self.assertEqual(notification.url, ("/tools/limitsmonitor"))
        self.assertEqual(notification.title, ("test"))
        self.assertEqual(notification.body, ("foobar"))


class AsJson(unittest.TestCase):
    def test_returns_a_hash(self):
        notification = NotificationModel(
            time=to_nsec_from_epoch(datetime.now(timezone.utc)),
            severity="INFO",
            url="/tools/limitsmonitor",
            title="test",
            body="foobar",
        )
        hash = notification.as_json()
        self.assertIsNotNone(hash["time"])
        self.assertEqual(hash["severity"], ("INFO"))
        self.assertEqual(hash["url"], ("/tools/limitsmonitor"))
        self.assertEqual(hash["title"], ("test"))
        self.assertEqual(hash["body"], ("foobar"))
