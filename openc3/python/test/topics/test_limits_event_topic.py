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

import time
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.topics.limits_event_topic import LimitsEventTopic


class TestLimitsEventTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

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

    def test_writes_and_reads_limits_settings_events(self):
        event = {
            "type": "LIMITS_SETTINGS",
            "limits_set": "CUSTOM",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "red_low": -50.0,
            "yellow_low": -40.0,
            "yellow_high": 40.0,
            "red_high": 50.0,
            "persistence": 1,
            "enabled": False,
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        event = {
            "type": "LIMITS_SETTINGS",
            "limits_set": "CUSTOM",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "red_low": -50.0,
            "yellow_low": -40.0,
            "yellow_high": 40.0,
            "red_high": 50.0,
            "green_low": -10.0,
            "green_high": 10.0,
            "persistence": 5,
            "enabled": True,
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        events = LimitsEventTopic.read("0-0", scope="DEFAULT")
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0][1]["type"], "LIMITS_SETTINGS")
        self.assertEqual(events[0][1]["limits_set"], "CUSTOM")
        self.assertEqual(events[0][1]["target_name"], "TGT1")
        self.assertEqual(events[0][1]["packet_name"], "PKT1")
        self.assertEqual(events[0][1]["item_name"], "ITEM1")
        self.assertEqual(events[0][1]["red_low"], (-50.0))
        self.assertEqual(events[0][1]["yellow_low"], (-40.0))
        self.assertEqual(events[0][1]["yellow_high"], 40.0)
        self.assertEqual(events[0][1]["red_high"], 50.0)
        self.assertEqual(events[0][1]["persistence"], 1)
        self.assertEqual(events[0][1]["enabled"], False)

        self.assertEqual(events[1][1]["type"], "LIMITS_SETTINGS")
        self.assertEqual(events[1][1]["limits_set"], "CUSTOM")
        self.assertEqual(events[1][1]["target_name"], "TGT1")
        self.assertEqual(events[1][1]["packet_name"], "PKT1")
        self.assertEqual(events[1][1]["item_name"], "ITEM1")
        self.assertEqual(events[1][1]["red_low"], -50.0)
        self.assertEqual(events[1][1]["yellow_low"], -40.0)
        self.assertEqual(events[1][1]["yellow_high"], 40.0)
        self.assertEqual(events[1][1]["red_high"], 50.0)
        self.assertEqual(events[1][1]["green_low"], -10.0)
        self.assertEqual(events[1][1]["green_high"], 10.0)
        self.assertEqual(events[1][1]["persistence"], 5)
        self.assertEqual(events[1][1]["enabled"], True)

    def test_writes_and_reads_limits_event_state(self):
        event = {
            "type": "LIMITS_ENABLE_STATE",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "enabled": True,
            "message": "TEST1",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        event = {
            "type": "LIMITS_ENABLE_STATE",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "enabled": False,
            "message": "TEST2",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        events = LimitsEventTopic.read("0-0", scope="DEFAULT")
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0][1]["type"], "LIMITS_ENABLE_STATE")
        self.assertEqual(events[0][1]["target_name"], "TGT1")
        self.assertEqual(events[0][1]["packet_name"], "PKT1")
        self.assertEqual(events[0][1]["item_name"], "ITEM1")
        self.assertEqual(events[0][1]["enabled"], True)
        self.assertEqual(events[0][1]["message"], "TEST1")

        self.assertEqual(events[1][1]["type"], "LIMITS_ENABLE_STATE")
        self.assertEqual(events[1][1]["target_name"], "TGT1")
        self.assertEqual(events[1][1]["packet_name"], "PKT1")
        self.assertEqual(events[1][1]["item_name"], "ITEM1")
        self.assertEqual(events[1][1]["enabled"], False)
        self.assertEqual(events[1][1]["message"], "TEST2")

    def test_writes_and_reads_limits_set(self):
        set = LimitsEventTopic.current_set(scope="DEFAULT")
        self.assertEqual(set, "DEFAULT")

        event = {
            "type": "LIMITS_SETTINGS",
            "limits_set": "TVAC",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "red_low": -50.0,
            "yellow_low": -40.0,
            "yellow_high": 40.0,
            "red_high": 50.0,
            "persistence": 1,
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        event = {
            "type": "LIMITS_SET",
            "set": "TVAC",
            "message": "Limits Set",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        events = LimitsEventTopic.read(scope="DEFAULT")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0][1]["type"], "LIMITS_SET")
        self.assertEqual(events[0][1]["message"], "Limits Set")

        set = LimitsEventTopic.current_set(scope="DEFAULT")
        self.assertEqual(set, "TVAC")

        sets = LimitsEventTopic.sets(scope="DEFAULT")
        self.assertEqual(sets["TVAC"], "true")
        self.assertEqual(sets["DEFAULT"], "false")

    def test_raise_limits_set_when_set_does_not_exist(self):
        with self.assertRaisesRegex(RuntimeError, "Set 'BLAH' does not exist"):
            event = {"type": "LIMITS_SET", "set": "BLAH", "message": "Limits Set"}
            LimitsEventTopic.write(event, scope="DEFAULT")

    def test_raise_on_unknown_types(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid limits event type 'BLAH'"):
            LimitsEventTopic.write({"type": "BLAH"}, scope="DEFAULT")

    def test_removes_individual_items_from_the_out_of_limits_list(self):
        event = {
            "type": "LIMITS_SETTINGS",
            "limits_set": "DEFAULT",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "red_low": -50.0,
            "yellow_low": -40.0,
            "yellow_high": 40.0,
            "red_high": 50.0,
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
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
        settings = Store.hgetall("DEFAULT__current_limits_settings")
        self.assertEqual(list(settings.keys()), [b"TGT1__PKT1__ITEM1"])

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

    def test_removes_all_items_from_the_out_of_limits_list(self):
        event = {
            "type": "LIMITS_SETTINGS",
            "limits_set": "DEFAULT",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "red_low": -50.0,
            "yellow_low": -40.0,
            "yellow_high": 40.0,
            "red_high": 50.0,
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
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
        settings = Store.hgetall("DEFAULT__current_limits_settings")
        self.assertEqual(list(settings.keys()), [b"TGT1__PKT1__ITEM1"])

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
        LimitsEventTopic.delete("TGT1", scope="DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 2)
        LimitsEventTopic.delete("TGT2", scope="DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 0)

    def test_sync(self):
        for method in ["sync_system", "sync_system_thread_body"]:
            # Make initial call to set the stream offset so we don't miss anything
            getattr(LimitsEventTopic, method)(scope="DEFAULT")

            event = {
                "type": "LIMITS_SETTINGS",
                "limits_set": "DEFAULT",
                "target_name": "INST",
                "packet_name": "HEALTH_STATUS",
                "item_name": "TEMP1",
                "red_low": -80.0,
                "yellow_low": -70.0,
                "yellow_high": 60.0,
                "red_high": 80.0,
                "green_low": -20.0,
                "green_high": 20.0,
                "enabled": True,
                "persistence": 1,
            }
            LimitsEventTopic.write(event, scope="DEFAULT")
            getattr(LimitsEventTopic, method)(scope="DEFAULT")

            event = {
                "type": "LIMITS_ENABLE_STATE",
                "target_name": "INST",
                "packet_name": "HEALTH_STATUS",
                "item_name": "TEMP1",
                "enabled": False,
                "message": "TEST1",
            }
            LimitsEventTopic.write(event, scope="DEFAULT")
            getattr(LimitsEventTopic, method)(scope="DEFAULT")
            self.assertEqual(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"), False)

            event = {
                "type": "LIMITS_ENABLE_STATE",
                "target_name": "INST",
                "packet_name": "HEALTH_STATUS",
                "item_name": "TEMP1",
                "enabled": True,
                "message": "TEST1",
            }
            LimitsEventTopic.write(event, scope="DEFAULT")
            getattr(LimitsEventTopic, method)(scope="DEFAULT")
            self.assertEqual(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"), True)

            limits = System.limits.get("INST", "HEALTH_STATUS", "TEMP1")
            self.assertEqual(limits[0], "DEFAULT")
            self.assertEqual(limits[1], 1)
            self.assertEqual(limits[2], True)
            self.assertEqual(limits[3], -80.0)
            self.assertEqual(limits[4], -70.0)
            self.assertEqual(limits[5], 60.0)
            self.assertEqual(limits[6], 80.0)
            self.assertEqual(limits[7], -20.0)
            self.assertEqual(limits[8], 20.0)

            event = {
                "type": "LIMITS_SETTINGS",
                "limits_set": "DEFAULT",
                "target_name": "INST",
                "packet_name": "HEALTH_STATUS",
                "item_name": "TEMP1",
                "red_low": -50.0,
                "yellow_low": -40.0,
                "yellow_high": 40.0,
                "red_high": 50.0,
                "persistence": 5,
            }
            LimitsEventTopic.write(event, scope="DEFAULT")
            getattr(LimitsEventTopic, method)(scope="DEFAULT")
            limits = System.limits.get("INST", "HEALTH_STATUS", "TEMP1")
            self.assertEqual(limits[0], "DEFAULT")
            self.assertEqual(limits[1], 5)
            self.assertEqual(limits[2], True)
            self.assertEqual(limits[3], -50.0)
            self.assertEqual(limits[4], -40.0)
            self.assertEqual(limits[5], 40.0)
            self.assertEqual(limits[6], 50.0)
            self.assertEqual(limits[7], None)
            self.assertEqual(limits[8], None)

            if method == "sync_system_thread_body":
                event = {
                    "type": "LIMITS_SETTINGS",
                    "limits_set": "TVAC",
                    "target_name": "TGT1",
                    "packet_name": "PKT1",
                    "item_name": "ITEM1",
                    "red_low": -50.0,
                    "yellow_low": -40.0,
                    "yellow_high": 40.0,
                    "red_high": 50.0,
                    "persistence": 1,
                }
                LimitsEventTopic.write(event, scope="DEFAULT")
                LimitsEventTopic.write({"type": "LIMITS_SET", "set": "TVAC", "message": "Limits Set"}, scope="DEFAULT")
                getattr(LimitsEventTopic, method)(scope="DEFAULT")
                self.assertEqual(System.limits_set(), "TVAC")
