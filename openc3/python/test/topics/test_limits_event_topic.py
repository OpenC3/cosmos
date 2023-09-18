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
from openc3.topics.limits_event_topic import LimitsEventTopic


class TestLimitsEventTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_writes_and_reads_limits_change_events(self):
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT",
            "packet_name": "PKT",
            "item_name": "ITEM",
            "old_limits_state": "GREEN",
            "new_limits_state": "YELLOW_LOW",
            "time_nsec": 123456789,
            "message": "test change",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        events = LimitsEventTopic.read(scope="DEFAULT")
        self.assertEqual(len(events), 1)
        self.assertRegex(events[0][0], r"\d+-0")
        self.assertEqual(events[0][1]["type"], "LIMITS_CHANGE")

        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0][0], "TGT")
        self.assertEqual(out[0][1], "PKT")
        self.assertEqual(out[0][2], "ITEM")
        self.assertEqual(out[0][3], "YELLOW_LOW")

    def test_removes_all_items_from_the_out_of_limits_list(self):
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "old_limits_state": "GREEN",
            "new_limits_state": "YELLOW_LOW",
            "time_nsec": 123456789,
            "message": "test change",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        event["packet_name"] = "PKT2"
        LimitsEventTopic.write(event, scope="DEFAULT")
        event["item_name"] = "ITEM2"
        LimitsEventTopic.write(event, scope="DEFAULT")
        event["target_name"] = "TGT2"
        event["packet_name"] = "PKT1"
        event["item_name"] = "ITEM1"
        LimitsEventTopic.write(event, scope="DEFAULT")
        event["item_name"] = "ITEM2"
        LimitsEventTopic.write(event, scope="DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 5)
        LimitsEventTopic.delete("TGT1", "PKT1", scope="DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 4)
        LimitsEventTopic.delete("TGT1", "PKT2", scope="DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 2)
        LimitsEventTopic.delete("TGT2", "PKT1", scope="DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 0)
