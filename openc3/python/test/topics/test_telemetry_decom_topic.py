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

from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from test.test_helper import mock_redis


class TestTelemetryDecomTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.captured = {}

        def fake_write_topic(topic, msg_hash, id, db_shard=None):
            self.captured["topic"] = topic
            self.captured["msg_hash"] = msg_hash
            self.captured["id"] = id

        write_patch = patch(
            "openc3.topics.telemetry_decom_topic.Topic.write_topic",
            side_effect=fake_write_topic,
        )
        write_patch.start()
        self.addCleanup(write_patch.stop)

        build_patch = patch(
            "openc3.topics.telemetry_decom_topic.CvtModel.build_json_from_packet",
            return_value={"TEMP1": 1.0},
        )
        build_patch.start()
        self.addCleanup(build_patch.stop)

        self.set_json_mock = MagicMock()
        set_patch = patch(
            "openc3.topics.telemetry_decom_topic.CvtModel.set_json",
            new=self.set_json_mock,
        )
        set_patch.start()
        self.addCleanup(set_patch.stop)

        shard_patch = patch(
            "openc3.topics.telemetry_decom_topic.Store.db_shard_for_target",
            return_value=0,
        )
        shard_patch.start()
        self.addCleanup(shard_patch.stop)

    def _make_packet(self, extra=None, stored=False):
        packet = MagicMock()
        packet.target_name = "TARGET"
        packet.packet_name = "PKT"
        packet.packet_time = datetime.datetime.now()
        packet.received_time = datetime.datetime.now()
        packet.received_count = 5
        packet.stored = stored
        packet.extra = extra
        return packet

    def test_writes_to_correct_decom_topic(self):
        TelemetryDecomTopic.write_packet(self._make_packet(), scope="DEFAULT")
        self.assertEqual(self.captured["topic"], "DEFAULT__DECOM__{TARGET}__PKT")
        msg_hash = self.captured["msg_hash"]
        self.assertEqual(msg_hash["target_name"], "TARGET")
        self.assertEqual(msg_hash["packet_name"], "PKT")
        self.assertEqual(msg_hash["received_count"], 5)
        self.assertIn("json_data", msg_hash)

    def test_includes_extra_when_set(self):
        extra = {"foo": "bar", "count": 42}
        TelemetryDecomTopic.write_packet(self._make_packet(extra=extra), scope="DEFAULT")
        self.assertIn("extra", self.captured["msg_hash"])
        self.assertEqual(json.loads(self.captured["msg_hash"]["extra"]), extra)

    def test_omits_extra_when_none(self):
        TelemetryDecomTopic.write_packet(self._make_packet(extra=None), scope="DEFAULT")
        self.assertNotIn("extra", self.captured["msg_hash"])

    def test_updates_cvt_when_not_stored(self):
        TelemetryDecomTopic.write_packet(self._make_packet(stored=False), scope="DEFAULT")
        self.set_json_mock.assert_called_once()

    def test_skips_cvt_when_stored(self):
        TelemetryDecomTopic.write_packet(self._make_packet(stored=True), scope="DEFAULT")
        self.set_json_mock.assert_not_called()
