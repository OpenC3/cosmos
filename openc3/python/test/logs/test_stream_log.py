# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
import unittest
from unittest.mock import patch
from test.test_helper import mock_redis, capture_io, BucketMock
from openc3.logs.stream_log import StreamLog

class TestStreamLog(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.mock_s3 = BucketMock.getClient()
        self.mock_s3.clear()
        self.patcher = patch("openc3.utilities.bucket_utilities.Bucket", BucketMock)
        self.patcher.start()

    def tearDown(self):
        if hasattr(self, "stream_log"):
            self.stream_log.shutdown()
        self.patcher.stop()

    def test_complains_with_not_enough_arguments(self):
        with self.assertRaisesRegex(TypeError, "log_type"):
            StreamLog("SLINT")

    def test_complains_with_an_unknown_log_type(self):
        with self.assertRaisesRegex(RuntimeError, "log_type must be 'READ' or 'WRITE'"):
            StreamLog("SLINT", "BOTH")

    def test_creates_a_raw_write_log(self):
        self.stream_log = StreamLog("SLINT", "WRITE")
        self.stream_log.write(b"\x00\x01\x02\x03")
        self.stream_log.stop()
        time.sleep(0.001)
        key = self.mock_s3.files()[0]
        self.assertIn("slint_stream_write.bin.gz", key)
        self.assertEqual(self.mock_s3.data(key), b"\x00\x01\x02\x03")

    def test_creates_a_raw_read_log(self):
        self.stream_log = StreamLog("SLINT", "READ")
        self.stream_log.write(b"\x01\x02\x03\x04")
        self.stream_log.stop()
        time.sleep(0.001)
        key = self.mock_s3.files()[0]
        self.assertIn("slint_stream_read.bin.gz", key)
        self.assertEqual(self.mock_s3.data(key), b"\x01\x02\x03\x04")

    def test_does_not_write_data_if_logging_is_disabled(self):
        self.stream_log = StreamLog("SLINT", "WRITE")
        self.stream_log.stop()
        time.sleep(0.001)
        self.stream_log.write(b"\x00\x01\x02\x03")
        self.assertEqual(self.stream_log.file_size, 0)
        self.assertEqual(len(self.mock_s3.files()), 0)

    def test_cycles_the_log_when_it_a_size(self):
        self.stream_log = StreamLog("SLINT", "WRITE", 300, 2000)
        self.stream_log.write(b"\x00\x01\x02\x03" * 250)  # size 1000
        self.stream_log.write(b"\x00\x01\x02\x03" * 250)  # size 2000
        self.assertEqual(len(self.mock_s3.files()), 0)  # hasn't cycled yet
        time.sleep(0.001)
        self.stream_log.write(b"\x00")  # size 200001
        time.sleep(0.001)
        self.assertEqual(len(self.mock_s3.files()), 1)
        self.stream_log.stop()
        time.sleep(0.001)
        self.assertEqual(len(self.mock_s3.files()), 2)

    def test_handles_errors_creating_the_log_file(self):
        with patch("builtins.open") as mock_file:
            mock_file.side_effect = IOError()
            for stdout in capture_io():
                self.stream_log = StreamLog("SLINT", "WRITE")
                self.stream_log.write(b"\x00\x01\x02\x03")
                self.stream_log.stop()
                self.assertIn(
                    "Error starting new log file",
                    stdout.getvalue(),
                )

    def test_handles_errors_moving_the_log_file(self):
        with patch("zlib.compressobj") as zlib:
            zlib.side_effect = RuntimeError("PROBLEM!")
            for stdout in capture_io():
                self.stream_log = StreamLog("SLINT", "WRITE")
                self.stream_log.write(b"\x00\x01\x02\x03")
                self.stream_log.stop()
                time.sleep(0.001)
                self.assertIn(
                    "Error saving log file to bucket",
                    stdout.getvalue(),
                )

    def test_enables_and_disable_logging(self):
        self.stream_log = StreamLog("SLINT", "WRITE")
        self.assertTrue(self.stream_log.logging_enabled)
        self.stream_log.write(b"\x00\x01\x02\x03")
        self.stream_log.stop()
        time.sleep(0.001)
        self.assertFalse(self.stream_log.logging_enabled)
        self.assertEqual(len(self.mock_s3.files()), 1)
        self.stream_log.start()
        self.assertTrue(self.stream_log.logging_enabled)
        self.stream_log.write(b"\x00\x01\x02\x03")
        self.stream_log.stop()
        time.sleep(0.001)
        self.assertEqual(len(self.mock_s3.files()), 2)
