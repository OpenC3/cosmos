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

import os
import time
import json
import unittest
from io import StringIO
from unittest.mock import *
from test.test_helper import *
from openc3.utilities.logger import Logger


class TestLogger(unittest.TestCase):
    def setUp(self):
        Logger.stdout = True

    def test_initializes_the_level_to_info(self):
        self.assertEqual(Logger().level, Logger.INFO)

    def test_gets_and_set_the_level(self):
        Logger.level = Logger.DEBUG
        self.assertEqual(Logger.level, Logger.DEBUG)

    def verify_output(self, level, method):
        orig = sys.stdout
        sys.stdout = StringIO()
        Logger.level = level
        getattr(Logger, method)("Message1")
        data = json.loads(sys.stdout.getvalue())
        self.assertEqual(data["level"], method.upper())
        self.assertIn("Message1", data["message"])
        # Verify we can round trip the time from a string and it makes sense
        self.assertGreaterEqual(time.time_ns(), int(str(data["time"])))
        self.assertGreaterEqual(int(str(data["time"])), time.time_ns() - 1_000_000)
        sys.stdout = orig

    def verify_no_output(self, level, method):
        orig = sys.stdout
        sys.stdout = StringIO()
        Logger.level = level
        getattr(Logger, method)("Message2")
        self.assertEqual(sys.stdout.getvalue(), "")
        sys.stdout = orig

    def test_debug_prints_if_level_is_debug_or_higher(self):
        self.verify_output(Logger.DEBUG, "debug")
        self.verify_output(Logger.DEBUG, "info")
        self.verify_output(Logger.DEBUG, "warn")
        self.verify_output(Logger.DEBUG, "error")
        self.verify_output(Logger.DEBUG, "fatal")
        self.verify_no_output(Logger.INFO, "debug")
        self.verify_no_output(Logger.WARN, "debug")
        self.verify_no_output(Logger.ERROR, "debug")
        self.verify_no_output(Logger.FATAL, "debug")

    def test_info_prints_if_level_is_info_or_higher(self):
        self.verify_output(Logger.INFO, "info")
        self.verify_output(Logger.INFO, "warn")
        self.verify_output(Logger.INFO, "error")
        self.verify_output(Logger.INFO, "fatal")
        self.verify_no_output(Logger.WARN, "info")
        self.verify_no_output(Logger.ERROR, "info")
        self.verify_no_output(Logger.FATAL, "info")

    def test_warn_prints_if_level_is_warn_or_higher(self):
        self.verify_output(Logger.WARN, "warn")
        self.verify_output(Logger.WARN, "error")
        self.verify_output(Logger.WARN, "fatal")
        self.verify_no_output(Logger.ERROR, "warn")
        self.verify_no_output(Logger.FATAL, "warn")

    def test_error_prints_if_level_is_error_or_higher(self):
        self.verify_output(Logger.ERROR, "error")
        self.verify_output(Logger.ERROR, "fatal")
        self.verify_no_output(Logger.FATAL, "info")

    def test_fatal_only_prints_if_level_is_fatal(self):
        self.verify_output(Logger.FATAL, "fatal")

    def test_help(self):
        help(Logger) # NOSONAR


class TestLogMessage(unittest.TestCase):
    def setUp(self):
        Logger.stdout = True
        Logger.level = Logger.INFO
        Logger.no_store = True
        Logger.microservice_name = None
        Logger.detail_string = None

    def tearDown(self):
        sys.stdout = sys.__stdout__
        sys.stderr = sys.__stderr__

    def test_log_message_includes_required_fields(self):
        """Test that log_message includes all required fields in output"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test message", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["level"], "INFO")
        self.assertEqual(data["message"], "Test message")
        self.assertIn("time", data)
        self.assertIn("@timestamp", data)
        self.assertIn("container_name", data)

    def test_log_message_with_microservice_name(self):
        """Test that microservice_name is included when set"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.microservice_name = "test-service"
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["microservice_name"], "test-service")

    def test_log_message_without_microservice_name(self):
        """Test that microservice_name is omitted when None"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.microservice_name = None
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertNotIn("microservice_name", data)

    def test_log_message_with_detail_string(self):
        """Test that detail is included when detail_string is set"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.detail_string = "Additional details"
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["detail"], "Additional details")

    def test_log_message_without_detail_string(self):
        """Test that detail is omitted when detail_string is None"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.detail_string = None
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertNotIn("detail", data)

    def test_log_message_with_user(self):
        """Test that user is included when provided"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user="testuser", type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["user"], "testuser")

    def test_log_message_without_user(self):
        """Test that user is omitted when None"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertNotIn("user", data)

    def test_log_message_with_type(self):
        """Test that type is included when provided"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type="notification", url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["type"], "notification")

    def test_log_message_without_type(self):
        """Test that type is omitted when None"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=None, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertNotIn("type", data)

    def test_log_message_with_url(self):
        """Test that url is included when provided"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url="http://example.com")
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["url"], "http://example.com")

    def test_log_message_without_url(self):
        """Test that url is omitted when None"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertNotIn("url", data)

    def test_log_message_with_other_dict(self):
        """Test that other dict merges additional fields"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        other = {"request_id": "12345", "custom_field": "custom_value"}
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None, other=other)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["request_id"], "12345")
        self.assertEqual(data["custom_field"], "custom_value")

    def test_log_message_with_nested_other_dict(self):
        """Test that nested structures in other dict are preserved"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        other = {
            "metadata": {
                "source": "test",
                "version": "1.0"
            },
            "tags": ["error", "critical"]
        }
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None, other=other)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertEqual(data["metadata"]["source"], "test")
        self.assertEqual(data["metadata"]["version"], "1.0")
        self.assertEqual(data["tags"], ["error", "critical"])

    def test_log_message_without_other(self):
        """Test that other is handled when None"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None, other=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        # Should only have standard fields
        self.assertIn("level", data)
        self.assertIn("message", data)

    def test_log_message_with_none_message(self):
        """Test that message can be None"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", None, scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        self.assertNotIn("message", data)

    @patch.dict(os.environ, {"OPENC3_LOG_STDERR": ""}, clear=False)
    def test_log_message_stdout_when_stderr_not_enabled(self):
        """Test that all log levels go to stdout when OPENC3_LOG_STDERR is not enabled"""
        from openc3.environment import OPENC3_LOG_STDERR
        # Force reload to pick up the environment variable
        import importlib
        import openc3.environment
        importlib.reload(openc3.environment)
        
        orig_stdout = sys.stdout
        orig_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        
        logger = Logger()
        logger.log_message("WARN", "Warning", scope="TEST", user=None, type=Logger.LOG, url=None)
        logger.log_message("ERROR", "Error", scope="TEST", user=None, type=Logger.LOG, url=None)
        logger.log_message("FATAL", "Fatal", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        stdout_output = sys.stdout.getvalue()
        stderr_output = sys.stderr.getvalue()
        
        sys.stdout = orig_stdout
        sys.stderr = orig_stderr
        
        # All should go to stdout
        self.assertIn("Warning", stdout_output)
        self.assertIn("Error", stdout_output)
        self.assertIn("Fatal", stdout_output)
        self.assertEqual(stderr_output, "")

    @patch('openc3.utilities.logger.OPENC3_LOG_STDERR', True)
    def test_log_message_stderr_when_enabled_for_warn(self):
        """Test that WARN goes to stderr when OPENC3_LOG_STDERR is enabled"""
        orig_stdout = sys.stdout
        orig_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        
        logger = Logger()
        logger.log_message("WARN", "Warning", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        stdout_output = sys.stdout.getvalue()
        stderr_output = sys.stderr.getvalue()
        
        sys.stdout = orig_stdout
        sys.stderr = orig_stderr
        
        self.assertEqual(stdout_output, "")
        self.assertIn("Warning", stderr_output)
        data = json.loads(stderr_output)
        self.assertEqual(data["level"], "WARN")

    @patch('openc3.utilities.logger.OPENC3_LOG_STDERR', True)
    def test_log_message_stderr_when_enabled_for_error(self):
        """Test that ERROR goes to stderr when OPENC3_LOG_STDERR is enabled"""
        orig_stdout = sys.stdout
        orig_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        
        logger = Logger()
        logger.log_message("ERROR", "Error message", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        stdout_output = sys.stdout.getvalue()
        stderr_output = sys.stderr.getvalue()
        
        sys.stdout = orig_stdout
        sys.stderr = orig_stderr
        
        self.assertEqual(stdout_output, "")
        self.assertIn("Error message", stderr_output)

    @patch('openc3.utilities.logger.OPENC3_LOG_STDERR', True)
    def test_log_message_stderr_when_enabled_for_fatal(self):
        """Test that FATAL goes to stderr when OPENC3_LOG_STDERR is enabled"""
        orig_stdout = sys.stdout
        orig_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        
        logger = Logger()
        logger.log_message("FATAL", "Fatal error", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        stdout_output = sys.stdout.getvalue()
        stderr_output = sys.stderr.getvalue()
        
        sys.stdout = orig_stdout
        sys.stderr = orig_stderr
        
        self.assertEqual(stdout_output, "")
        self.assertIn("Fatal error", stderr_output)

    @patch('openc3.utilities.logger.OPENC3_LOG_STDERR', True)
    def test_log_message_stdout_for_info_when_stderr_enabled(self):
        """Test that INFO still goes to stdout when OPENC3_LOG_STDERR is enabled"""
        orig_stdout = sys.stdout
        orig_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Info message", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        stdout_output = sys.stdout.getvalue()
        stderr_output = sys.stderr.getvalue()
        
        sys.stdout = orig_stdout
        sys.stderr = orig_stderr
        
        self.assertIn("Info message", stdout_output)
        self.assertEqual(stderr_output, "")

    @patch('openc3.utilities.logger.OPENC3_LOG_STDERR', True)
    def test_log_message_stdout_for_debug_when_stderr_enabled(self):
        """Test that DEBUG goes to stdout when OPENC3_LOG_STDERR is enabled"""
        orig_stdout = sys.stdout
        orig_stderr = sys.stderr
        sys.stdout = StringIO()
        sys.stderr = StringIO()
        
        logger = Logger()
        logger.log_message("DEBUG", "Debug message", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        stdout_output = sys.stdout.getvalue()
        stderr_output = sys.stderr.getvalue()
        
        sys.stdout = orig_stdout
        sys.stderr = orig_stderr
        
        self.assertIn("Debug message", stdout_output)
        self.assertEqual(stderr_output, "")

    def test_log_message_respects_stdout_false(self):
        """Test that no output when stdout is False"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.stdout = False
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        self.assertEqual(output, "")

    @patch("openc3.utilities.logger.EphemeralStoreQueued")
    def test_log_message_writes_to_store_with_scope(self, mock_store):
        """Test that log messages are written to store with scope"""
        logger = Logger()
        logger.no_store = False
        logger.log_message("INFO", "Test", scope="TESTSCOPE", user=None, type=Logger.LOG, url=None)
        
        mock_store.write_topic.assert_called_once()
        call_args = mock_store.write_topic.call_args
        self.assertEqual(call_args[0][0], "TESTSCOPE__openc3_log_messages")
        self.assertIsInstance(call_args[0][1], dict)
        self.assertEqual(call_args[0][1]["message"], "Test")

    @patch("openc3.utilities.logger.EphemeralStoreQueued")
    def test_log_message_writes_to_store_without_scope(self, mock_store):
        """Test that log messages are written to NOSCOPE when scope is None"""
        logger = Logger()
        logger.no_store = False
        logger.log_message("INFO", "Test", scope=None, user=None, type=Logger.LOG, url=None)
        
        mock_store.write_topic.assert_called_once()
        call_args = mock_store.write_topic.call_args
        self.assertEqual(call_args[0][0], "NOSCOPE__openc3_log_messages")

    @patch("openc3.utilities.logger.EphemeralStoreQueued")
    def test_log_message_does_not_write_to_store_when_no_store_true(self, mock_store):
        """Test that log messages are not written to store when no_store is True"""
        logger = Logger()
        logger.no_store = True
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        mock_store.write_topic.assert_not_called()

    def test_log_message_timestamp_format(self):
        """Test that timestamp is in correct ISO format with Z suffix"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        timestamp = data["@timestamp"]
        # Verify format: YYYY-MM-DDTHH:MM:SS.ffffffZ
        self.assertTrue(timestamp.endswith("Z"))
        self.assertIn("T", timestamp)
        # Should be parseable
        from datetime import datetime
        parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        self.assertIsNotNone(parsed)

    def test_log_message_time_is_nanoseconds(self):
        """Test that time field is in nanoseconds"""
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        before_ns = time.time_ns()
        logger.log_message("INFO", "Test", scope="TEST", user=None, type=Logger.LOG, url=None)
        after_ns = time.time_ns()
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        data = json.loads(output)
        log_time = data["time"]
        # Verify it's in the expected range (nanoseconds)
        self.assertGreaterEqual(log_time, before_ns)
        self.assertLessEqual(log_time, after_ns)

    def test_log_message_thread_safety(self):
        """Test that log_message is thread-safe with mutex"""
        import threading
        orig_stdout = sys.stdout
        sys.stdout = StringIO()
        
        logger = Logger()
        results = []
        
        def log_from_thread(n):
            logger.log_message("INFO", f"Message {n}", scope="TEST", user=None, type=Logger.LOG, url=None)
        
        threads = [threading.Thread(target=log_from_thread, args=(i,)) for i in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        
        output = sys.stdout.getvalue()
        sys.stdout = orig_stdout
        
        lines = output.strip().split("\n")
        self.assertEqual(len(lines), 10)
        # Each line should be valid JSON
        for line in lines:
            data = json.loads(line)
            self.assertIn("Message", data["message"])
