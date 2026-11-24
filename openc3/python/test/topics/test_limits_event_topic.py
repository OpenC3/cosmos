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
import unittest
from unittest.mock import *

from openc3.topics.limits_event_topic import LimitsEventTopic
from openc3.topics.topic import Topic
from test.test_helper import *


class TestLimitsEventTopicLimitsGroupItems(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_returns_none_for_an_undefined_group(self):
        self.assertIsNone(LimitsEventTopic.limits_group_items("NOPE", scope="DEFAULT"))

    def test_expands_nested_groups_of_any_target_into_their_items(self):
        Store.hset(
            "DEFAULT__limits_groups",
            "SYS__SPACECRAFT",
            json.dumps(
                [
                    ["INST", "LIMITS_GROUP", "THERMAL"],
                    ["INST", "HEALTH_STATUS", "VOLTS"],
                    ["SYS", "LIMITS_GROUP", "UNDEFINED"],
                ]
            ),
        )
        Store.hset(
            "DEFAULT__limits_groups",
            "INST__THERMAL",
            json.dumps(
                [
                    ["INST", "HEALTH_STATUS", "TEMP1"],
                    ["INST2", "HEALTH_STATUS", "TEMP2"],
                    ["INST", "HEALTH_STATUS", "VOLTS"],
                ]
            ),
        )
        # Same group name in another target isn't the child
        Store.hset("DEFAULT__limits_groups", "INST2__THERMAL", json.dumps([["INST2", "HEALTH_STATUS", "TEMP4"]]))
        self.assertEqual(
            LimitsEventTopic.limits_group_items("SYS__SPACECRAFT", scope="DEFAULT"),
            {"INST": {"HEALTH_STATUS": ["TEMP1", "VOLTS"]}, "INST2": {"HEALTH_STATUS": ["TEMP2"]}},
        )

    def test_stops_at_cycles(self):
        Store.hset(
            "DEFAULT__limits_groups",
            "INST__A",
            json.dumps([["INST", "LIMITS_GROUP", "B"], ["INST", "HEALTH_STATUS", "TEMP1"]]),
        )
        Store.hset(
            "DEFAULT__limits_groups",
            "INST__B",
            json.dumps([["INST", "LIMITS_GROUP", "A"], ["INST", "HEALTH_STATUS", "TEMP2"]]),
        )
        self.assertEqual(
            LimitsEventTopic.limits_group_items("INST__A", scope="DEFAULT"),
            {"INST": {"HEALTH_STATUS": ["TEMP2", "TEMP1"]}},
        )

    def test_skips_nested_groups_without_cascade(self):
        Store.hset(
            "DEFAULT__limits_groups",
            "SYS__SPACECRAFT",
            json.dumps([["INST", "LIMITS_GROUP", "THERMAL"], ["INST", "HEALTH_STATUS", "VOLTS"]]),
        )
        Store.hset("DEFAULT__limits_groups", "INST__THERMAL", json.dumps([["INST", "HEALTH_STATUS", "TEMP1"]]))
        self.assertEqual(
            LimitsEventTopic.limits_group_items("SYS__SPACECRAFT", scope="DEFAULT", cascade=False),
            {"INST": {"HEALTH_STATUS": ["VOLTS"]}},
        )
        # A group of only nested groups has no items of its own
        Store.hset("DEFAULT__limits_groups", "SYS__ALL", json.dumps([["SYS", "LIMITS_GROUP", "SPACECRAFT"]]))
        self.assertEqual(LimitsEventTopic.limits_group_items("SYS__ALL", scope="DEFAULT", cascade=False), {})


class TestLimitsEventTopicLimitsGroupKeys(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_returns_the_group_and_every_defined_group_below_it_with_cascade(self):
        Store.hset(
            "DEFAULT__limits_groups",
            "SYS__ALL",
            json.dumps(
                [
                    ["INST", "LIMITS_GROUP", "THERMAL"],
                    ["SYS", "LIMITS_GROUP", "UNDEFINED"],
                    ["INST", "HEALTH_STATUS", "TEMP1"],
                ]
            ),
        )
        Store.hset("DEFAULT__limits_groups", "INST__THERMAL", json.dumps([["INST", "LIMITS_GROUP", "INNER"]]))
        Store.hset("DEFAULT__limits_groups", "INST__INNER", json.dumps([["INST", "HEALTH_STATUS", "TEMP2"]]))
        self.assertEqual(
            sorted(LimitsEventTopic.limits_group_keys("SYS__ALL", scope="DEFAULT")),
            ["INST__INNER", "INST__THERMAL", "SYS__ALL"],
        )
        self.assertEqual(LimitsEventTopic.limits_group_keys("SYS__ALL", scope="DEFAULT", cascade=False), ["SYS__ALL"])
        self.assertEqual(LimitsEventTopic.limits_group_keys("NOPE", scope="DEFAULT"), [])
        self.assertEqual(LimitsEventTopic.limits_group_keys(None, scope="DEFAULT"), [])

    def test_write_only_disables_the_group_itself_without_cascade_and_otherwise_clears_the_flags(self):
        Store.hset("DEFAULT__limits_groups", "INST__THERMAL", json.dumps([["INST", "HEALTH_STATUS", "TEMP1"]]))
        Store.hset("DEFAULT__limits_groups", "INST__ALL", json.dumps([["INST", "LIMITS_GROUP", "THERMAL"]]))
        event = {
            "type": "LIMITS_GROUP_ENABLE_STATE",
            "target_name": "INST",
            "group_name": "ALL",
            "enabled": False,
            "cascade": False,
            "message": "TEST1",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(LimitsEventTopic.limits_group_settings("DEFAULT"), {"INST__ALL": {"enabled": False}})
        # ALL has no items of its own
        self.assertEqual(Store.hgetall("DEFAULT__current_limits_settings"), {})
        LimitsEventTopic.write({**event, "enabled": True}, scope="DEFAULT")
        self.assertEqual(LimitsEventTopic.limits_group_settings("DEFAULT"), {})

        # With cascade every item below is disabled so the groups follow their
        # members, and enabling one of them later shows in the groups
        LimitsEventTopic.write(event, scope="DEFAULT")
        LimitsEventTopic.write({**event, "group_name": "THERMAL"}, scope="DEFAULT")
        self.assertEqual(sorted(LimitsEventTopic.limits_group_settings("DEFAULT")), ["INST__ALL", "INST__THERMAL"])
        LimitsEventTopic.write({**event, "cascade": True}, scope="DEFAULT")
        self.assertEqual(LimitsEventTopic.limits_group_settings("DEFAULT"), {})
        settings = json.loads(Store.hget("DEFAULT__current_limits_settings", "INST__HEALTH_STATUS__TEMP1"))
        self.assertFalse(settings["enabled"])

    def test_delete_removes_a_deleted_targets_group_flags(self):
        Store.hset("DEFAULT__limits_group_settings", "INST__ALL", json.dumps({"enabled": False}))
        Store.hset("DEFAULT__limits_group_settings", "INST2__ALL", json.dumps({"enabled": False}))
        LimitsEventTopic.delete("INST", "HEALTH_STATUS", scope="DEFAULT")
        self.assertEqual(sorted(LimitsEventTopic.limits_group_settings("DEFAULT")), ["INST2__ALL", "INST__ALL"])
        LimitsEventTopic.delete("INST", scope="DEFAULT")
        self.assertEqual(list(LimitsEventTopic.limits_group_settings("DEFAULT")), ["INST2__ALL"])


class TestLimitsEventTopicFindLimitsGroup(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        for key in ["INST__TEMPS", "INST2__TEMPS", "INST__POWER", "LEGACY"]:
            Store.hset("DEFAULT__limits_groups", key, "[]")

    def test_finds_a_group_by_target_and_name(self):
        self.assertEqual(LimitsEventTopic.find_limits_group("inst2", "temps", "DEFAULT"), "INST2__TEMPS")
        with self.assertRaisesRegex(RuntimeError, "LIMITS_GROUP INST2 POWER undefined"):
            LimitsEventTopic.find_limits_group("INST2", "POWER", "DEFAULT")

    def test_finds_a_group_by_a_name_only_one_target_defines(self):
        self.assertEqual(LimitsEventTopic.find_limits_group(None, "power", "DEFAULT"), "INST__POWER")
        self.assertEqual(LimitsEventTopic.find_limits_group(None, "LEGACY", "DEFAULT"), "LEGACY")
        self.assertEqual(LimitsEventTopic.find_limits_group(None, "INST2__TEMPS", "DEFAULT"), "INST2__TEMPS")
        with self.assertRaisesRegex(RuntimeError, "LIMITS_GROUP NOPE undefined"):
            LimitsEventTopic.find_limits_group(None, "NOPE", "DEFAULT")
        with self.assertRaisesRegex(RuntimeError, "LIMITS_GROUP TEMPS is defined by targets INST, INST2"):
            LimitsEventTopic.find_limits_group(None, "TEMPS", "DEFAULT")

    def test_splits_keys(self):
        self.assertEqual(LimitsEventTopic.split_limits_group_key("INST__TEMPS"), ("INST", "TEMPS"))
        self.assertEqual(LimitsEventTopic.split_limits_group_key("LEGACY"), (None, "LEGACY"))

    def test_finds_the_group_of_an_event(self):
        event = {"target_name": "INST2", "group_name": "TEMPS"}
        self.assertEqual(LimitsEventTopic.limits_group_event_key(event, "DEFAULT"), "INST2__TEMPS")
        self.assertEqual(LimitsEventTopic.limits_group_event_key({"group_name": "POWER"}, "DEFAULT"), "INST__POWER")
        # Without a target the name is ambiguous
        self.assertIsNone(LimitsEventTopic.limits_group_event_key({"group_name": "TEMPS"}, "DEFAULT"))


class TestLimitsEventTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_read_returns_an_empty_list_with_no_events(self):
        # https://github.com/OpenC3/cosmos/issues/4293
        self.assertEqual(LimitsEventTopic.read(scope="DEFAULT"), [])

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

    def test_skips_current_limits_update_when_event_has_suppress_stored_true(self):
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT",
            "packet_name": "PKT",
            "item_name": "ITEM",
            "old_limits_state": "GREEN",
            "new_limits_state": "RED_HIGH",
            "time_nsec": 123456789,
            "message": "stored change",
            "suppress_stored": True,
        }
        LimitsEventTopic.write(event, scope="DEFAULT")

        # Event is still written to the stream
        events = LimitsEventTopic.read(scope="DEFAULT")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0][1]["type"], "LIMITS_CHANGE")
        self.assertTrue(events[0][1]["suppress_stored"])

        # But current_limits hash is NOT updated
        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 0)

    def test_updates_current_limits_when_event_has_no_suppress_stored_flag(self):
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT",
            "packet_name": "PKT",
            "item_name": "ITEM",
            "old_limits_state": "GREEN",
            "new_limits_state": "RED_HIGH",
            "time_nsec": 123456789,
            "message": "realtime change",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")

        out = LimitsEventTopic.out_of_limits(scope="DEFAULT")
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0][3], "RED_HIGH")

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

    def test_stores_zero_green_limits_in_current_limits_settings(self):
        event = {
            "type": "LIMITS_SETTINGS",
            "limits_set": "CUSTOM",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "red_low": -4.0,
            "yellow_low": -3.0,
            "yellow_high": 2.0,
            "red_high": 3.0,
            "green_low": 0.0,
            "green_high": 1.0,
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        settings = json.loads(Store.hget("DEFAULT__current_limits_settings", "TGT1__PKT1__ITEM1"))
        self.assertEqual(settings["CUSTOM"]["green_low"], 0.0)
        self.assertEqual(settings["CUSTOM"]["green_high"], 1.0)

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

    def test_writes_and_reads_limits_group_enable_state(self):
        # Existing settings for an item must be preserved
        Store.hset(
            "DEFAULT__current_limits_settings",
            "TGT1__PKT1__ITEM1",
            json.dumps({"persistence_setting": 3, "enabled": True}),
        )
        Store.hset(
            "DEFAULT__limits_groups",
            "GROUP",
            json.dumps([["TGT1", "PKT1", "ITEM1"], ["TGT1", "PKT1", "ITEM2"], ["TGT2", "PKT1", "ITEM1"]]),
        )
        event = {
            "type": "LIMITS_GROUP_ENABLE_STATE",
            "group_name": "GROUP",
            "enabled": False,
            "message": "TEST1",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")

        events = LimitsEventTopic.read("0-0", scope="DEFAULT")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0][1]["type"], "LIMITS_GROUP_ENABLE_STATE")
        self.assertEqual(events[0][1]["group_name"], "GROUP")
        self.assertNotIn("items", events[0][1])
        self.assertFalse(events[0][1]["enabled"])
        self.assertEqual(events[0][1]["message"], "TEST1")

        settings = {k.decode(): json.loads(v) for k, v in Store.hgetall("DEFAULT__current_limits_settings").items()}
        self.assertEqual(
            settings,
            {
                "TGT1__PKT1__ITEM1": {"persistence_setting": 3, "enabled": False},
                "TGT1__PKT1__ITEM2": {"enabled": False},
                "TGT2__PKT1__ITEM1": {"enabled": False},
            },
        )

    def test_clears_the_current_limits_state_of_items_a_limits_enable_state_event_disables(self):
        # After a decom restart the item has no local state so disabling it can't publish a
        # LIMITS_CHANGE, while current_limits still holds the state from before the restart
        Store.hset("DEFAULT__current_limits", "TGT1__PKT1__ITEM1", "RED_LOW")
        Store.hset("DEFAULT__current_limits", "TGT1__PKT1__ITEM2", "RED_LOW")
        event = {
            "type": "LIMITS_ENABLE_STATE",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": "ITEM1",
            "enabled": True,
            "time_nsec": 123456789,
            "message": "test",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT1__PKT1__ITEM1"), b"RED_LOW")
        event["enabled"] = False
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT1__PKT1__ITEM1"), b"")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT1__PKT1__ITEM2"), b"RED_LOW")

    def test_clears_the_current_limits_state_of_items_a_limits_group_enable_state_event_disables(self):
        Store.hset(
            "DEFAULT__limits_groups", "GROUP", json.dumps([["TGT1", "PKT1", "ITEM1"], ["TGT2", "PKT1", "ITEM1"]])
        )
        Store.hset("DEFAULT__current_limits", "TGT1__PKT1__ITEM1", "RED_LOW")
        Store.hset("DEFAULT__current_limits", "TGT2__PKT1__ITEM1", "YELLOW_HIGH")
        Store.hset("DEFAULT__current_limits", "TGT1__PKT1__ITEM2", "RED_LOW")
        event = {
            "type": "LIMITS_GROUP_ENABLE_STATE",
            "group_name": "GROUP",
            "enabled": True,
            "time_nsec": 123456789,
            "message": "test",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT1__PKT1__ITEM1"), b"RED_LOW")
        event["enabled"] = False
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT1__PKT1__ITEM1"), b"")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT2__PKT1__ITEM1"), b"")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT1__PKT1__ITEM2"), b"RED_LOW")

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
        with self.assertRaisesRegex(RuntimeError, "Limits set 'BLAH' does not exist"):
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

    def limits_change_event(self, i):
        return {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT1",
            "packet_name": "PKT1",
            "item_name": f"ITEM{i}",
            "old_limits_state": "GREEN",
            "new_limits_state": "RED_HIGH",
            "message": "TEST",
        }

    def test_events_trimmed_returns_false_when_no_events_after_the_offset_were_trimmed(self):
        LimitsEventTopic.write(self.limits_change_event(0), scope="DEFAULT")
        offset = Topic.get_last_offset("DEFAULT__openc3_limits_events")
        LimitsEventTopic.write(self.limits_change_event(1), scope="DEFAULT")
        self.assertFalse(LimitsEventTopic.events_trimmed(offset, "DEFAULT"))

    def test_events_trimmed_returns_true_when_events_after_the_offset_were_trimmed(self):
        LimitsEventTopic.write(self.limits_change_event(0), scope="DEFAULT")
        offset = Topic.get_last_offset("DEFAULT__openc3_limits_events")
        # More LIMITS_CHANGE events than the ~1000 entries the limits event stream keeps
        for i in range(1500):
            LimitsEventTopic.write(self.limits_change_event(i), scope="DEFAULT")
        self.assertTrue(LimitsEventTopic.events_trimmed(offset, "DEFAULT"))

    def test_events_trimmed_returns_false_when_the_stream_was_empty_or_there_is_no_offset(self):
        for i in range(1500):
            LimitsEventTopic.write(self.limits_change_event(i), scope="DEFAULT")
        self.assertFalse(LimitsEventTopic.events_trimmed("0-0", "DEFAULT"))
        self.assertFalse(LimitsEventTopic.events_trimmed(None, "DEFAULT"))

    def test_resync_system_reloads_the_limits_set_from_the_store(self):
        Store.hset("DEFAULT__limits_sets", mapping={"DEFAULT": "true", "TVAC": "false"})
        System.set_limits_set("TVAC", "DEFAULT")
        LimitsEventTopic.resync_system("DEFAULT")
        self.assertEqual(System.limits_set(), "DEFAULT")

    def test_process_event_updates_the_limits_set(self):
        self.assertEqual(System.limits_set(), "DEFAULT")
        LimitsEventTopic.process_event({"type": "LIMITS_SET", "set": "TVAC"}, "DEFAULT")
        self.assertEqual(System.limits_set(), "TVAC")

    def test_resync_system_reloads_item_settings_from_the_store(self):
        Store.hset("DEFAULT__current_limits_settings", "INST__HEALTH_STATUS__TEMP1", json.dumps({"enabled": False}))
        LimitsEventTopic.resync_system("DEFAULT")
        self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))

    def test_write_with_publish_false_updates_the_store_without_writing_to_the_stream(self):
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT",
            "packet_name": "PKT",
            "item_name": "ITEM",
            "old_limits_state": "GREEN",
            "new_limits_state": "RED_HIGH",
            "time_nsec": 123456789,
            "message": "test",
        }
        LimitsEventTopic.write(event, scope="DEFAULT", publish=False)
        self.assertEqual(Store.hget("DEFAULT__current_limits", "TGT__PKT__ITEM"), b"RED_HIGH")
        self.assertEqual(LimitsEventTopic.read(0, scope="DEFAULT"), [])

    def test_active_db_shards_caches_until_the_cache_times_out_or_is_cleared(self):
        now = [1000.0]
        target_reads = []

        class CountingStore:
            @staticmethod
            def hgetall(key):
                if key == "DEFAULT__openc3_targets":
                    target_reads.append(key)
                return Store.hgetall(key)

        with (
            patch("openc3.topics.limits_event_topic.time.monotonic", side_effect=lambda: now[0]),
            patch("openc3.topics.limits_event_topic.Store", CountingStore),
        ):
            self.assertEqual(LimitsEventTopic._active_db_shards("DEFAULT"), {0})
            set_target_db_shard("INST", 1)  # Clears the cache
            self.assertEqual(LimitsEventTopic._active_db_shards("DEFAULT"), {0, 1})
            Store.hset("DEFAULT__openc3_targets", "INST2", json.dumps({"name": "INST2", "db_shard": 2}))
            now[0] += LimitsEventTopic.ACTIVE_DB_SHARDS_CACHE_TIMEOUT - 1
            self.assertEqual(LimitsEventTopic._active_db_shards("DEFAULT"), {0, 1})  # Cached
            now[0] += 2
            self.assertEqual(LimitsEventTopic._active_db_shards("DEFAULT"), {0, 1, 2})
            self.assertEqual(len(target_reads), 3)

    def persist_disabled(self, *item_names):
        for item_name in item_names:
            Store.hset(
                "DEFAULT__current_limits_settings",
                f"INST__HEALTH_STATUS__{item_name}",
                json.dumps({"enabled": False}),
            )

    def test_sync_system_only_calls_the_callback_for_items_with_a_limits_state_to_clear(self):
        calls = []
        System.telemetry.set_limits_change_callback(
            lambda _packet, item, old_state, _value, _log: calls.append((item.name, old_state))
        )
        self.addCleanup(System.telemetry.set_limits_change_callback, None)
        self.persist_disabled("TEMP1", "TEMP2")
        System.telemetry.packet("INST", "HEALTH_STATUS").get_item("TEMP1").limits.state = "RED_LOW"

        LimitsEventTopic.sync_system("DEFAULT")
        self.assertEqual(calls, [("TEMP1", "RED_LOW")])
        # Re-syncing items that are already disabled must not fire again
        LimitsEventTopic.sync_system("DEFAULT")
        self.assertEqual(calls, [("TEMP1", "RED_LOW")])

    def test_sync_system_clears_the_current_limits_state_of_disabled_items(self):
        self.persist_disabled("TEMP1", "TEMP2")
        Store.hset("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP1", "RED_LOW")
        Store.hset("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP3", "RED_HIGH")
        LimitsEventTopic.sync_system("DEFAULT")
        self.assertEqual(Store.hget("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP1"), b"")
        self.assertFalse(Store.hexists("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP2"))
        self.assertEqual(Store.hget("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP3"), b"RED_HIGH")
        self.assertEqual(LimitsEventTopic.out_of_limits("DEFAULT"), [["INST", "HEALTH_STATUS", "TEMP3", "RED_HIGH"]])

    def test_resync_system_ignores_saved_numeric_settings_for_items_with_change_limits(self):
        limits = System.telemetry.packet("INST", "HEALTH_STATUS").get_item("TEMP1").limits
        limits.change_type = "SEQUENCE"
        try:
            numeric = {"red_low": -50.0, "yellow_low": -40.0, "yellow_high": 40.0, "red_high": 50.0}
            Store.hset(
                "DEFAULT__current_limits_settings",
                "INST__HEALTH_STATUS__TEMP1",
                json.dumps({"DEFAULT": numeric, "persistence_setting": 1, "enabled": False}),
            )
            Store.hset(
                "DEFAULT__current_limits_settings",
                "INST__HEALTH_STATUS__TEMP3",
                json.dumps({"DEFAULT": numeric, "persistence_setting": 2, "enabled": True}),
            )
            LimitsEventTopic.resync_system("DEFAULT")
            # Enabled state is still applied and other items still sync
            self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))
            self.assertEqual(
                list(System.limits.get("INST", "HEALTH_STATUS", "TEMP3")[1:7]), [2, True, -50.0, -40.0, 40.0, 50.0]
            )
        finally:
            limits.change_type = None

    def test_sync_system_thread_body_applies_a_limits_group_enable_state_event(self):
        LimitsEventTopic.sync_system_thread_body(scope="DEFAULT")  # Set the stream offset
        Store.hset("DEFAULT__limits_groups", "FIRST", json.dumps([["INST", "HEALTH_STATUS", "TEMP1"]]))
        event = {
            "type": "LIMITS_GROUP_ENABLE_STATE",
            "group_name": "FIRST",
            "enabled": False,
            "message": "TEST1",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        LimitsEventTopic.sync_system_thread_body(scope="DEFAULT")
        self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))

    def test_applies_a_limits_group_enable_state_event_without_cascade_to_the_groups_own_items(self):
        Store.hset("DEFAULT__limits_groups", "INST__THERMAL", json.dumps([["INST", "HEALTH_STATUS", "TEMP1"]]))
        Store.hset(
            "DEFAULT__limits_groups",
            "INST__ALL",
            json.dumps([["INST", "LIMITS_GROUP", "THERMAL"], ["INST", "HEALTH_STATUS", "TEMP3"]]),
        )
        event = {
            "type": "LIMITS_GROUP_ENABLE_STATE",
            "target_name": "INST",
            "group_name": "ALL",
            "enabled": False,
            "cascade": False,
            "message": "TEST1",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(
            list(Store.hgetall("DEFAULT__current_limits_settings").keys()), [b"INST__HEALTH_STATUS__TEMP3"]
        )
        LimitsEventTopic.process_event(json.loads(json.dumps(event)), scope="DEFAULT")
        self.assertTrue(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))
        self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP3"))

    def test_process_event_applies_the_rest_of_a_group_when_one_item_fails(self):
        original_disable = System.limits.disable

        def disable(target_name, packet_name, item_name):
            if item_name == "TEMP1":
                raise RuntimeError("boom")
            original_disable(target_name, packet_name, item_name)

        Store.hset(
            "DEFAULT__limits_groups",
            "FIRST",
            json.dumps([["INST", "HEALTH_STATUS", "TEMP1"], ["INST", "HEALTH_STATUS", "TEMP3"]]),
        )
        event = {
            "type": "LIMITS_GROUP_ENABLE_STATE",
            "group_name": "FIRST",
            "enabled": False,
        }
        with patch.object(System.limits, "disable", side_effect=disable):
            LimitsEventTopic.process_event(event, "DEFAULT")
        self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP3"))

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
                LimitsEventTopic.write(
                    {"type": "LIMITS_SET", "set": "TVAC", "message": "Limits Set"},
                    scope="DEFAULT",
                )
                getattr(LimitsEventTopic, method)(scope="DEFAULT")
                self.assertEqual(System.limits_set(), "TVAC")

    def test_sync_limits_group_enable_state(self):
        for method in ["sync_system", "sync_system_thread_body"]:
            # Make initial call to set the stream offset so we don't miss anything
            getattr(LimitsEventTopic, method)(scope="DEFAULT")

            Store.hset(
                "DEFAULT__limits_groups",
                "FIRST",
                json.dumps(
                    [
                        ["INST", "HEALTH_STATUS", "TEMP1"],
                        ["INST", "HEALTH_STATUS", "TEMP3"],
                        ["NOTGT", "NOPKT", "NOITEM"],  # Targets not in this System are ignored
                    ]
                ),
            )
            event = {
                "type": "LIMITS_GROUP_ENABLE_STATE",
                "group_name": "FIRST",
                "enabled": False,
                "message": "TEST1",
            }
            LimitsEventTopic.write(event, scope="DEFAULT")
            getattr(LimitsEventTopic, method)(scope="DEFAULT")
            self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))
            self.assertTrue(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP2"))
            self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP3"))

            event["enabled"] = True
            event["message"] = "TEST2"
            LimitsEventTopic.write(event, scope="DEFAULT")
            getattr(LimitsEventTopic, method)(scope="DEFAULT")
            self.assertTrue(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))
            self.assertTrue(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP3"))

    def test_sync_limits_group_enable_state_with_and_without_cascade(self):
        for method in ["sync_system", "sync_system_thread_body"]:
            with self.subTest(method=method):
                # Make initial call to set the stream offset so we don't miss anything
                getattr(LimitsEventTopic, method)(scope="DEFAULT")
                Store.hset("DEFAULT__limits_groups", "INST__THERMAL", json.dumps([["INST", "HEALTH_STATUS", "TEMP1"]]))
                Store.hset(
                    "DEFAULT__limits_groups",
                    "INST__ALL",
                    json.dumps([["INST", "LIMITS_GROUP", "THERMAL"], ["INST", "HEALTH_STATUS", "TEMP3"]]),
                )
                event = {
                    "type": "LIMITS_GROUP_ENABLE_STATE",
                    "target_name": "INST",
                    "group_name": "ALL",
                    "enabled": False,
                    "message": "TEST1",
                }
                LimitsEventTopic.write(event, scope="DEFAULT")
                getattr(LimitsEventTopic, method)(scope="DEFAULT")
                self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))
                self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP3"))

                LimitsEventTopic.write({**event, "enabled": True, "cascade": False}, scope="DEFAULT")
                getattr(LimitsEventTopic, method)(scope="DEFAULT")
                self.assertFalse(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))
                self.assertTrue(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP3"))
                settings = {
                    key.decode(): json.loads(value)["enabled"]
                    for key, value in Store.hgetall("DEFAULT__current_limits_settings").items()
                }
                self.assertEqual(settings["INST__HEALTH_STATUS__TEMP1"], False)
                self.assertEqual(settings["INST__HEALTH_STATUS__TEMP3"], True)

                LimitsEventTopic.write({**event, "enabled": True, "cascade": True}, scope="DEFAULT")
                getattr(LimitsEventTopic, method)(scope="DEFAULT")
                self.assertTrue(System.limits.enabled("INST", "HEALTH_STATUS", "TEMP1"))


class TestLimitsEventTopicMultipleDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        # INST is installed on db_shard 1 while SYSTEM stays on db_shard 0
        setup_system(db_shards={"INST": 1})

    def test_writes_events_to_every_target_db_shard(self):
        # Each decom microservice reads limits events inline from its own db_shard
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "INST",
            "packet_name": "HEALTH_STATUS",
            "item_name": "TEMP1",
            "old_limits_state": "GREEN",
            "new_limits_state": "YELLOW_LOW",
            "time_nsec": 123456789,
            "message": "test change",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        self.assertEqual(shard_redis(0).xlen("DEFAULT__openc3_limits_events"), 1)
        self.assertEqual(shard_redis(1).xlen("DEFAULT__openc3_limits_events"), 1)
        self.assertFalse(shard_redis(2).exists("DEFAULT__openc3_limits_events"))

    def test_only_uses_the_db_shards_cache_for_limits_change_events(self):
        self.assertEqual(LimitsEventTopic._active_db_shards("DEFAULT"), {0, 1})  # Fills the cache
        # Another process installs a target on a new db_shard, which can't clear this process's cache
        Store.instance(db_shard=0).hset(
            "DEFAULT__openc3_targets", "INST2", json.dumps({"name": "INST2", "db_shard": 2})
        )

        change = {
            "type": "LIMITS_CHANGE",
            "target_name": "INST",
            "packet_name": "HEALTH_STATUS",
            "item_name": "TEMP1",
            "old_limits_state": "GREEN",
            "new_limits_state": "RED_HIGH",
            "time_nsec": 123456789,
            "message": "test change",
        }
        LimitsEventTopic.write(change, scope="DEFAULT")
        self.assertFalse(shard_redis(2).exists("DEFAULT__openc3_limits_events"))  # Cached

        # Events that change decom limits must reach the decom on the new db_shard
        enable = {
            "type": "LIMITS_ENABLE_STATE",
            "target_name": "INST",
            "packet_name": "HEALTH_STATUS",
            "item_name": "TEMP1",
            "enabled": False,
            "time_nsec": 123456789,
            "message": "test enable",
        }
        LimitsEventTopic.write(enable, scope="DEFAULT")
        self.assertEqual(shard_redis(2).xlen("DEFAULT__openc3_limits_events"), 1)

        # The lookup refreshed the cache for later LIMITS_CHANGE events
        LimitsEventTopic.write(change, scope="DEFAULT")
        self.assertEqual(shard_redis(2).xlen("DEFAULT__openc3_limits_events"), 2)
        self.assertEqual(shard_redis(0).xlen("DEFAULT__openc3_limits_events"), 3)
