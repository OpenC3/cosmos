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

import datetime
import json
import unittest
from unittest.mock import MagicMock, patch

from openc3.topics.command_topic import CommandTopic
from test.test_helper import mock_redis


class TestCommandTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.captured = {}

        def fake_write_topic(topic, msg_hash):
            self.captured["topic"] = topic
            self.captured["msg_hash"] = msg_hash

        self.store_instance = MagicMock()
        self.store_instance.write_topic.side_effect = fake_write_topic

        instance_patch = patch(
            "openc3.topics.command_topic.EphemeralStoreQueued.instance",
            return_value=self.store_instance,
        )
        instance_patch.start()
        self.addCleanup(instance_patch.stop)

        shard_patch = patch(
            "openc3.topics.command_topic.Store.db_shard_for_target",
            return_value=0,
        )
        shard_patch.start()
        self.addCleanup(shard_patch.stop)

    def _make_packet(self, extra=None):
        packet = MagicMock()
        packet.target_name = "TARGET"
        packet.packet_name = "COMMAND"
        packet.packet_time = datetime.datetime.now()
        packet.received_time = datetime.datetime.now()
        packet.received_count = 1
        packet.stored = False
        packet.buffer_no_copy.return_value = b"\x01\x02\x03\x04"
        packet.extra = extra
        return packet

    def test_writes_to_correct_topic(self):
        CommandTopic.write_packet(self._make_packet(), scope="DEFAULT")
        self.assertEqual(self.captured["topic"], "DEFAULT__COMMAND__{TARGET}__COMMAND")
        msg_hash = self.captured["msg_hash"]
        self.assertEqual(msg_hash["target_name"], "TARGET")
        self.assertEqual(msg_hash["packet_name"], "COMMAND")
        self.assertEqual(msg_hash["received_count"], 1)
        self.assertEqual(msg_hash["buffer"], b"\x01\x02\x03\x04")

    def test_includes_extra_when_set(self):
        extra = {"foo": "bar", "count": 42}
        CommandTopic.write_packet(self._make_packet(extra=extra), scope="DEFAULT")
        self.assertIn("extra", self.captured["msg_hash"])
        self.assertEqual(json.loads(self.captured["msg_hash"]["extra"]), extra)

    def test_omits_extra_when_none(self):
        CommandTopic.write_packet(self._make_packet(extra=None), scope="DEFAULT")
        self.assertNotIn("extra", self.captured["msg_hash"])

    def test_omits_extra_when_empty_dict(self):
        # Falsy extra (empty dict) should not produce an extra field
        CommandTopic.write_packet(self._make_packet(extra={}), scope="DEFAULT")
        self.assertNotIn("extra", self.captured["msg_hash"])
