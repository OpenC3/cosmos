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

import unittest
from unittest.mock import patch

from openc3.topics.topic import Topic
from openc3.utilities.store import EphemeralStore, Store
from test.test_helper import mock_redis_db_shards, set_target_db_shard


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
