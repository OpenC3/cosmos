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

import queue
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from openc3.logs.log_writer import LogWriter
from openc3.topics.topic import Topic
from openc3.utilities.bucket_utilities import BucketUtilities
from test.test_helper import BucketMock, mock_redis, set_target_db_shard


class TestLogWriterDbShardForTopic(unittest.TestCase):
    @patch("openc3.logs.log_writer.Store.db_shard_for_target", return_value=2)
    def test_looks_up_target_in_hashtag(self, mock_lookup):
        self.assertEqual(LogWriter.db_shard_for_topic("OTHER__TELEMETRY__{INST}__HEALTH_STATUS"), 2)
        mock_lookup.assert_called_once_with("INST", scope="OTHER")

    @patch("openc3.logs.log_writer.Store.db_shard_for_target", return_value=1)
    def test_handles_underscores_in_target(self, mock_lookup):
        self.assertEqual(LogWriter.db_shard_for_topic("DEFAULT__DECOM__{MY_TARGET}__PKT"), 1)
        mock_lookup.assert_called_once_with("MY_TARGET", scope="DEFAULT")

    @patch("openc3.logs.log_writer.Store.db_shard_for_target")
    def test_returns_zero_without_target(self, mock_lookup):
        self.assertEqual(LogWriter.db_shard_for_topic("DEFAULT__openc3_log_messages"), 0)
        mock_lookup.assert_not_called()


class TestLogWriterCleanupOffsets(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.patcher = patch("openc3.utilities.bucket_utilities.Bucket", BucketMock)
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()

    def test_close_file_queues_offsets_and_cycle_trims_correct_shard(self):
        writer = LogWriter("log_writer_test/")
        try:
            writer.start_new_file()
            writer.first_time = time.time_ns()
            writer.last_time = writer.first_time
            writer.last_offsets["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"] = "100-0"
            with patch.object(BucketUtilities, "move_log_file_to_bucket"):
                writer.close_file()
            self.assertEqual(writer.cleanup_offsets, [{"DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS": "100-0"}])

            # Make the cleanup due and run one cycle pass
            writer.cleanup_times = [datetime.now(timezone.utc) - timedelta(seconds=1)]
            with (
                patch("openc3.logs.log_writer.Store.db_shard_for_target", return_value=3),
                patch("openc3.logs.log_writer.Topic.trim_topic") as trim,
            ):
                writer.trim_due_cleanups(datetime.now(timezone.utc))
            trim.assert_called_once_with("DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", "100-0", db_shard=3)
            self.assertEqual(writer.cleanup_offsets, [])
        finally:
            writer.shutdown()


class TestLogWriterCycleReason(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.patcher = patch("openc3.utilities.bucket_utilities.Bucket", BucketMock)
        self.patcher.start()
        self.writers = []

    def tearDown(self):
        for writer in self.writers:
            writer.shutdown()
        self.patcher.stop()

    def writer(self, start_time, **kwargs):
        writer = LogWriter("log_writer_test/", **kwargs)
        self.writers.append(writer)
        writer.start_time = start_time
        return writer

    def test_cycles_daily_at_midnight(self):
        writer = self.writer(datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc), cycle_hour="0", cycle_minute="0")
        self.assertEqual(writer.cycle_hour, 0)
        self.assertEqual(writer.cycle_minute, 0)
        self.assertEqual(writer.cycle_reason(datetime(2026, 1, 2, 0, 0, 30, tzinfo=timezone.utc)), "daily")
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 2, 0, 1, tzinfo=timezone.utc)))

    def test_does_not_cycle_daily_twice_in_one_day(self):
        writer = self.writer(datetime(2026, 1, 2, 0, 0, 5, tzinfo=timezone.utc), cycle_hour=0, cycle_minute=0)
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 2, 0, 0, 30, tzinfo=timezone.utc)))

    def test_cycles_hourly_at_minute_zero(self):
        writer = self.writer(datetime(2026, 1, 1, 12, 30, tzinfo=timezone.utc), cycle_minute=0)
        self.assertIsNone(writer.cycle_hour)
        self.assertEqual(writer.cycle_reason(datetime(2026, 1, 1, 13, 0, 10, tzinfo=timezone.utc)), "hourly")
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 1, 13, 1, tzinfo=timezone.utc)))

    def test_cycles_on_cycle_time(self):
        writer = self.writer(datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc), cycle_time=60)
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 1, 12, 0, 59, tzinfo=timezone.utc)))
        self.assertEqual(writer.cycle_reason(datetime(2026, 1, 1, 12, 1, 1, tzinfo=timezone.utc)), "due to cycle time")


class TestLogWriterMultipleDbShards(unittest.TestCase):
    """Trimming after cleanup must happen on each topic's target db_shard."""

    def setUp(self):
        mock_redis(self)
        # INST lives on db_shard 1 while SYSTEM stays on db_shard 0
        set_target_db_shard("INST", 1)
        set_target_db_shard("SYSTEM", 0)
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        # Check the cleanup times quickly rather than every 10s
        patcher = patch.object(LogWriter, "CYCLE_TIME_INTERVAL", 0.01)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.trimmed = queue.Queue()

        def trim_topic(topic, minid, approximate=True, limit=0, db_shard=0):
            self.trimmed.put((db_shard, topic, minid))

        patcher = patch.object(Topic, "trim_topic", side_effect=trim_topic)
        patcher.start()
        self.addCleanup(patcher.stop)

    def trim(self, cleanup_offsets, count):
        writer = LogWriter(self.temp_dir.name)
        writer.cleanup_offsets.append(cleanup_offsets)
        writer.cleanup_times.append(datetime.now(timezone.utc) - timedelta(seconds=1))
        results = [self.trimmed.get(timeout=3) for _ in range(count)]
        writer.shutdown()
        return results

    def test_trims_each_topic_on_its_target_db_shard(self):
        results = self.trim(
            {"DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS": "1-0", "DEFAULT__DECOM__{SYSTEM}__META": "2-0"}, 2
        )
        self.assertCountEqual(
            results,
            [(1, "DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS", "1-0"), (0, "DEFAULT__DECOM__{SYSTEM}__META", "2-0")],
        )

    def test_looks_up_the_target_db_shard_in_the_topic_scope(self):
        # The same target name is on db_shard 1 in DEFAULT but db_shard 2 in OTHER
        set_target_db_shard("INST", 2, scope="OTHER")
        results = self.trim({"OTHER__TELEMETRY__{INST}__HEALTH_STATUS": "1-0"}, 1)
        self.assertEqual(results, [(2, "OTHER__TELEMETRY__{INST}__HEALTH_STATUS", "1-0")])


if __name__ == "__main__":
    unittest.main()
