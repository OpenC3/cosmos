# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import re
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from openc3.script.suite_results import SuiteResults


class TestSuiteResults(unittest.TestCase):
    def setUp(self):
        self.suite_results = SuiteResults()
        # Freeze time for consistent testing
        self.frozen_time_utc = datetime(2025, 11, 22, 15, 30, 45, 123456, tzinfo=timezone.utc)

    def test_format_timestamp_always_uses_utc(self):
        """Test that timestamp is always formatted as UTC with Z suffix"""
        self.suite_results._report = []
        self.suite_results.write("Test message")
        report = self.suite_results.report()

        # Should contain a timestamp in UTC format with Z suffix
        pattern = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Test message"
        self.assertIsNotNone(re.search(pattern, report), f"Expected UTC timestamp format, got: {report}")

    @patch("openc3.script.suite_results.datetime")
    def test_write_appends_to_report(self, mock_datetime):
        """Test that write appends messages to the report"""
        mock_datetime.now.return_value = self.frozen_time_utc

        self.suite_results._report = []
        self.suite_results.write("First message")
        self.suite_results.write("Second message")
        report = self.suite_results.report()

        self.assertIn("First message", report)
        self.assertIn("Second message", report)

    def test_puts_is_alias_for_write(self):
        """Test that puts method is an alias for write"""
        self.suite_results._report = []
        self.suite_results.puts("Test puts message")
        report = self.suite_results.report()

        # Should contain a timestamp in UTC format with Z suffix
        pattern = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Test puts message"
        self.assertIsNotNone(re.search(pattern, report))

    @patch("openc3.script.suite_results.datetime")
    def test_print_is_alias_for_write(self, mock_datetime):
        """Test that print method is an alias for write"""
        mock_datetime.now.return_value = self.frozen_time_utc

        self.suite_results._report = []
        self.suite_results.print("Test print message")
        report = self.suite_results.report()

        # Should contain a timestamp in UTC format with Z suffix
        import re

        pattern = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z: Test print message"
        self.assertIsNotNone(re.search(pattern, report))

    def test_integration_full_report(self):
        """Test that formatted timestamps appear in the full report"""

        # Simulate a test run
        class TestSuiteClass:
            __name__ = "TestSuite"

        self.suite_results.start("Test", TestSuiteClass)
        self.suite_results.puts("Running test 1")
        self.suite_results.puts("Running test 2")
        self.suite_results.complete()

        report = self.suite_results.report()

        self.assertIn("--- Script Report ---", report)
        self.assertIn("Results:", report)

        # Check for timestamps in UTC format with Z suffix
        import re

        pattern = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z:"
        matches = re.findall(pattern, report)
        self.assertGreater(len(matches), 0, "Expected to find UTC timestamps in the report")

    def test_report_returns_joined_lines(self):
        """Test that report() returns all lines joined with newlines"""
        self.suite_results._report = ["Line 1", "Line 2", "Line 3"]
        report = self.suite_results.report()
        self.assertEqual(report, "Line 1\nLine 2\nLine 3")

    def test_timestamp_format_uses_z_suffix_not_offset(self):
        """Test that UTC timestamp uses Z suffix, not +00:00"""
        self.suite_results._report = []
        self.suite_results.write("Test message")
        report = self.suite_results.report()

        # Should use Z suffix
        self.assertIn("Z:", report)
        # Should NOT use +00:00 offset
        self.assertNotIn("+00:00", report)


if __name__ == "__main__":
    unittest.main()
