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
from openc3.utilities.logger import Logger
from openc3.utilities.store import EphemeralStore, Store
from test.test_helper import mock_redis, mock_redis_db_shards, set_target_db_shard


class TestTopicStreamSafetyTrim(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)
        Topic.clear_stream_max_age_cache()
        self.addCleanup(Topic.clear_stream_max_age_cache)
        env_patch = patch.dict(os.environ)
        env_patch.start()
        self.addCleanup(env_patch.stop)
        os.environ.pop("OPENC3_STREAM_MAX_AGE_SECONDS", None)

    def test_max_age_defaults_to_600(self):
        self.assertEqual(Topic.stream_max_age_seconds(), 600)

    def test_max_age_reads_env(self):
        with patch.dict(os.environ, {"OPENC3_STREAM_MAX_AGE_SECONDS": "120"}):
            self.assertEqual(Topic.stream_max_age_seconds(), 120.0)

    def test_max_age_invalid_or_non_finite_uses_default(self):
        for value in ["abc", "10s", "nan", "inf", "1e400"]:
            with (
                patch.dict(os.environ, {"OPENC3_STREAM_MAX_AGE_SECONDS": value}),
                patch.object(Logger.instance(), "warn") as warn,
            ):
                Topic.clear_stream_max_age_cache()
                self.assertEqual(Topic.stream_max_age_seconds(), 600)
                self.assertEqual(Topic.stream_max_age_ms(), 600000)
                self.assertIn("is invalid", warn.call_args.args[0])

    def test_max_age_ms_is_cached(self):
        self.assertEqual(Topic.stream_max_age_ms(), 600000)
        with patch.dict(os.environ, {"OPENC3_STREAM_MAX_AGE_SECONDS": "120"}):
            self.assertEqual(Topic.stream_max_age_ms(), 600000)
            Topic.clear_stream_max_age_cache()
            self.assertEqual(Topic.stream_max_age_ms(), 120000)

    def test_max_age_raised_to_minimum(self):
        with (
            patch.dict(os.environ, {"OPENC3_STREAM_MAX_AGE_SECONDS": "0.5"}),
            patch.object(Logger.instance(), "warn") as warn,
        ):
            self.assertEqual(Topic.stream_max_age_ms(), 120000)
        self.assertIn("below the minimum", warn.call_args.args[0])

    @patch("openc3.topics.topic.time.time", return_value=1700000000.0)
    def test_minid_relative_to_now_for_auto_ids(self, _time):
        self.assertEqual(Topic.stream_safety_minid(), "1699999400000")
        self.assertEqual(Topic.stream_safety_minid(None), "1699999400000")

    def test_minid_relative_to_explicit_id(self):
        self.assertEqual(Topic.stream_safety_minid("1700000000000-5"), "1699999400000")
        self.assertEqual(Topic.stream_safety_minid(b"1700000000000-5"), "1699999400000")

    def test_minid_explicit_max_age(self):
        self.assertEqual(Topic.stream_safety_minid("1700000000000-0", max_age_ms=1320000), "1699998680000")
        self.assertIsNone(Topic.stream_safety_minid("1700000000000-0", max_age_ms=0))

    def test_minid_disabled(self):
        with patch.dict(os.environ, {"OPENC3_STREAM_MAX_AGE_SECONDS": "0"}):
            self.assertIsNone(Topic.stream_safety_minid())
            self.assertIsNone(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"))
        Topic.clear_stream_max_age_cache()
        with patch.dict(os.environ, {"OPENC3_STREAM_MAX_AGE_SECONDS": ""}):
            self.assertIsNone(Topic.stream_safety_minid())
            self.assertIsNone(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"))

    def test_minid_none_for_small_ids(self):
        self.assertIsNone(Topic.stream_safety_minid("1000-0"))

    def test_log_stream_min_age_default(self):
        self.assertEqual(Topic.log_stream_min_age_seconds("NOPE", "TLM", "DEFAULT"), 1320)

    def test_log_stream_min_age_uses_target_model(self):
        model = {"tlm_log_cycle_time": 3600, "cmd_log_cycle_time": 1200}
        with patch.object(TargetModel, "get", return_value=model) as get:
            self.assertEqual(Topic.log_stream_min_age_seconds("INST", "TLM", "DEFAULT"), 7320)
            self.assertEqual(Topic.log_stream_min_age_seconds("INST", "CMD", "DEFAULT"), 2520)
            self.assertEqual(get.call_count, 2)

    @patch("openc3.topics.topic.time.time", return_value=1700000000.0)
    def test_log_stream_minid_uses_min_age(self, _time):
        self.assertEqual(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"), "1699998680000")

    @patch("openc3.topics.topic.time.time", return_value=1700000000.0)
    def test_log_stream_minid_uses_larger_max_age(self, _time):
        with patch.dict(os.environ, {"OPENC3_STREAM_MAX_AGE_SECONDS": "3600"}):
            self.assertEqual(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"), "1699996400000")

    def test_log_stream_minid_is_cached_per_stream(self):
        with patch.object(TargetModel, "get", return_value=None) as get:
            Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT")
            Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT")
            Topic.log_stream_safety_minid("INST", "CMD", "DEFAULT")
            Topic.log_stream_safety_minid("INST", "CMD", "DEFAULT")
            self.assertEqual(get.call_count, 2)

    def test_log_stream_min_age_raises_on_lookup_failure(self):
        with (
            patch.object(TargetModel, "get", side_effect=RuntimeError("down")),
            self.assertRaisesRegex(RuntimeError, "down"),
        ):
            Topic.log_stream_min_age_seconds("INST", "TLM", "DEFAULT")

    @patch("openc3.topics.topic.time.time", return_value=1700000000.0)
    def test_log_stream_minid_not_cached_on_lookup_failure(self, _time):
        model = {"tlm_log_cycle_time": 3600}
        expected = str(1700000000000 - 7320000)
        with (
            patch("openc3.topics.topic.time.monotonic", return_value=1000.0) as monotonic,
            patch.object(Logger.instance(), "warn") as warn,
            patch.object(TargetModel, "get", side_effect=[RuntimeError("down"), model]) as get,
        ):
            self.assertIsNone(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"))
            self.assertIn("Unable to determine log cycle time for INST TLM", warn.call_args.args[0])
            # Not retried until the retry interval passes
            monotonic.return_value = 1000.0 + Topic.LOG_CYCLE_LOOKUP_RETRY_SECONDS - 1
            self.assertIsNone(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"))
            self.assertEqual(get.call_count, 1)
            monotonic.return_value = 1000.0 + Topic.LOG_CYCLE_LOOKUP_RETRY_SECONDS
            self.assertEqual(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"), expected)
            # Now cached
            self.assertEqual(Topic.log_stream_safety_minid("INST", "TLM", "DEFAULT"), expected)
            self.assertEqual(get.call_count, 2)

    def test_write_topic_rejects_maxlen_and_minid(self):
        with self.assertRaisesRegex(ValueError, "both maxlen and minid"):
            Topic.write_topic("TOPIC", {"a": 1}, "*", 10, minid="123")

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


def shard(db_shard):
    return EphemeralStore.instance(db_shard=db_shard)


class TestMockRedisDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)

    def test_gives_each_db_shard_its_own_data(self):
        Store.instance(db_shard=1).set("KEY", "one")
        self.assertIsNone(Store.instance(db_shard=0).get("KEY"))
        self.assertEqual(Store.instance(db_shard=1).get("KEY"), b"one")
        # The ephemeral store is separate from the store on the same db_shard
        self.assertIsNone(shard(1).get("KEY"))


class TestTopicDbShardRouting(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)

    def test_writes_and_reads_a_topic_on_the_given_db_shard_only(self):
        Topic.write_topic("DEFAULT__TOPIC__X", {"received_count": "5"}, db_shard=1)
        self.assertEqual(shard(0).xlen("DEFAULT__TOPIC__X"), 0)
        self.assertEqual(shard(1).xlen("DEFAULT__TOPIC__X"), 1)

        self.assertEqual(Topic.get_cnt("DEFAULT__TOPIC__X", db_shard=1), 5)
        self.assertEqual(Topic.get_cnt("DEFAULT__TOPIC__X"), 0)
        self.assertEqual(Topic.get_newest_message("DEFAULT__TOPIC__X", db_shard=1)[1], {b"received_count": b"5"})
        self.assertEqual(Topic.get_newest_message("DEFAULT__TOPIC__X"), (None, None))
        self.assertEqual(Topic.get_oldest_message("DEFAULT__TOPIC__X", db_shard=1)[1], {b"received_count": b"5"})
        self.assertIsNone(Topic.get_oldest_message("DEFAULT__TOPIC__X"))
        self.assertNotEqual(Topic.get_last_offset("DEFAULT__TOPIC__X", db_shard=1), "0-0")
        self.assertEqual(Topic.get_last_offset("DEFAULT__TOPIC__X"), "0-0")
        self.assertEqual(Topic.topics("TOPIC", "DEFAULT", db_shard=1), [b"DEFAULT__TOPIC__X"])
        self.assertEqual(Topic.topics("TOPIC", "DEFAULT"), [])

        messages = [msg for _, _, msg, _ in Topic.read_topics(["DEFAULT__TOPIC__X"], ["0-0"], db_shard=1)]
        self.assertEqual(messages, [{b"received_count": b"5"}])
        self.assertEqual(list(Topic.read_topics(["DEFAULT__TOPIC__X"], ["0-0"], 1)), [])

    def test_clears_and_trims_a_topic_on_the_given_db_shard_only(self):
        for index in range(3):
            Topic.write_topic("TOPIC", {"index": str(index)}, f"{index + 1}-0", db_shard=1)
        Topic.write_topic("TOPIC", {"index": "0"}, db_shard=0)

        Topic.trim_topic("TOPIC", "2-0", False, db_shard=1)
        self.assertEqual(shard(1).xlen("TOPIC"), 2)
        Topic.clear_topics(["TOPIC"], 1, db_shard=1)
        self.assertEqual(shard(1).xlen("TOPIC"), 1)
        self.assertEqual(shard(0).xlen("TOPIC"), 1)

    def test_writes_an_ack_to_the_given_db_shard(self):
        Topic.write_ack("{DEFAULT__CMD}TARGET__INST", "SUCCESS", "1-0", db_shard=1)
        _, msg = Topic.get_newest_message("{DEFAULT__ACKCMD}TARGET__INST", db_shard=1)
        self.assertEqual(msg, {b"result": b"SUCCESS", b"id": b"1-0"})
        self.assertEqual(shard(0).exists("{DEFAULT__ACKCMD}TARGET__INST"), 0)


class TestTopicGroupTopicsByDbShard(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)
        set_target_db_shard("INST", 0)
        set_target_db_shard("INST2", 1)
        set_target_db_shard("MY_TARGET", 2)

    def test_groups_command_topics_by_the_db_shard_of_their_target(self):
        topics = [
            "{DEFAULT__CMD}TARGET__INST",
            "{DEFAULT__CMD}TARGET__INST2",
            "{DEFAULT__CMD}TARGET__MY_TARGET",
            "{DEFAULT__CMD}INTERFACE__INT",
        ]
        self.assertEqual(
            Topic.group_topics_by_db_shard(topics, "CMD}TARGET__", "DEFAULT"),
            {
                0: ["{DEFAULT__CMD}TARGET__INST", "{DEFAULT__CMD}INTERFACE__INT"],
                1: ["{DEFAULT__CMD}TARGET__INST2"],
                2: ["{DEFAULT__CMD}TARGET__MY_TARGET"],
            },
        )

    def test_groups_telemetry_topics_by_the_db_shard_of_their_target(self):
        topics = [
            "DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS",
            "DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS",
            "DEFAULT__TELEMETRY__{MY_TARGET}__MY_PKT",
        ]
        self.assertEqual(
            Topic.group_topics_by_db_shard(topics, "__TELEMETRY__", "DEFAULT"),
            {
                0: ["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"],
                1: ["DEFAULT__TELEMETRY__{INST2}__HEALTH_STATUS"],
                2: ["DEFAULT__TELEMETRY__{MY_TARGET}__MY_PKT"],
            },
        )

    def test_puts_a_target_which_isnt_on_a_db_shard_on_db_shard_0(self):
        self.assertEqual(
            Topic.group_topics_by_db_shard(["{DEFAULT__CMD}TARGET__UNKNOWN"], "CMD}TARGET__", "DEFAULT"),
            {0: ["{DEFAULT__CMD}TARGET__UNKNOWN"]},
        )

    def test_looks_up_the_db_shard_in_the_given_scope(self):
        set_target_db_shard("INST", 3, scope="OTHER")
        self.assertEqual(
            Topic.group_topics_by_db_shard(["{OTHER__CMD}TARGET__INST"], "CMD}TARGET__", "OTHER"),
            {3: ["{OTHER__CMD}TARGET__INST"]},
        )

    def test_all_same_db_shard_is_true_for_at_most_one_db_shard(self):
        self.assertTrue(Topic.all_same_db_shard({}))
        self.assertTrue(Topic.all_same_db_shard({1: ["A", "B"]}))
        self.assertFalse(Topic.all_same_db_shard({0: ["A"], 1: ["B"]}))


class TestRouterTopicRouteCommandDbShard(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)
        set_target_db_shard("INST2", 1)

    def test_routes_a_command_to_the_db_shard_of_its_target(self):
        from openc3.packets.packet import Packet
        from openc3.topics.router_topic import RouterTopic

        packet = Packet("INST2", "ABORT")
        packet.buffer = b"\x01\x02"
        with patch.object(Packet, "identified", return_value=True):
            RouterTopic.route_command(packet, ["INST2"], scope="DEFAULT")
        self.assertEqual(shard(0).xlen("{DEFAULT__CMD}TARGET__INST2"), 0)
        self.assertEqual(shard(1).xlen("{DEFAULT__CMD}TARGET__INST2"), 1)

        packet = Packet(None, None)
        packet.buffer = b"\x01\x02"
        RouterTopic.route_command(packet, ["INST2"], scope="DEFAULT")
        self.assertEqual(shard(1).xlen("{DEFAULT__CMD}TARGET__INST2"), 2)
