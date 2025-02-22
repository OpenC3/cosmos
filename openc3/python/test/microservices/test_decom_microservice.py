# Copyright 2025 OpenC3, Inc.
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

import re
import time
import unittest
import threading
from unittest.mock import patch
from datetime import datetime, timezone
from test.test_helper import Mock, mock_redis, setup_system, capture_io
from openc3.api.tlm_api import tlm
from openc3.system.system import System
from openc3.packets.limits_response import LimitsResponse
from openc3.models.target_model import TargetModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.microservices.decom_microservice import DecomMicroservice
from openc3.topics.limits_event_topic import LimitsEventTopic
from openc3.topics.topic import Topic
from openc3.topics.telemetry_topic import TelemetryTopic
from openc3.processors.processor import Processor


class TestDecomMicroservice(unittest.TestCase):
    @patch("openc3.system.system.System.limits_set")
    @patch("openc3.microservices.microservice.System")
    def setUp(self, usystem, limits_set):
        redis = mock_redis(self)
        setup_system()

        limits_set.return_value = "DEFAULT"

        orig_xread = redis.xread

        # Override xread to ignore the block and count keywords
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

        model = TargetModel(name="INST", scope="DEFAULT")
        model.create()
        model = TargetModel(name="SYSTEM", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(
            "DEFAULT__DECOM__INST_INT",
            scope="DEFAULT",
            topics=[
                "DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS",
            ],
            target_names=["INST"],
        )
        model.create()
        self.dm = DecomMicroservice("DEFAULT__DECOM__INST_INT")
        self.dm_thread = threading.Thread(target=self.dm.run)
        self.dm_thread.start()
        time.sleep(0.001)  # Allow the thread to start

    def tearDown(self):
        self.dm.shutdown()
        self.dm_thread.join()

    def test_run_decommutates_a_packet_from_raw_to_engineering_values(self):
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.extra = {}
        packet.extra["STATUS"] = "OK"
        packet.received_time = datetime.now(timezone.utc)
        for stdout in capture_io():
            TelemetryTopic.write_packet(packet, scope="DEFAULT")
            time.sleep(0.01)
            self.assertIn("INST HEALTH_STATUS TEMP1 = -100.0 is RED_LOW (-80.0)", stdout.getvalue())
            self.assertIn("INST HEALTH_STATUS TEMP2 = -100.0 is RED_LOW (-60.0)", stdout.getvalue())
            self.assertIn("INST HEALTH_STATUS TEMP3 = -100.0 is RED_LOW (-25.0)", stdout.getvalue())
            self.assertIn("INST HEALTH_STATUS TEMP4 = -100.0 is RED_LOW (-80.0)", stdout.getvalue())
            self.assertIn("INST HEALTH_STATUS GROUND1STATUS = UNAVAILABLE is YELLOW", stdout.getvalue())
            self.assertIn("INST HEALTH_STATUS GROUND2STATUS = UNAVAILABLE is YELLOW", stdout.getvalue())
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), -100.0)
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP2"), -100.0)
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP3"), -100.0)
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP4"), -100.0)

        events = LimitsEventTopic.read(0, scope="DEFAULT")
        self.assertEqual(len(events), 6)
        # Check the first one completely
        self.assertEqual(events[0][1].get("type"), "LIMITS_CHANGE")
        self.assertEqual(events[0][1].get("target_name"), "INST")
        self.assertEqual(events[0][1].get("packet_name"), "HEALTH_STATUS")
        self.assertEqual(events[0][1].get("item_name"), "TEMP1")
        self.assertEqual(events[0][1].get("old_limits_state"), "None")
        self.assertEqual(events[0][1].get("new_limits_state"), "RED_LOW")
        self.assertEqual(events[0][1].get("message"), "INST HEALTH_STATUS TEMP1 = -100.0 is RED_LOW (-80.0)")
        self.assertEqual(events[1][1].get("message"), "INST HEALTH_STATUS TEMP2 = -100.0 is RED_LOW (-60.0)")
        self.assertEqual(events[2][1].get("message"), "INST HEALTH_STATUS TEMP3 = -100.0 is RED_LOW (-25.0)")
        self.assertEqual(events[3][1].get("message"), "INST HEALTH_STATUS TEMP4 = -100.0 is RED_LOW (-80.0)")
        self.assertEqual(events[4][1].get("message"), "INST HEALTH_STATUS GROUND1STATUS = UNAVAILABLE is YELLOW")
        self.assertEqual(events[5][1].get("message"), "INST HEALTH_STATUS GROUND2STATUS = UNAVAILABLE is YELLOW")

        packet.disable_limits("TEMP3")
        packet.write("TEMP1", 0.0)
        packet.write("TEMP2", 0.0)
        packet.write("TEMP3", 0.0)
        for stdout in capture_io():
            TelemetryTopic.write_packet(packet, scope="DEFAULT")
            time.sleep(0.01)
            assert re.search(r"INST HEALTH_STATUS TEMP1 = .* is BLUE \(-20.0 to 20.0\)", stdout.getvalue())
            assert re.search(r"INST HEALTH_STATUS TEMP2 = .* is GREEN \(-55.0 to 30.0\)", stdout.getvalue())

        # Start reading from the last event's ID
        events = LimitsEventTopic.read(events[-1][0], scope="DEFAULT")
        self.assertEqual(len(events), 3)
        self.assertEqual(events[0][1]["type"], "LIMITS_CHANGE")
        self.assertEqual(events[0][1]["target_name"], "INST")
        self.assertEqual(events[0][1]["packet_name"], "HEALTH_STATUS")
        self.assertEqual(events[0][1]["item_name"], "TEMP3")
        self.assertEqual(events[0][1]["old_limits_state"], "RED_LOW")
        self.assertEqual(events[0][1]["new_limits_state"], "None")
        self.assertEqual(events[0][1]["message"], "INST HEALTH_STATUS TEMP3 is disabled")
        assert re.search(r"INST HEALTH_STATUS TEMP1 = .* is BLUE \(-20.0 to 20.0\)", events[1][1]["message"])
        assert re.search(r"INST HEALTH_STATUS TEMP2 = .* is GREEN \(-55.0 to 30.0\)", events[2][1]["message"])

    def test_handles_exceptions_in_the_thread(self):
        with patch.object(self.dm, "microservice_cmd") as mock_microservice_cmd:
            mock_microservice_cmd.side_effect = Exception("Bad command")
            for stdout in capture_io():
                Topic.write_topic("MICROSERVICE__DEFAULT__DECOM__INST_INT", {"connect": "true"}, "*", 100)
                time.sleep(0.01)
                self.assertIn("Decom error Exception('Bad command')", stdout.getvalue())
            # This is an implementation detail but we want to ensure the error was logged
            self.assertEqual(self.dm.metric.data["decom_error_total"]["value"], 1)

    def test_handles_exceptions_in_user_processors(self):
        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        processor = Processor()
        processor.call = lambda packet, buffer: exec("raise RuntimeError('Bad processor')")
        packet.processors["TEMP1"] = processor
        packet.received_time = datetime.now(timezone.utc)
        for stdout in capture_io():
            TelemetryTopic.write_packet(packet, scope="DEFAULT")
            time.sleep(0.01)
            self.assertIn("Bad processor", stdout.getvalue())
        # This is an implementation detail but we want to ensure the error was logged
        self.assertEqual(self.dm.metric.data["decom_error_total"]["value"], 1)
        # CVT is still set
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP1"), -100.0)
        self.assertEqual(tlm("INST HEALTH_STATUS TEMP2"), -100.0)

    def test_handles_limits_responses_in_another_thread(self):
        class DelayedLimitsResponse(LimitsResponse):
            def call(self, packet, item, old_limits_state):
                time.sleep(0.1)

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        temp1 = packet.get_item("TEMP1")
        temp1.limits.response = DelayedLimitsResponse()
        packet.received_time = datetime.now(timezone.utc)
        TelemetryTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)

        # Verify that even though the limits response sleeps for 0.1s, the decom thread is not blocked
        self.assertLess(self.dm.metric.data["decom_duration_seconds"]["value"], 0.01)

    def test_handles_exceptions_in_limits_responses(self):
        class BadLimitsResponse(LimitsResponse):
            def call(self, packet, item, old_limits_state):
                raise RuntimeError("Bad response")

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        temp1 = packet.get_item("TEMP1")
        temp1.limits.response = BadLimitsResponse()
        packet.received_time = datetime.now(timezone.utc)
        for stdout in capture_io():
            TelemetryTopic.write_packet(packet, scope="DEFAULT")
            time.sleep(0.01)
            self.assertIn("INST HEALTH_STATUS TEMP1 Limits Response Exception!", stdout.getvalue())
            self.assertIn("Bad response", stdout.getvalue())

        self.assertEqual(self.dm.limits_response_thread.metric.data["limits_response_error_total"]["value"], 1)
