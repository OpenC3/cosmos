# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import queue
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from openc3.logs.log_writer import LogWriter
from openc3.topics.topic import Topic
from test.test_helper import mock_redis, set_target_db_shard


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
