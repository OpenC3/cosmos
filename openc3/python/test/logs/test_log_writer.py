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

import time
import unittest
from datetime import UTC, datetime, timedelta
from unittest.mock import patch

from openc3.logs.log_writer import LogWriter
from openc3.utilities.bucket_utilities import BucketUtilities
from test.test_helper import BucketMock, mock_redis


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
            writer.cleanup_times = [datetime.now(UTC) - timedelta(seconds=1)]
            with (
                patch("openc3.logs.log_writer.Store.db_shard_for_target", return_value=3),
                patch("openc3.logs.log_writer.Topic.trim_topic") as trim,
            ):
                writer.trim_due_cleanups(datetime.now(UTC))
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
        writer = self.writer(datetime(2026, 1, 1, 12, 0, tzinfo=UTC), cycle_hour="0", cycle_minute="0")
        self.assertEqual(writer.cycle_hour, 0)
        self.assertEqual(writer.cycle_minute, 0)
        self.assertEqual(writer.cycle_reason(datetime(2026, 1, 2, 0, 0, 30, tzinfo=UTC)), "daily")
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 2, 0, 1, tzinfo=UTC)))

    def test_does_not_cycle_daily_twice_in_one_day(self):
        writer = self.writer(datetime(2026, 1, 2, 0, 0, 5, tzinfo=UTC), cycle_hour=0, cycle_minute=0)
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 2, 0, 0, 30, tzinfo=UTC)))

    def test_cycles_hourly_at_minute_zero(self):
        writer = self.writer(datetime(2026, 1, 1, 12, 30, tzinfo=UTC), cycle_minute=0)
        self.assertIsNone(writer.cycle_hour)
        self.assertEqual(writer.cycle_reason(datetime(2026, 1, 1, 13, 0, 10, tzinfo=UTC)), "hourly")
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 1, 13, 1, tzinfo=UTC)))

    def test_cycles_on_cycle_time(self):
        writer = self.writer(datetime(2026, 1, 1, 12, 0, tzinfo=UTC), cycle_time=60)
        self.assertIsNone(writer.cycle_reason(datetime(2026, 1, 1, 12, 0, 59, tzinfo=UTC)))
        self.assertEqual(writer.cycle_reason(datetime(2026, 1, 1, 12, 1, 1, tzinfo=UTC)), "due to cycle time")
