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

import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from openc3.packets.packet import Packet
from openc3.topics.router_topic import RouterTopic
from openc3.topics.topic import Topic
from test.test_helper import mock_redis, read_topics_from_start, setup_system, shard_redis


class TestRouterTopicRouteCommand(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        p = patch("openc3.topics.router_topic.Topic.write_topic")
        self.write_topic = p.start()
        self.addCleanup(p.stop)

    def test_routes_an_identified_command_to_its_target(self):
        packet = Packet("INST", "ABORT")
        packet.buffer = b"\x01\x02"
        RouterTopic.route_command(packet, ["INST", "INST2"], scope="DEFAULT")
        self.write_topic.assert_called_once_with(
            "{DEFAULT__CMD}TARGET__INST",
            {"target_name": "INST", "cmd_name": "ABORT", "cmd_buffer": b"\x01\x02"},
            "*",
            100,
            db_shard=0,
        )

    def test_routes_an_unidentified_command_to_the_only_target_naming_that_target(self):
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02"
        RouterTopic.route_command(packet, ["INST"], scope="DEFAULT")
        self.write_topic.assert_called_once_with(
            "{DEFAULT__CMD}TARGET__INST",
            {"target_name": "INST", "cmd_name": "UNKNOWN", "cmd_buffer": b"\x01\x02"},
            "*",
            100,
            db_shard=0,
        )

    def test_raises_if_an_unidentified_command_has_more_than_one_possible_target(self):
        packet = Packet(None, None)
        packet.buffer = b"\x01\x02"
        with self.assertRaisesRegex(RuntimeError, "No route for command"):
            RouterTopic.route_command(packet, ["INST", "INST2"], scope="DEFAULT")


class TestRouterTopicMultipleDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        # INST is installed on db_shard 1 while SYSTEM stays on db_shard 0
        setup_system(db_shards={"INST": 1})

    def test_route_command_writes_to_the_target_db_shard(self):
        # The interface for the target reads its command topic from the target db_shard
        packet = Packet("INST", "ABORT")
        packet.buffer = b"\x01\x02"
        RouterTopic.route_command(packet, ["INST"], scope="DEFAULT")
        unidentified = Packet(None, None)
        unidentified.buffer = b"\x03\x04"
        RouterTopic.route_command(unidentified, ["INST"], scope="DEFAULT")
        self.assertEqual(shard_redis(1).xlen("{DEFAULT__CMD}TARGET__INST"), 2)
        self.assertFalse(shard_redis(0).exists("{DEFAULT__CMD}TARGET__INST"))

    def test_receive_telemetry_reads_each_target_from_its_db_shard(self):
        inst_topic = "DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"
        system_topic = "DEFAULT__TELEMETRY__{SYSTEM}__LIMITS_CHANGE"
        Topic.write_topic(inst_topic, {"data": "inst"}, db_shard=1)
        Topic.write_topic(system_topic, {"data": "system"}, db_shard=0)
        router = SimpleNamespace(name="ROUTER", tlm_target_names=["INST", "SYSTEM"])
        received = []

        def receive():
            read_topics_from_start(1, [inst_topic])
            read_topics_from_start(0, [system_topic])
            for topic, _, _, _ in RouterTopic.receive_telemetry(router, scope="DEFAULT"):
                if topic in (inst_topic, system_topic):
                    received.append(topic)
                if len(received) == 2:
                    return

        # Reading the wrong db_shard blocks forever so don't wait on it forever
        thread = threading.Thread(target=receive, daemon=True)
        thread.start()
        thread.join(5)
        self.assertEqual(sorted(received), [inst_topic, system_topic])
