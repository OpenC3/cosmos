# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import patch

from openc3.logs.stream_log_pair import StreamLogPair
from test.test_helper import BucketMock, mock_redis


class TestStreamLogPair(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.patcher = patch("openc3.utilities.bucket_utilities.Bucket", BucketMock)
        self.patcher.start()
        self.pairs = []

    def tearDown(self):
        for pair in self.pairs:
            pair.shutdown()
        self.patcher.stop()

    def test_clone_creates_independent_logs_with_the_same_settings(self):
        pair = StreamLogPair("SLINT", [300, 1000, None, None])
        pair.write_log.stop()
        clone = pair.clone()
        self.pairs.extend([pair, clone])

        self.assertIsNot(clone, pair)
        self.assertIsNot(clone.read_log, pair.read_log)
        self.assertIsNot(clone.write_log, pair.write_log)
        self.assertIsNot(clone.read_log.mutex, pair.read_log.mutex)
        self.assertEqual(clone.read_log.name, "slint_stream_read")
        self.assertEqual(clone.write_log.name, "slint_stream_write")
        self.assertEqual(clone.read_log.cycle_time, 300)
        self.assertEqual(clone.write_log.cycle_size, 1000)
        self.assertTrue(clone.read_log.logging_enabled)
        self.assertFalse(clone.write_log.logging_enabled)
