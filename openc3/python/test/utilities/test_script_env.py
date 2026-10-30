# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import unittest
from unittest.mock import MagicMock, patch

from openc3.utilities import script_env


class TestScriptEnv(unittest.TestCase):
    def setUp(self):
        # patch.dict snapshots os.environ and restores it on stop
        patcher = patch.dict(os.environ)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_cleared_vars_include_unused_vars(self):
        for key in script_env.UNUSED_VARS:
            self.assertIn(key, script_env.CLEARED_VARS)

    def test_clear_credentials_connects_before_clearing(self):
        for key in script_env.CLEARED_VARS:
            os.environ[key] = "value"
        os.environ["OPENC3_SCOPE"] = "DEFAULT"
        calls = MagicMock()

        def record(name):
            def side_effect():
                calls(name, all(key in os.environ for key in script_env.CLEARED_VARS))

            return side_effect

        with (
            patch.object(script_env.Bucket, "get_client", side_effect=record("bucket")),
            patch.object(script_env.Store, "instance", side_effect=record("store")),
            patch.object(script_env.EphemeralStore, "instance", side_effect=record("ephemeral")),
        ):
            script_env.clear_credentials()

        self.assertEqual(
            [c.args for c in calls.call_args_list],
            [("bucket", True), ("store", True), ("ephemeral", True)],
        )
        for key in script_env.CLEARED_VARS:
            self.assertNotIn(key, os.environ)
        self.assertEqual(os.environ["OPENC3_SCOPE"], "DEFAULT")

    def test_clear_credentials_ignores_missing_vars(self):
        for key in script_env.CLEARED_VARS:
            os.environ.pop(key, None)
        with (
            patch.object(script_env.Bucket, "get_client"),
            patch.object(script_env.Store, "instance"),
            patch.object(script_env.EphemeralStore, "instance"),
        ):
            script_env.clear_credentials()
        for key in script_env.CLEARED_VARS:
            self.assertNotIn(key, os.environ)
