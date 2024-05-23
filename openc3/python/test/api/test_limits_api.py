# Copyright 2024 OpenC3, Inc.
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
from datetime import datetime, timezone
import unittest
import threading
from unittest.mock import *
from test.test_helper import *
from openc3.api.limits_api import *
from openc3.api.tlm_api import *
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.models.microservice_model import MicroserviceModel
from openc3.microservices.decom_microservice import DecomMicroservice
from openc3.utilities.time import formatted


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
            try:
                result = orig_xread(*args, **kwargs)
            except RuntimeError:
                pass

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
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            get_limits("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_get_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            get_limits("INST", "BLAH", "TEMP1")

    def test_get_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"
        ):
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
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            set_limits("BLAH", "HEALTH_STATUS", "TEMP1", 0.0, 10.0, 20.0, 30.0)

    def test_set_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            set_limits("INST", "BLAH", "TEMP1", 0.0, 10.0, 20.0, 30.0)

    def test_set_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"
        ):
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
            time.sleep(0.01)

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
            self.assertRegex(
                stdout.getvalue(), r"INST HEALTH_STATUS TEMP3 = .* is YELLOW_HIGH"
            )
            self.assertRegex(
                stdout.getvalue(), r"INST HEALTH_STATUS TEMP4 = .* is RED_HIGH"
            )

            inject_tlm(
                "INST",
                "HEALTH_STATUS",
                {"TEMP1": 0, "TEMP2": 0, "TEMP3": 0, "TEMP4": 70},
                type="CONVERTED",
            )
            time.sleep(0.01)

            items = get_out_of_limits()
            self.assertEqual(items[0][0], "INST")
            self.assertEqual(items[0][1], "HEALTH_STATUS")
            self.assertEqual(items[0][2], "TEMP4")
            self.assertEqual(items[0][3], "YELLOW_HIGH")

            # Now we see a GREEN transition which is INFO because it was coming from YELLOW_HIGH
            self.assertRegex(
                stdout.getvalue(), r"INST HEALTH_STATUS TEMP3 = .* is GREEN"
            )
            self.assertRegex(
                stdout.getvalue(), r"INST HEALTH_STATUS TEMP4 = .* is YELLOW_HIGH"
            )

    def test_get_overall_limits_state_returns_the_overall_system_limits_state(self):
        inject_tlm(
            "INST",
            "HEALTH_STATUS",
            {
                "TEMP1": 0,
                "TEMP2": 0,
                "TEMP3": 0,
                "TEMP4": 0,
                "GROUND1STATUS": 1,
                "GROUND2STATUS": 1,
            },
        )
        time.sleep(0.1)
        self.assertEqual(get_overall_limits_state(), "GREEN")
        # TEMP1 limits: -80.0 -70.0 60.0 80.0 -20.0 20.0
        # TEMP2 limits: -60.0 -55.0 30.0 35.0
        inject_tlm(
            "INST", "HEALTH_STATUS", {"TEMP1": 70, "TEMP2": 32, "TEMP3": 0, "TEMP4": 0}
        )  # Both YELLOW
        time.sleep(0.1)
        self.assertEqual(get_overall_limits_state(), "YELLOW")
        inject_tlm(
            "INST", "HEALTH_STATUS", {"TEMP1": -75, "TEMP2": 40, "TEMP3": 0, "TEMP4": 0}
        )
        time.sleep(0.1)
        self.assertEqual(get_overall_limits_state(), "RED")
        self.assertEqual(get_overall_limits_state([]), "RED")

        # Ignoring all now yields GREEN
        self.assertEqual(
            get_overall_limits_state([["INST", "HEALTH_STATUS", None]]), "GREEN"
        )
        # Ignoring just TEMP2 yields YELLOW due to TEMP1
        self.assertEqual(
            get_overall_limits_state([["INST", "HEALTH_STATUS", "TEMP2"]]), "YELLOW"
        )

    def test_get_overall_limits_state_raise_on_invalid_ignored_items(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid ignored item: BLAH"):
            get_overall_limits_state(["BLAH"])
        with self.assertRaisesRegex(RuntimeError, "HEALTH_STATUS"):
            get_overall_limits_state([["INST", "HEALTH_STATUS"]])

    def test_limits_enabled_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            limits_enabled("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_limits_enabled_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            limits_enabled("INST", "BLAH", "TEMP1")

    def test_limits_enabled_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"
        ):
            limits_enabled("INST", "HEALTH_STATUS", "BLAH")

    def test_limits_enabled_returns_whether_limits_are_enable_for_an_item(self):
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))

    def test_enable_limits_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            enable_limits("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_enable_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            enable_limits("INST", "BLAH", "TEMP1")

    def test_enable_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"
        ):
            enable_limits("INST", "HEALTH_STATUS", "BLAH")

    def test_enable_limits_enables_limits_for_an_item(self):
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        disable_limits("INST", "HEALTH_STATUS", "TEMP1")
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        enable_limits("INST", "HEALTH_STATUS", "TEMP1")
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))

    def test_disable_limits_complains_about_non_existant_targets(self):
        with self.assertRaisesRegex(
            RuntimeError, "Packet 'BLAH HEALTH_STATUS' does not exist"
        ):
            disable_limits("BLAH", "HEALTH_STATUS", "TEMP1")

    def test_disable_limits_complains_about_non_existant_packets(self):
        with self.assertRaisesRegex(RuntimeError, "Packet 'INST BLAH' does not exist"):
            disable_limits("INST", "BLAH", "TEMP1")

    def test_disable_limits_complains_about_non_existant_items(self):
        with self.assertRaisesRegex(
            RuntimeError, "Item 'INST HEALTH_STATUS BLAH' does not exist"
        ):
            disable_limits("INST", "HEALTH_STATUS", "BLAH")

    def test_disable_limits_disables_limits_for_an_item(self):
        self.assertTrue(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        disable_limits("INST", "HEALTH_STATUS", "TEMP1")
        self.assertFalse(limits_enabled("INST", "HEALTH_STATUS", "TEMP1"))
        enable_limits("INST", "HEALTH_STATUS", "TEMP1")
