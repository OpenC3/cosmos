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

from openc3.packets.packet import Packet
from openc3.topics.telemetry_topic import TelemetryTopic
from test.test_helper import mock_redis


class TestTelemetryTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        shard_patch = patch("openc3.topics.telemetry_topic.Store.db_shard_for_target", return_value=3)
        shard_patch.start()
        self.addCleanup(shard_patch.stop)

        self.packet = Packet("TARGET", "PACKET")
        self.packet.received_time = datetime.datetime.now(datetime.timezone.utc)
        self.packet.packet_time = datetime.datetime.now(datetime.timezone.utc)
        self.packet.received_count = 1

    @patch("openc3.topics.telemetry_topic.EphemeralStoreQueued.instance")
    def test_writes_to_queued_store_for_target_shard(self, instance):
        instance.return_value = MagicMock()
        TelemetryTopic.write_packet(self.packet, queued=True, scope="DEFAULT")
        instance.assert_called_once_with(db_shard=3)
        topic, msg_hash = instance.return_value.write_topic.call_args.args
        self.assertEqual(topic, "DEFAULT__TELEMETRY__{TARGET}__PACKET")
        self.assertEqual(msg_hash["target_name"], "TARGET")

    @patch("openc3.topics.telemetry_topic.Topic.write_topic")
    @patch("openc3.topics.telemetry_topic.EphemeralStoreQueued.instance")
    def test_writes_directly_to_target_shard_when_not_queued(self, instance, write_topic):
        TelemetryTopic.write_packet(self.packet, scope="DEFAULT")
        instance.assert_not_called()
        self.assertEqual(write_topic.call_args.args[0], "DEFAULT__TELEMETRY__{TARGET}__PACKET")
        self.assertEqual(write_topic.call_args.kwargs["db_shard"], 3)
