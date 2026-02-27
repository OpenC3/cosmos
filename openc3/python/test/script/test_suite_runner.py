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


if __name__ == "__main__":
    unittest.main()
