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
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from openc3.logs.log_writer import LogWriter
from openc3.topics.topic import Topic
from openc3.utilities.store import EphemeralStore
from test.test_helper import mock_redis_db_shards, set_target_db_shard


class TestLogWriterDbShard(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)
        set_target_db_shard("INST", 0)
        set_target_db_shard("MY_TARGET", 1)
        set_target_db_shard("INST", 2, scope="OTHER")

    def test_returns_the_db_shard_of_the_target_of_a_topic(self):
        self.assertEqual(LogWriter.db_shard_for_topic("DEFAULT__DECOM__{INST}__HEALTH_STATUS"), 0)
        self.assertEqual(LogWriter.db_shard_for_topic("DEFAULT__TELEMETRY__{MY_TARGET}__MY_PKT"), 1)
        self.assertEqual(LogWriter.db_shard_for_topic("DEFAULT__COMMAND__{MY_TARGET}__ABORT"), 1)
        self.assertEqual(LogWriter.db_shard_for_topic("DEFAULT__DECOMCMD__{MY_TARGET}__ABORT"), 1)

    def test_looks_up_the_target_in_the_scope_of_the_topic(self):
        self.assertEqual(LogWriter.db_shard_for_topic("OTHER__DECOM__{INST}__HEALTH_STATUS"), 2)

    def test_returns_db_shard_0_for_a_topic_without_a_target(self):
        self.assertEqual(LogWriter.db_shard_for_topic("DEFAULT__openc3_log_messages"), 0)

    def test_trims_each_logged_topic_on_the_db_shard_of_its_target(self):
        topics = {
            "DEFAULT__DECOM__{INST}__HEALTH_STATUS": 0,
            "DEFAULT__DECOM__{MY_TARGET}__MY_PKT": 1,
            "OTHER__DECOM__{INST}__HEALTH_STATUS": 2,
        }
        # Each topic has 3 entries on its target's db_shard and on every other db_shard
        for topic in topics:
            for db_shard in range(3):
                for index in range(1, 4):
                    Topic.write_topic(topic, {"index": str(index)}, f"{index}-0", db_shard=db_shard)

        # Don't start a cycle thread, the test runs a single pass of it below
        with patch.object(LogWriter, "cycle_thread", True):
            writer = LogWriter("DEFAULT/logs")
        writer.cleanup_offsets = [dict.fromkeys(topics, "3-0")]
        writer.cleanup_times = [datetime.now(timezone.utc) - timedelta(seconds=1)]
        try:
            with patch("openc3.logs.log_writer.Sleeper.sleep", return_value=True):
                writer.cycle_thread_body()
        finally:
            LogWriter.instances.remove(writer)

        for topic, target_db_shard in topics.items():
            for db_shard in range(3):
                # Only the target's db_shard is trimmed up to the cleanup offset
                expected = 1 if db_shard == target_db_shard else 3
                self.assertEqual(EphemeralStore.instance(db_shard=db_shard).xlen(topic), expected, (topic, db_shard))
        self.assertEqual(writer.cleanup_offsets, [])
