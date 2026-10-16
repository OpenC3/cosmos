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
import unittest
from unittest.mock import MagicMock, patch

from openc3.topics.telemetry_topic import TelemetryTopic
from test.test_helper import mock_redis


class TestTelemetryTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.captured = {}

        def fake_write_topic(topic, msg_hash, db_shard=0):
            self.captured["topic"] = topic
            self.captured["msg_hash"] = msg_hash

        topic_patch = patch("openc3.topics.telemetry_topic.Topic.write_topic", side_effect=fake_write_topic)
        topic_patch.start()
        self.addCleanup(topic_patch.stop)

        shard_patch = patch("openc3.topics.telemetry_topic.Store.db_shard_for_target", return_value=0)
        shard_patch.start()
        self.addCleanup(shard_patch.stop)

    def _make_packet(self, stored):
        packet = MagicMock()
        packet.target_name = "TARGET"
        packet.packet_name = "PACKET"
        packet.packet_time = datetime.datetime.now()
        packet.received_time = datetime.datetime.now()
        packet.received_count = 1
        packet.stored = stored
        packet.buffer_no_copy.return_value = b"\x01\x02"
        packet.extra = None
        return packet

    def test_writes_stored_as_lowercase_like_ruby(self):
        TelemetryTopic.write_packet(self._make_packet(True), scope="DEFAULT")
        self.assertEqual(self.captured["topic"], "DEFAULT__TELEMETRY__{TARGET}__PACKET")
        self.assertEqual(self.captured["msg_hash"]["stored"], "true")
        TelemetryTopic.write_packet(self._make_packet(False), scope="DEFAULT")
        self.assertEqual(self.captured["msg_hash"]["stored"], "false")
