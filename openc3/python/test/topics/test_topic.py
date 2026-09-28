# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import unittest
from unittest.mock import MagicMock, patch

from openc3.models.target_model import TargetModel
from openc3.topics.telemetry_topic import TelemetryTopic
from openc3.topics.topic import Topic
from test.test_helper import mock_redis


class TestTopicStreamSafetyTrim(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)
        Topic.clear_log_cycle_times()
        self.addCleanup(Topic.clear_log_cycle_times)
        env_patch = patch.dict(os.environ)
        env_patch.start()
        self.addCleanup(env_patch.stop)
        os.environ.pop("OPENC3_STREAM_MAX_AGE_SECONDS", None)

    def test_max_age_defaults_to_600(self):
        self.assertEqual(Topic.stream_max_age_seconds(), 600)

    def test_max_age_reads_env(self):
        os.environ["OPENC3_STREAM_MAX_AGE_SECONDS"] = "120"
        self.assertEqual(Topic.stream_max_age_seconds(), 120.0)

    @patch("openc3.topics.topic.time.time", return_value=1700000000.0)
    def test_minid_relative_to_now_for_auto_ids(self, _time):
        self.assertEqual(Topic.stream_safety_minid(), "1699999400000")
        self.assertEqual(Topic.stream_safety_minid(None), "1699999400000")

    def test_minid_relative_to_explicit_id(self):
        self.assertEqual(Topic.stream_safety_minid("1700000000000-5"), "1699999400000")
        self.assertEqual(Topic.stream_safety_minid(b"1700000000000-5"), "1699999400000")

    def test_minid_respects_min_age(self):
        self.assertEqual(Topic.stream_safety_minid("1700000000000-0", min_age_seconds=1320), "1699998680000")
        self.assertEqual(Topic.stream_safety_minid("1700000000000-0", min_age_seconds=10), "1699999400000")

    def test_minid_disabled(self):
        os.environ["OPENC3_STREAM_MAX_AGE_SECONDS"] = "0"
        self.assertIsNone(Topic.stream_safety_minid())
        os.environ["OPENC3_STREAM_MAX_AGE_SECONDS"] = ""
        self.assertIsNone(Topic.stream_safety_minid(min_age_seconds=1320))

    def test_minid_none_for_small_ids(self):
        self.assertIsNone(Topic.stream_safety_minid("1000-0"))

    def test_log_stream_min_age_default(self):
        self.assertEqual(Topic.log_stream_min_age_seconds("NOPE", "TLM", "DEFAULT"), 1320)

    def test_log_stream_min_age_uses_target_model(self):
        model = {"tlm_log_cycle_time": 3600, "cmd_log_cycle_time": 1200}
        with patch.object(TargetModel, "get", return_value=model) as get:
            self.assertEqual(Topic.log_stream_min_age_seconds("INST", "TLM", "DEFAULT"), 7320)
            self.assertEqual(Topic.log_stream_min_age_seconds("INST", "CMD", "DEFAULT"), 2520)
            # Cached after the first lookup
            self.assertEqual(Topic.log_stream_min_age_seconds("INST", "TLM", "DEFAULT"), 7320)
            self.assertEqual(get.call_count, 2)

    def test_write_topic_trims_old_entries(self):
        Topic.write_topic("TOPIC", {"a": 1}, "1000-0")
        Topic.write_topic("TOPIC", {"a": 2}, "2000-0")
        Topic.write_topic("TOPIC", {"a": 3}, "3000-0", approximate=False, minid="2000")
        entries = self.redis.xrange("TOPIC")
        self.assertEqual([entry[0] for entry in entries], [b"2000-0", b"3000-0"])

    def test_telemetry_topic_applies_log_cycle_minid(self):
        packet = MagicMock()
        packet.target_name = "INST"
        packet.packet_name = "HEALTH_STATUS"
        packet.extra = None
        packet.buffer_no_copy.return_value = b"\x00"
        with (
            patch("openc3.topics.topic.time.time", return_value=1700000000.0),
            patch("openc3.topics.telemetry_topic.to_nsec_from_epoch", return_value=0),
            patch("openc3.topics.telemetry_topic.Topic.write_topic") as write_topic,
        ):
            TelemetryTopic.write_packet(packet, scope="DEFAULT")
        self.assertEqual(write_topic.call_args.kwargs["minid"], str(1700000000000 - 1320000))
