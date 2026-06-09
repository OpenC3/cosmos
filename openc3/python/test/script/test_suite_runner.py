# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import types
import unittest

from openc3.script.suite import Group, Suite
from openc3.script.suite_runner import SuiteRunner


class OrderedGroup(Group):
    def test_z_last(self):
        # Empty test method to verify order of test methods in suite runner
        pass

    def test_a_first(self):
        # Empty test method to verify order of test methods in suite runner
        pass

    def test_m_middle(self):
        # Empty test method to verify order of test methods in suite runner
        pass


class OrderedSuite(Suite):
    def __init__(self):
        self.add_script(OrderedGroup, "test_m_middle")
        self.add_script(OrderedGroup, "test_z_last")
        self.add_script(OrderedGroup, "test_a_first")


class NoSetupTeardownGroup(Group):
    def test_something(self):
        # Intentionally empty — used only to trigger missing-method/setup/teardown error paths
        pass


class MissingScriptSuite(Suite):
    def __init__(self):
        self.add_script(NoSetupTeardownGroup, "nonexistent_method")


class MissingSetupSuite(Suite):
    def __init__(self):
        self.add_group_setup(NoSetupTeardownGroup)


class MissingTeardownSuite(Suite):
    def __init__(self):
        self.add_group_teardown(NoSetupTeardownGroup)


# Fixtures for SuiteRunner option validation. OptionsGroup is part of
# OptionsSuite; OtherGroup is intentionally left out of any suite plan.
class SuiteRunnerOptionsGroup(Group):
    def test_valid_script(self):
        pass


class SuiteRunnerOptionsSuite(Suite):
    def __init__(self):
        self.add_group(SuiteRunnerOptionsGroup)


class SuiteRunnerOtherGroup(Group):
    def test_other(self):
        pass


class TestSuiteRunner(unittest.TestCase):
    def test_build_suites_creates_a_list_of_suites(self):
        mod = types.ModuleType("test_mod")
        mod.OrderedGroup = OrderedGroup
        mod.OrderedSuite = OrderedSuite
        suites = SuiteRunner.build_suites(from_module=mod)
        self.assertIn("OrderedSuite", suites)
        self.assertIn("groups", suites["OrderedSuite"])
        self.assertIn("OrderedGroup", suites["OrderedSuite"]["groups"])

    def test_build_suites_preserves_add_script_insertion_order(self):
        mod = types.ModuleType("test_mod")
        mod.OrderedGroup = OrderedGroup
        mod.OrderedSuite = OrderedSuite
        suites = SuiteRunner.build_suites(from_module=mod)
        # Scripts should be in the order they were added, not alphabetical
        scripts = suites["OrderedSuite"]["groups"]["OrderedGroup"]["scripts"]
        self.assertEqual(scripts, ["test_m_middle", "test_z_last", "test_a_first"])

    def test_build_suites_raises_attribute_error_for_missing_script(self):
        mod = types.ModuleType("test_mod")
        mod.NoSetupTeardownGroup = NoSetupTeardownGroup
        mod.MissingScriptSuite = MissingScriptSuite
        with self.assertRaises(AttributeError, msg="nonexistent_method"):
            SuiteRunner.build_suites(from_module=mod)

    def test_build_suites_raises_attribute_error_for_missing_setup(self):
        mod = types.ModuleType("test_mod")
        mod.NoSetupTeardownGroup = NoSetupTeardownGroup
        mod.MissingSetupSuite = MissingSetupSuite
        with self.assertRaises(AttributeError, msg="setup"):
            SuiteRunner.build_suites(from_module=mod)

    def test_build_suites_raises_attribute_error_for_missing_teardown(self):
        mod = types.ModuleType("test_mod")
        mod.NoSetupTeardownGroup = NoSetupTeardownGroup
        mod.MissingTeardownSuite = MissingTeardownSuite
        with self.assertRaises(AttributeError, msg="teardown"):
            SuiteRunner.build_suites(from_module=mod)

    # These validate the suite_runner option combinations that flow through
    # RunningScript.run into SuiteRunner.start / setup / teardown (all of
    # which funnel through SuiteRunner.execute).
    def _build_options_suite(self):
        mod = types.ModuleType("test_mod")
        mod.SuiteRunnerOptionsGroup = SuiteRunnerOptionsGroup
        mod.SuiteRunnerOptionsSuite = SuiteRunnerOptionsSuite
        SuiteRunner.build_suites(from_module=mod)

    def test_start_raises_when_script_given_without_group(self):
        self._build_options_suite()
        with self.assertRaisesRegex(RuntimeError, "Script test_valid_script requires a Group"):
            SuiteRunner.start(SuiteRunnerOptionsSuite, None, "test_valid_script")

    def test_start_raises_for_unknown_suite(self):
        self._build_options_suite()
        with self.assertRaisesRegex(RuntimeError, "Suite .* not found"):
            SuiteRunner.start(str)

    def test_start_raises_for_group_not_in_suite(self):
        self._build_options_suite()
        with self.assertRaisesRegex(RuntimeError, "Group .* not found in Suite"):
            SuiteRunner.start(SuiteRunnerOptionsSuite, SuiteRunnerOtherGroup)


if __name__ == "__main__":
    unittest.main()
