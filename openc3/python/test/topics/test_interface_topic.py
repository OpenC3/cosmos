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

import json
import threading
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from openc3.topics.interface_topic import InterfaceTopic
from openc3.topics.topic import Topic
from test.test_helper import mock_redis, read_topics_from_start, set_target_db_shard, shard_redis


class TestInterfaceTopicDetails(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        for target, value in [
            ("openc3.topics.interface_topic.InterfaceTopic._db_shard_for_interface", 0),
            ("openc3.topics.interface_topic.Topic.update_topic_offsets", None),
            ("openc3.topics.interface_topic.Topic.write_topic", "1234-0"),
        ]:
            p = patch(target, return_value=value)
            p.start()
            self.addCleanup(p.stop)

    # Yield a single ack message carrying the given result for the cmd_id
    # returned by the patched write_topic
    def stub_ack(self, result):
        p = patch(
            "openc3.topics.interface_topic.Topic.read_topics",
            return_value=[("ACKTOPIC", "1234-1", {b"id": "1234-0", b"result": result}, None)],
        )
        p.start()
        self.addCleanup(p.stop)

    def test_parses_the_json_result_from_the_microservice(self):
        self.stub_ack(json.dumps({"name": "INST_INT", "state": "CONNECTED"}).encode())
        details = InterfaceTopic.interface_details("INST_INT", scope="DEFAULT")
        self.assertEqual(details["name"], "INST_INT")
        self.assertEqual(details["state"], "CONNECTED")

    def test_raises_with_the_error_text_if_the_result_is_not_json(self):
        # The microservice returns the exception message rather than JSON if
        # details raises, so surface that text instead of a JSON decode error
        self.stub_ack(b"'int' object is not callable")
        with self.assertRaisesRegex(RuntimeError, r"interface_details failed: 'int' object is not callable"):
            InterfaceTopic.interface_details("INST_INT", scope="DEFAULT")


class TestInterfaceTopicMultipleDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        # INST is installed on db_shard 1 while INST2 stays on db_shard 0
        set_target_db_shard("INST", 1)
        set_target_db_shard("INST2", 0)

    def tearDown(self):
        InterfaceTopic.while_receive_commands = False

    def test_receive_commands_reads_and_acks_each_target_on_its_db_shard(self):
        inst_topic = "{DEFAULT__CMD}TARGET__INST"
        inst2_topic = "{DEFAULT__CMD}TARGET__INST2"
        Topic.write_topic(inst_topic, {"cmd_name": "ABORT"}, db_shard=1)
        Topic.write_topic(inst2_topic, {"cmd_name": "ABORT"}, db_shard=0)
        interface = SimpleNamespace(name="INST_INT", cmd_target_names=["INST", "INST2"])
        received = []

        def process_cmd(topic, _msg_id, _msg_hash, _redis):
            received.append(topic)
            if len(received) == 2:
                InterfaceTopic.while_receive_commands = False
            return "SUCCESS"

        def receive():
            read_topics_from_start(1, [inst_topic])
            read_topics_from_start(0, [inst2_topic])
            InterfaceTopic.receive_commands(process_cmd, interface, scope="DEFAULT")

        # Reading the wrong db_shard blocks forever so don't wait on it forever
        thread = threading.Thread(target=receive, daemon=True)
        thread.start()
        thread.join(5)
        self.assertEqual(sorted(received), [inst_topic, inst2_topic])
        # Acks go back on the db_shard the command was read from
        self.assertEqual(shard_redis(1).xlen("{DEFAULT__ACKCMD}TARGET__INST"), 1)
        self.assertFalse(shard_redis(0).exists("{DEFAULT__ACKCMD}TARGET__INST"))
        self.assertEqual(shard_redis(0).xlen("{DEFAULT__ACKCMD}TARGET__INST2"), 1)
