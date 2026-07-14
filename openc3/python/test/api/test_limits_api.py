# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import contextlib
import threading
import time
import unittest
from datetime import datetime, timezone
from unittest.mock import *

from openc3.api.limits_api import *
from openc3.api.tlm_api import *
from openc3.microservices.decom_microservice import DecomMicroservice
from openc3.models.microservice_model import MicroserviceModel
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.utilities.time import formatted
from test.test_helper import *


class TestLimitsApi(unittest.TestCase):
    @patch("openc3.microservices.microservice.System")
    def setUp(self, system):
        redis = mock_redis(self)
        setup_system()

        orig_xread = redis.xread

        # Override xread to ignore the block keyword
        def xread_side_effect(*args, **kwargs):
            if "block" in kwargs:
                kwargs.pop("block")
            result = None
            with contextlib.suppress(Exception):
                result = orig_xread(*args, **kwargs)

            # # Create a slight delay to simulate the blocking call
            if result and len(result) == 0:
                time.sleep(0.01)
            return result

        redis.xread = Mock()
        redis.xread.side_effect = xread_side_effect

        # Store Limits Groups
        for group, items in System.limits.groups().items():
            Store.hset("DEFAULT__limits_groups", group, json.dumps(items))

        model = TargetModel(name="INST", scope="DEFAULT")
        model.create()
        model = TargetModel(name="SYSTEM", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(
            name="DEFAULT__DECOM__INST_INT",
            scope="DEFAULT",
            topics=["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"],
            target_names=["INST"],
        )
        model.create()
        self.dm = DecomMicroservice("DEFAULT__DECOM__INST_INT")
        self.dm_thread = threading.Thread(target=self.dm.run)
        self.dm_thread.start()
        time.sleep(0.001)  # Allow the threads to run

    def tearDown(self):
        self.dm.shutdown()
        time.sleep(0.001)

    def test_get_limits_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            get_limits("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_get_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_limits("INST", "BLAH", "TEMP1")

    def test_get_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"):
            get_limits("INST", "HEALTH_STATUS", "BLAH")

    def test_gets_limits_for_an_item(self):
        self.assertEqual(
            get_limits("INST", "HEALTH_STATUS", "TEMP1"),
            {
                "DEFAULT": [-80.0, -70.0, 60.0, 80.0, -20.0, 20.0],
                "TVAC": [-80.0, -30.0, 30.0, 80.0],
            },
        )

    def test_gets_limits_for_a_latest_item(self):
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc)
        packet.stored = False
        packet.check_limits()
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)  # Allow the write to happen
        packet.received_time = datetime.now(timezone.utc)
        packet.check_limits()
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)  # Allow the write to happen

        self.assertEqual(
            get_limits("INST", "LATEST", "TEMP1"),
            {
                "DEFAULT": [-80.0, -70.0, 60.0, 80.0, -20.0, 20.0],
                "TVAC": [-80.0, -30.0, 30.0, 80.0],
            },
        )

    def test_set_limits_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            set_limits("BLAH", "HEALTH_STATUS", "TEMP1", 0.0, 10.0, 20.0, 30.0)

    def test_set_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            set_limits("INST", "BLAH", "TEMP1", 0.0, 10.0, 20.0, 30.0)

    def test_set_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"):
            set_limits("INST", "HEALTH_STATUS", "BLAH", 0.0, 10.0, 20.0, 30.0)

    def test_set_limits_creates_a_custom_limits_set(self):
        set_limits("INST", "HEALTH_STATUS", "TEMP1", 0.0, 10.0, 20.0, 30.0)
        self.assertEqual(
            get_limits("INST", "HEALTH_STATUS", "TEMP1")["CUSTOM"],
            ([0.0, 10.0, 20.0, 30.0]),
        )

    def test_set_limits_complains_about_invalid_limits(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid limits specified"):
            set_limits("INST", "HEALTH_STATUS", "TEMP1", 2.0, 1.0, 4.0, 5.0)
        with self.assertRaisesRegex(RuntimeError, "Invalid limits specified"):
            set_limits("INST", "HEALTH_STATUS", "TEMP1", 0.0, 1.0, 2.0, 3.0, 4.0, 5.0)

    def test_set_limits_overrides_existing_limits(self):
        item = get_item("INST", "HEALTH_STATUS", "TEMP1")
        self.assertNotEqual(item["limits"]["persistence_setting"], 10)
        self.assertTrue(item["limits"]["enabled"])
        set_limits(
            "INST",
            "HEALTH_STATUS",
            "TEMP1",
            0.0,
            1.0,
            4.0,
            5.0,
            2.0,
            3.0,
            "DEFAULT",
            10,
            False,
        )
        item = get_item("INST", "HEALTH_STATUS", "TEMP1")
        self.assertEqual(item["limits"]["persistence_setting"], (10))
        self.assertIsNone(item["limits"].get("enabled"))
        self.assertEqual(
            item["limits"]["DEFAULT"],
            {
                "red_low": 0.0,
                "yellow_low": 1.0,
                "yellow_high": 4.0,
                "red_high": 5.0,
                "green_low": 2.0,
                "green_high": 3.0,
            },
        )
        # Verify it also works with symbols for the set
        set_limits(
            "INST",
            "HEALTH_STATUS",
            "TEMP1",
            1.0,
            2.0,
            5.0,
            6.0,
            3.0,
            4.0,
            "DEFAULT",
            10,
            False,
        )
        item = get_item("INST", "HEALTH_STATUS", "TEMP1")
        self.assertEqual(item["limits"]["persistence_setting"], (10))
        self.assertIsNone(item["limits"].get("enabled"))
        self.assertEqual(
            item["limits"]["DEFAULT"],
            {
                "red_low": 1.0,
                "yellow_low": 2.0,
                "yellow_high": 5.0,
                "red_high": 6.0,
                "green_low": 3.0,
                "green_high": 4.0,
            },
        )

    def test_set_state_color_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            set_state_color("BLAH", "HEALTH_STATUS", "GROUND1STATUS", "CONNECTED", "RED")

    def test_set_state_color_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            set_state_color("INST", "BLAH", "GROUND1STATUS", "CONNECTED", "RED")

    def test_set_state_color_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"):
            set_state_color("INST", "HEALTH_STATUS", "BLAH", "CONNECTED", "RED")

    def test_set_state_color_complains_about_non_existant_states(self):
        with self.assertRaisesRegex(RuntimeError, "State 'BLAH' does not exist"):
            set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "BLAH", "RED")

    def test_set_state_color_complains_about_invalid_colors(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid state color PURPLE"):
            set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "CONNECTED", "PURPLE")

    def test_set_state_color_changes_the_color_of_a_state(self):
        item = get_item("INST", "HEALTH_STATUS", "GROUND1STATUS")
        self.assertEqual(item["states"]["CONNECTED"]["color"], "GREEN")
        set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "CONNECTED", "RED")
        item = get_item("INST", "HEALTH_STATUS", "GROUND1STATUS")
        self.assertEqual(item["states"]["CONNECTED"]["color"], "RED")
        self.assertTrue(item["limits"]["enabled"])

    def test_set_state_color_accepts_lowercase_names_and_colors(self):
        set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "connected", "yellow")
        item = get_item("INST", "HEALTH_STATUS", "GROUND1STATUS")
        self.assertEqual(item["states"]["CONNECTED"]["color"], "YELLOW")

    def test_set_state_color_writes_a_limits_state_color_event(self):
        set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "UNAVAILABLE", "RED")
        event = get_limits_events()[-1][1]
        self.assertEqual(event["type"], "LIMITS_STATE_COLOR")
        self.assertEqual(event["target_name"], "INST")
        self.assertEqual(event["packet_name"], "HEALTH_STATUS")
        self.assertEqual(event["item_name"], "GROUND1STATUS")
        self.assertEqual(event["state_name"], "UNAVAILABLE")
        self.assertEqual(event["color"], "RED")

    def test_set_state_color_clears_the_color_of_a_state_when_passed_none(self):
        set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "CONNECTED", "RED")
        item = get_item("INST", "HEALTH_STATUS", "GROUND1STATUS")
        self.assertEqual(item["states"]["CONNECTED"]["color"], "RED")
        set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "CONNECTED", None)
        item = get_item("INST", "HEALTH_STATUS", "GROUND1STATUS")
        self.assertNotIn("color", item["states"]["CONNECTED"])

    def test_set_state_color_does_not_validate_the_color_when_clearing(self):
        # Should not raise
        set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "CONNECTED", None)

    def test_set_state_color_complains_about_non_existant_states_when_clearing(self):
        with self.assertRaisesRegex(RuntimeError, "State 'BLAH' does not exist"):
            set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "BLAH", None)

    def test_set_state_color_writes_a_limits_state_color_event_with_none_when_clearing(self):
        set_state_color("INST", "HEALTH_STATUS", "GROUND1STATUS", "UNAVAILABLE", None)
        event = get_limits_events()[-1][1]
        self.assertEqual(event["type"], "LIMITS_STATE_COLOR")
        self.assertEqual(event["state_name"], "UNAVAILABLE")
        self.assertIsNone(event["color"])

    def test_get_limits_groups_returns_all_the_limits_groups(self):
        self.assertEqual(
            get_limits_groups(),
            {
                "FIRST": [
                    ["INST", "HEALTH_STATUS", "TEMP1"],
                    ["INST", "HEALTH_STATUS", "TEMP3"],
                ],
                "SECOND": [
                    ["INST", "HEALTH_STATUS", "TEMP2"],
                    ["INST", "HEALTH_STATUS", "TEMP4"],
                ],
            },
        )

    def test_enable_limits_groups_complains_about_undefined_limits_groups(self):
        with self.assertRaisesRegex(
            RuntimeError,
            "LIMITS_GROUP MINE undefined. Ensure your telemetry definition contains the line: LIMITS_GROUP MINE",
        ):
            enable_limits_group("MINE")

    def test_enable_limits_groups_enables_limits_for_all_items_in_the_group(self):
        disable_limits("INST", "HEALTH_STATUS", "TEMP1")
        disable_limits("INST", "HEALTH_STATUS", "TEMP3")
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP3"))
        enable_limits_group("FIRST")
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP3"))

    def test_disable_limits_groups_complains_about_undefined_limits_groups(self):
        with self.assertRaisesRegex(
            RuntimeError,
            "LIMITS_GROUP MINE undefined. Ensure your telemetry definition contains the line: LIMITS_GROUP MINE",
        ):
            disable_limits_group("MINE")

    def test_disable_limits_groups_disables_limits_for_all_items_in_the_group(self):
        enable_limits("INST", "HEALTH_STATUS", "TEMP1")
        enable_limits("INST", "HEALTH_STATUS", "TEMP3")
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP3"))
        disable_limits_group("FIRST")
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP3"))

    def test_gets_and_set_the_active_limits_set(self):
        self.assertEqual(get_limits_sets(), ["DEFAULT", "TVAC"])
        set_limits_set("TVAC")
        self.assertEqual(get_limits_set(), "TVAC")
        set_limits_set("DEFAULT")
        self.assertEqual(get_limits_set(), "DEFAULT")
        set_limits_set("TVAC")
        self.assertEqual(get_limits_set(), "TVAC")
        set_limits_set("DEFAULT")
        self.assertEqual(get_limits_set(), "DEFAULT")

    def test_delete_limits_set_complains_about_default(self):
        with self.assertRaisesRegex(RuntimeError, "Cannot delete the DEFAULT limits set"):
            delete_limits_set("DEFAULT")

    def test_delete_limits_set_complains_about_current_set(self):
        set_limits_set("TVAC")
        with self.assertRaisesRegex(RuntimeError, "Cannot delete the current limits set 'TVAC'"):
            delete_limits_set("TVAC")

    def test_delete_limits_set_complains_about_non_existent_set(self):
        with self.assertRaisesRegex(RuntimeError, "Limits set 'NOPE' does not exist"):
            delete_limits_set("NOPE")

    def test_delete_limits_set_removes_set_from_the_list_of_sets(self):
        self.assertEqual(get_limits_sets(), ["DEFAULT", "TVAC"])

        delete_limits_set("TVAC")

        self.assertEqual(get_limits_sets(), ["DEFAULT"])

    def test_delete_limits_set_cleans_current_settings_but_leaves_target_model(self):
        set_limits("INST", "HEALTH_STATUS", "TEMP1", 0.0, 10.0, 20.0, 30.0)  # creates CUSTOM
        self.assertIn("CUSTOM", get_limits_sets())
        settings = Store.hget("DEFAULT__current_limits_settings", "INST__HEALTH_STATUS__TEMP1")
        self.assertIn("CUSTOM", settings.decode())

        delete_limits_set("CUSTOM")

        self.assertNotIn("CUSTOM", get_limits_sets())
        # current_limits_settings is cleaned up
        settings = Store.hget("DEFAULT__current_limits_settings", "INST__HEALTH_STATUS__TEMP1")
        self.assertNotIn("CUSTOM", settings.decode())
        # The TargetModel packet definition is intentionally left alone
        # (cleaned up on the next plugin install)
        self.assertIn("CUSTOM", get_limits("INST", "HEALTH_STATUS", "TEMP1").keys())

    def test_get_limits_events_returns_an_offset_and_limits_event_hash(self):
        # Load the events topic with two events ... only the last should be returned
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "BLAH",
            "packet_name": "BLAH",
            "item_name": "BLAH",
            "old_limits_state": "RED_LOW",
            "new_limits_state": "RED_HIGH",
            "time_nsec": 0,
            "message": "nope",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        time = datetime.now(timezone.utc)
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT",
            "packet_name": "PKT",
            "item_name": "ITEM",
            "old_limits_state": "GREEN",
            "new_limits_state": "YELLOW_LOW",
            "time_nsec": time,
            "message": "message",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        events = get_limits_events()
        self.assertIsInstance(events, list)
        offset = events[0][0]
        event = events[0][1]
        self.assertRegex(offset, r"\d{13}-\d")
        self.assertIsInstance(event, dict)
        self.assertEqual(event["type"], "LIMITS_CHANGE")
        self.assertEqual(event["target_name"], "TGT")
        self.assertEqual(event["packet_name"], "PKT")
        self.assertEqual(event["old_limits_state"], "GREEN")
        self.assertEqual(event["new_limits_state"], "YELLOW_LOW")
        # TODO: This is a different timestamp coming back:
        # 2023-10-16 23:48:36.761255 vs our formatted 2023/10/16 23:48:36.761
        self.assertEqual(event["time_nsec"][0:-3], formatted(time).replace("/", "-"))
        self.assertEqual(event["message"], "message")

    def test_get_limits_events_returns_multiple_offsets_events_with_multiple_calls(
        self,
    ):
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": "TGT",
            "packet_name": "PKT",
            "item_name": "ITEM",
            "old_limits_state": "GREEN",
            "new_limits_state": "YELLOW_LOW",
            "time_nsec": 0,
            "message": "message",
        }
        LimitsEventTopic.write(event, scope="DEFAULT")
        events = get_limits_events()
        self.assertRegex(events[0][0], r"\d{13}-\d")
        self.assertEqual(events[0][1]["time_nsec"], 0)
        last_offset = events[-1][0]

        # Load additional events
        event["old_limits_state"] = "YELLOW_LOW"
        event["new_limits_state"] = "RED_LOW"
        event["time_nsec"] = 1
        LimitsEventTopic.write(event, scope="DEFAULT")
        event["old_limits_state"] = "RED_LOW"
        event["new_limits_state"] = "YELLOW_LOW"
        event["time_nsec"] = 2
        LimitsEventTopic.write(event, scope="DEFAULT")
        event["old_limits_state"] = "YELLOW_LOW"
        event["new_limits_state"] = "GREEN"
        event["time_nsec"] = 3
        LimitsEventTopic.write(event, scope="DEFAULT")
        # Limit the count to 2
        events = get_limits_events(last_offset, count=2)
        self.assertEqual(len(events), 2)
        self.assertRegex(events[0][0], r"\d{13}-\d")
        self.assertEqual(events[0][1]["time_nsec"], 1)
        self.assertRegex(events[1][0], r"\d{13}-\d")
        self.assertEqual(events[1][1]["time_nsec"], 2)
        last_offset = events[-1][0]

        events = get_limits_events(last_offset)
        self.assertEqual(len(events), 1)
        self.assertRegex(events[0][0], r"\d{13}-\d")
        self.assertEqual(events[0][1]["time_nsec"], 3)
        last_offset = events[-1][0]

        events = get_limits_events(last_offset)
        self.assertEqual(events, ([]))

    def test_get_out_of_limits_returns_all_out_of_limits_items(self):
        for stdout in capture_io():
            inject_tlm(
                "INST",
                "HEALTH_STATUS",
                {"TEMP1": 0, "TEMP2": 0, "TEMP3": 52, "TEMP4": 81},
                type="CONVERTED",
            )
            time.sleep(0.1)

            items = get_out_of_limits()
            self.assertEqual(items[0][0], "INST")
            self.assertEqual(items[0][1], "HEALTH_STATUS")
            self.assertEqual(items[0][2], "TEMP3")
            self.assertEqual(items[0][3], "YELLOW_HIGH")
            self.assertEqual(items[1][0], "INST")
            self.assertEqual(items[1][1], "HEALTH_STATUS")
            self.assertEqual(items[1][2], "TEMP4")
            self.assertEqual(items[1][3], "RED_HIGH")

            # These don't come out because we're initializing from nothing
            self.assertNotIn("INST HEALTH_STATUS TEMP1", stdout.getvalue())
            self.assertNotIn("INST HEALTH_STATUS TEMP2", stdout.getvalue())
            self.assertRegex(stdout.getvalue(), r"INST HEALTH_STATUS TEMP3 = .* is YELLOW_HIGH")
            self.assertRegex(stdout.getvalue(), r"INST HEALTH_STATUS TEMP4 = .* is RED_HIGH")

            inject_tlm(
                "INST",
                "HEALTH_STATUS",
                {"TEMP1": 0, "TEMP2": 0, "TEMP3": 0, "TEMP4": 70},
                type="CONVERTED",
            )
            time.sleep(0.1)

            items = get_out_of_limits()
            self.assertEqual(items[0][0], "INST")
            self.assertEqual(items[0][1], "HEALTH_STATUS")
            self.assertEqual(items[0][2], "TEMP4")
            self.assertEqual(items[0][3], "YELLOW_HIGH")

            # Now we see a GREEN transition which is INFO because it was coming from YELLOW_HIGH
            self.assertRegex(stdout.getvalue(), r"INST HEALTH_STATUS TEMP3 = .* is GREEN")
            self.assertRegex(stdout.getvalue(), r"INST HEALTH_STATUS TEMP4 = .* is YELLOW_HIGH")

    def test_get_overall_limits_state_returns_the_overall_system_limits_state(self):
        inject_tlm(
            "INST",
            "HEALTH_STATUS",
            {
                "TEMP1": 0,
                "TEMP2": 0,
                "TEMP3": 0,
                "TEMP4": 0,
                "GROUND1STATUS": "CONNECTED",
                "GROUND2STATUS": "CONNECTED",
            },
        )
        time.sleep(0.1)
        self.assertEqual(get_overall_limits_state(), "GREEN")
        # TEMP1 limits: -80.0 -70.0 60.0 80.0 -20.0 20.0
        # TEMP2 limits: -60.0 -55.0 30.0 35.0
        inject_tlm("INST", "HEALTH_STATUS", {"TEMP1": 70, "TEMP2": 32, "TEMP3": 0, "TEMP4": 0})  # Both YELLOW
        time.sleep(0.1)
        self.assertEqual(get_overall_limits_state(), "YELLOW")
        inject_tlm("INST", "HEALTH_STATUS", {"TEMP1": -75, "TEMP2": 40, "TEMP3": 0, "TEMP4": 0})
        time.sleep(0.1)
        self.assertEqual(get_overall_limits_state(), "RED")
        self.assertEqual(get_overall_limits_state([]), "RED")

        # Ignoring all now yields GREEN
        self.assertEqual(get_overall_limits_state([["INST", "HEALTH_STATUS", None]]), "GREEN")
        # Ignoring just TEMP2 yields YELLOW due to TEMP1
        self.assertEqual(get_overall_limits_state([["INST", "HEALTH_STATUS", "TEMP2"]]), "YELLOW")

    def test_get_overall_limits_state_raise_on_invalid_ignored_items(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid ignored item: BLAH"):
            get_overall_limits_state(["BLAH"])
        with self.assertRaisesRegex(RuntimeError, "HEALTH_STATUS"):
            get_overall_limits_state([["INST", "HEALTH_STATUS"]])

    def test_limits_enabled_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            limits_enabled("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_limits_enabled_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            limits_enabled("INST", "BLAH", "TEMP1")

    def test_limits_enabled_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"):
            limits_enabled("INST", "HEALTH_STATUS", "BLAH")

    def test_limits_enabled_returns_whether_limits_are_enable_for_an_item(self):
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))

    def test_enable_limits_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            enable_limits("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_enable_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            enable_limits("INST", "BLAH", "TEMP1")

    def test_enable_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"):
            enable_limits("INST", "HEALTH_STATUS", "BLAH")

    def test_enable_limits_enables_limits_for_an_item(self):
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        disable_limits("INST", "HEALTH_STATUS", "TEMP1")
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        enable_limits("INST", "HEALTH_STATUS", "TEMP1")
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))

    def test_disable_limits_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"):
            disable_limits("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_disable_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            disable_limits("INST", "BLAH", "TEMP1")

    def test_disable_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"):
            disable_limits("INST", "HEALTH_STATUS", "BLAH")

    def test_disable_limits_disables_limits_for_an_item(self):
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        disable_limits("INST", "HEALTH_STATUS", "TEMP1")
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        enable_limits("INST", "HEALTH_STATUS", "TEMP1")
