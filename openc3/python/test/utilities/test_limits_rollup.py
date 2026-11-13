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

    def test_maps_green_states_and_blue_to_green(self):
        for state in ["GREEN", "GREEN_HIGH", "GREEN_LOW", "BLUE"]:
            self.assertEqual(limits_rollup.color(state), "GREEN")

    def test_returns_none_for_a_missing_or_unknown_state(self):
        self.assertIsNone(limits_rollup.color(None))
        self.assertIsNone(limits_rollup.color("STALE"))


class TestLimitsRollupWorst(unittest.TestCase):
    def test_returns_the_most_severe_color(self):
        self.assertEqual(limits_rollup.worst(["GREEN", "BLUE"]), "GREEN")
        self.assertEqual(limits_rollup.worst(["GREEN_HIGH", "YELLOW_LOW", "BLUE"]), "YELLOW")
        self.assertEqual(limits_rollup.worst(["YELLOW_HIGH", "RED_LOW", "GREEN"]), "RED")
        self.assertEqual(limits_rollup.worst(["RED_HIGH", "YELLOW"]), "RED")

    def test_ignores_missing_states(self):
        self.assertEqual(limits_rollup.worst([None, "YELLOW_HIGH", None]), "YELLOW")

    def test_returns_none_when_no_state_counts(self):
        self.assertIsNone(limits_rollup.worst([]))
        self.assertIsNone(limits_rollup.worst([None]))


class TestLimitsRollupRollup(unittest.TestCase):
    def test_rolls_up_an_all_enabled_group(self):
        self.assertEqual(limits_rollup.rollup([("GREEN", True), ("YELLOW_LOW", True)]), ("YELLOW", True))
        self.assertEqual(limits_rollup.rollup([("RED_HIGH", True), ("YELLOW_LOW", True)]), ("RED", True))
        self.assertEqual(limits_rollup.rollup([("BLUE", True), ("GREEN_HIGH", True)]), ("GREEN", True))

    def test_ignores_members_with_limits_disabled_and_reports_not_enabled(self):
        self.assertEqual(limits_rollup.rollup([("RED", False), ("GREEN", True)]), ("GREEN", False))

    def test_ignores_missing_states_on_enabled_members(self):
        self.assertEqual(limits_rollup.rollup([(None, True), ("YELLOW", True)]), ("YELLOW", True))

    def test_has_no_color_when_enabled_members_have_no_state_yet(self):
        self.assertEqual(limits_rollup.rollup([(None, True)]), (None, True))

    def test_has_no_color_and_is_not_enabled_with_no_enabled_members(self):
        self.assertEqual(limits_rollup.rollup([("RED", False), ("YELLOW", False)]), (None, False))

    def test_has_no_color_and_is_not_enabled_when_the_group_is_empty(self):
        self.assertEqual(limits_rollup.rollup([]), (None, False))
