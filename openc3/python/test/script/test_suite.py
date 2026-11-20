# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import sys
import unittest

from openc3.io.stderr import Stderr
from openc3.io.stdout import Stdout
from openc3.script.suite import Group, ScriptResult, ScriptStatus, Suite


class CurrentSuiteGroup(Group):
    seen_suite = None

    def script_record_suite(self):
        CurrentSuiteGroup.seen_suite = Group.current_suite()


class CurrentSuiteSuite(Suite):
    def __init__(self):
        self.add_group(CurrentSuiteGroup)


class StderrGroup(Group):
    def setup(self):
        # Intentionally empty, used to check the setup status string
        pass

    def script_stderr(self):
        print("stderr text", file=sys.stderr)


class EqualSuite(Suite):
    pass


class OtherSuite(Suite):
    pass


class TestSuiteAndGroup(unittest.TestCase):
    def setUp(self):
        self.orig_stdout = sys.stdout
        self.orig_stderr = sys.stderr

    def tearDown(self):
        sys.stdout = self.orig_stdout
        sys.stderr = self.orig_stderr
        ScriptResult.suite = None

    def test_script_result_stores_the_running_suite(self):
        ScriptResult.suite = "MySuite"
        result = ScriptResult()
        self.assertEqual(result.suite, "MySuite")
        ScriptResult.suite = None
        self.assertIsNone(ScriptResult().suite)

    def test_current_suite_returns_suite_name_while_running(self):
        CurrentSuiteGroup.seen_suite = None
        suite = CurrentSuiteSuite()
        list(suite.run_group(CurrentSuiteGroup))
        self.assertEqual(CurrentSuiteGroup.seen_suite, "CurrentSuiteSuite")

    def test_run_method_removes_output_buffer_from_stdout_and_stderr(self):
        group = StderrGroup()
        result = group.run_script("script_stderr")
        self.assertIn("stderr text", result.output)
        self.assertNotIn(group.output_io, Stdout.instance().streams)
        self.assertNotIn(group.output_io, Stderr.instance().streams)

    def test_group_setup_status_uses_class_name(self):
        group = StderrGroup()
        # run_script sets its own status, so stub it to see the run_setup status
        group.run_script = lambda method_name: None
        group.run_setup()
        self.assertEqual(ScriptStatus.instance().status, "StderrGroup : setup")

    def test_suites_compare_and_hash_by_name(self):
        self.assertEqual(EqualSuite(), EqualSuite())
        self.assertNotEqual(EqualSuite(), OtherSuite())
        self.assertEqual(len({EqualSuite(), EqualSuite(), OtherSuite()}), 2)


if __name__ == "__main__":
    unittest.main()
