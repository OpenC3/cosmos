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

from openc3.utilities import limits_rollup


class TestLimitsRollupColor(unittest.TestCase):
    def test_maps_every_red_state_to_red(self):
        for state in ["RED", "RED_HIGH", "RED_LOW"]:
            self.assertEqual(limits_rollup.color(state), "RED")

    def test_maps_every_yellow_state_to_yellow(self):
        for state in ["YELLOW", "YELLOW_HIGH", "YELLOW_LOW"]:
            self.assertEqual(limits_rollup.color(state), "YELLOW")

    def test_maps_every_green_state_to_green(self):
        for state in ["GREEN", "GREEN_HIGH", "GREEN_LOW"]:
            self.assertEqual(limits_rollup.color(state), "GREEN")

    def test_keeps_blue(self):
        self.assertEqual(limits_rollup.color("BLUE"), "BLUE")

    def test_returns_none_for_a_missing_or_unknown_state(self):
        self.assertIsNone(limits_rollup.color(None))
        self.assertIsNone(limits_rollup.color("STALE"))


class TestLimitsRollupWorst(unittest.TestCase):
    def test_returns_the_most_severe_color(self):
        self.assertEqual(limits_rollup.worst(["GREEN", "BLUE"]), "GREEN")
        self.assertEqual(limits_rollup.worst(["GREEN_HIGH", "YELLOW_LOW", "BLUE"]), "YELLOW")
        self.assertEqual(limits_rollup.worst(["YELLOW_HIGH", "RED_LOW", "GREEN"]), "RED")
        self.assertEqual(limits_rollup.worst(["RED_HIGH", "YELLOW"]), "RED")

    def test_is_blue_only_when_every_state_is_blue(self):
        self.assertEqual(limits_rollup.worst(["BLUE", "BLUE"]), "BLUE")
        self.assertEqual(limits_rollup.worst(["BLUE", None]), "BLUE")
        self.assertEqual(limits_rollup.worst(["BLUE", "GREEN_LOW"]), "GREEN")

    def test_ignores_missing_states(self):
        self.assertEqual(limits_rollup.worst([None, "YELLOW_HIGH", None]), "YELLOW")

    def test_returns_none_when_no_state_counts(self):
        self.assertIsNone(limits_rollup.worst([]))
        self.assertIsNone(limits_rollup.worst([None]))


class TestLimitsRollupRollup(unittest.TestCase):
    def test_rolls_up_an_all_enabled_group(self):
        self.assertEqual(limits_rollup.rollup([("GREEN", True), ("YELLOW_LOW", True)]), ("YELLOW", "TRUE"))
        self.assertEqual(limits_rollup.rollup([("RED_HIGH", True), ("YELLOW_LOW", True)]), ("RED", "TRUE"))
        self.assertEqual(limits_rollup.rollup([("BLUE", True), ("GREEN_HIGH", True)]), ("GREEN", "TRUE"))

    def test_is_blue_when_every_member_is_blue(self):
        self.assertEqual(limits_rollup.rollup([("BLUE", True), ("BLUE", True)]), ("BLUE", "TRUE"))
        # A disabled member doesn't count
        self.assertEqual(limits_rollup.rollup([("BLUE", True), ("GREEN", False)]), ("BLUE", "PARTIAL"))
        # A BLUE nested group
        self.assertEqual(limits_rollup.rollup([("BLUE", "TRUE"), ("BLUE", True)]), ("BLUE", "TRUE"))

    def test_ignores_members_with_limits_disabled_and_reports_the_group_partial(self):
        self.assertEqual(limits_rollup.rollup([("RED", False), ("GREEN", True)]), ("GREEN", "PARTIAL"))

    def test_ignores_missing_states_on_enabled_members(self):
        self.assertEqual(limits_rollup.rollup([(None, True), ("YELLOW", True)]), ("YELLOW", "TRUE"))

    def test_has_no_color_when_enabled_members_have_no_state_yet(self):
        self.assertEqual(limits_rollup.rollup([(None, True)]), (None, "TRUE"))

    def test_is_disabled_with_no_enabled_members(self):
        self.assertEqual(limits_rollup.rollup([("RED", False), ("YELLOW", False)]), ("DISABLED", "FALSE"))

    def test_is_disabled_when_the_group_is_empty(self):
        self.assertEqual(limits_rollup.rollup([]), ("DISABLED", "FALSE"))

    def test_ignores_a_disabled_nested_group_and_reports_the_group_partial(self):
        self.assertEqual(limits_rollup.rollup([("DISABLED", "FALSE"), ("YELLOW", True)]), ("YELLOW", "PARTIAL"))

    def test_counts_a_partly_enabled_nested_group_and_reports_the_group_partial(self):
        self.assertEqual(limits_rollup.rollup([("RED", "PARTIAL"), ("GREEN", True)]), ("RED", "PARTIAL"))
        self.assertEqual(limits_rollup.rollup([("RED", "PARTIAL")]), ("RED", "PARTIAL"))

    def test_is_disabled_when_every_nested_group_is_disabled(self):
        self.assertEqual(limits_rollup.rollup([("DISABLED", "FALSE"), ("DISABLED", "FALSE")]), ("DISABLED", "FALSE"))
        self.assertEqual(limits_rollup.rollup([("DISABLED", "FALSE"), ("GREEN", False)]), ("DISABLED", "FALSE"))
