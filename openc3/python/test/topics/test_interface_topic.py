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
import unittest
from unittest.mock import patch

from openc3.topics.interface_topic import InterfaceTopic
from test.test_helper import mock_redis


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
