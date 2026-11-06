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

from openc3.models.scope_model import ScopeModel
from test.test_helper import mock_redis


class TestScopeModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_defaults_critical_cmd_approvers_to_1(self):
        self.assertEqual(ScopeModel(name="DEFAULT").critical_cmd_approvers, 1)
        self.assertEqual(ScopeModel(name="DEFAULT", critical_cmd_approvers=None).critical_cmd_approvers, 1)

    def test_converts_critical_cmd_approvers_to_int(self):
        self.assertEqual(ScopeModel(name="DEFAULT", critical_cmd_approvers="3").critical_cmd_approvers, 3)

    def test_raises_on_non_integer_critical_cmd_approvers(self):
        for value in [1.9, 2.0, "2oops", "1.9", "", " ", "-1", True]:
            with self.assertRaisesRegex(RuntimeError, rf"Invalid value for critical_cmd_approvers: {value} \(must be 1 to 10\)"):
                ScopeModel(name="DEFAULT", critical_cmd_approvers=value)
        # Base 10, matching Ruby
        self.assertEqual(ScopeModel(name="DEFAULT", critical_cmd_approvers="010").critical_cmd_approvers, 10)

    def test_raises_on_critical_cmd_approvers_less_than_1(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid value for critical_cmd_approvers"):
            ScopeModel(name="DEFAULT", critical_cmd_approvers=0)

    def test_allows_up_to_10_critical_cmd_approvers(self):
        self.assertEqual(ScopeModel(name="DEFAULT", critical_cmd_approvers=10).critical_cmd_approvers, 10)
        with self.assertRaisesRegex(RuntimeError, r"Invalid value for critical_cmd_approvers: 11 \(must be 1 to 10\)"):
            ScopeModel(name="DEFAULT", critical_cmd_approvers=11)

    def test_as_json_round_trip(self):
        model = ScopeModel(name="DEFAULT", critical_commanding="NORMAL", critical_cmd_approvers=2)
        json_data = model.as_json()
        self.assertEqual(json_data["critical_commanding"], "NORMAL")
        self.assertEqual(json_data["critical_cmd_approvers"], 2)
        model = ScopeModel.from_json(json_data)
        self.assertEqual(model.critical_cmd_approvers, 2)

    def test_from_json_without_critical_cmd_approvers(self):
        # Scopes saved before critical_cmd_approvers existed default to 1
        model = ScopeModel.from_json({"name": "DEFAULT", "critical_commanding": "ALL"})
        self.assertEqual(model.critical_cmd_approvers, 1)
