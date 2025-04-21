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
        #NOSONAR
        help(Logger)
