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

import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import MagicMock, patch

import openc3.script
import openc3.script.api_shared
import openc3.utilities


# Importing running_script monkeypatches openc3.script and api_shared at module
# level (RUNNING_SCRIPT, openc3_script_sleep, etc). Import it only while this
# module's tests run and restore the originals afterwards so other test files
# don't see a RunningScript with no instance.
_PATCHED_MODULES = (openc3.script, openc3.script.api_shared)
_saved_attrs = {}
running_script = None
RunningScript = None


def setUpModule():
    global running_script, RunningScript
    for module in _PATCHED_MODULES:
        _saved_attrs[module] = dict(vars(module))
    from openc3.utilities import running_script as rs

    running_script = rs
    RunningScript = rs.RunningScript


def tearDownModule():
    for module, saved in _saved_attrs.items():
        for name, value in list(vars(module).items()):
            if name not in saved and not isinstance(value, types.ModuleType):
                delattr(module, name)
        for name, value in saved.items():
            setattr(module, name, value)
    sys.modules.pop("openc3.utilities.running_script", None)
    if hasattr(openc3.utilities, "running_script"):
        delattr(openc3.utilities, "running_script")


class TestOpenBucketDialog(unittest.TestCase):
    def setUp(self):
        self.instance = MagicMock()
        self.instance.scope.return_value = "DEFAULT"
        self.instance.user_input = {
            "bucket": "OPENC3_CONFIG_BUCKET",
            "path": "DEFAULT/targets/INST/procedures/test.py",
            "filename": "test.py",
        }
        patcher = patch.object(running_script.RunningScript, "instance", self.instance)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_returns_file_with_bucket_info(self):
        file = tempfile.NamedTemporaryFile(mode="w+b")  # noqa: SIM115 - closed below
        self.addCleanup(file.close)
        with patch.object(running_script, "_get_storage_file", return_value=file) as get_file:
            result = running_script.running_script_method("open_bucket_dialog", "Title")
        get_file.assert_called_once_with(
            "targets/INST/procedures/test.py", bucket="OPENC3_CONFIG_BUCKET", scope="DEFAULT"
        )
        self.assertIs(result, file)
        self.assertEqual(result.filename(), "test.py")
        self.assertEqual(result.bucket(), "OPENC3_CONFIG_BUCKET")
        self.assertEqual(result.bucket_path(), "DEFAULT/targets/INST/procedures/test.py")


class TestGoto(unittest.TestCase):
    def setUp(self):
        # Skip __init__ since it redirects stdout/stderr and talks to Redis
        self.running_script = RunningScript.__new__(RunningScript)
        self.running_script.script_status = MagicMock(state="breakpoint", current_filename="test_script.py")
        self.running_script.execute_while_paused_info = None
        RunningScript.instance = self.running_script
        start_patcher = patch.object(running_script, "start")
        self.mock_start = start_patcher.start()
        self.addCleanup(start_patcher.stop)

    def tearDown(self):
        RunningScript.instance = None

    def test_goto_off_run_thread_hands_off_to_run_thread(self):
        mock_start = self.mock_start
        # The debug prompt execs goto on the redis subscriber thread. Running the
        # script there deadlocks at the next pause because that thread is the one
        # that processes go/step/stop, so goto must defer to the run thread.
        patcher = patch.object(RunningScript, "run_thread", threading.Thread(target=lambda: None))
        patcher.start()
        self.addCleanup(patcher.stop)

        running_script.goto(9)
        self.assertEqual(
            self.running_script.execute_while_paused_info,
            {"filename": "test_script.py", "line_no": 9, "end_line_no": None, "bind_variables": True},
        )

        running_script.goto("other.py", 3)
        self.assertEqual(
            self.running_script.execute_while_paused_info,
            {"filename": "other.py", "line_no": 3, "end_line_no": None, "bind_variables": True},
        )
        mock_start.assert_not_called()

    def test_queued_goto_to_another_file_keeps_binding(self):
        patcher = patch.object(RunningScript, "run_thread", threading.Thread(target=lambda: None))
        patcher.start()
        self.addCleanup(patcher.stop)
        running_script.goto("other.py", 3)

        self.running_script.check_execute_while_paused()
        self.mock_start.assert_called_with("other.py", line_no=3, bind_variables=True, complete=True)

    def test_editor_goto_binds_only_for_current_file(self):
        self.running_script.execute_while_paused("other.py", 3)

        self.running_script.check_execute_while_paused()
        self.mock_start.assert_called_with("other.py", line_no=3, bind_variables=False, complete=True)

    def test_goto_on_run_thread_starts_directly(self):
        mock_start = self.mock_start
        patcher = patch.object(RunningScript, "run_thread", threading.current_thread())
        patcher.start()
        self.addCleanup(patcher.stop)

        running_script.goto(9)
        mock_start.assert_called_with("test_script.py", line_no=9, bind_variables=True, complete=True)

        running_script.goto("other.py", 3)
        mock_start.assert_called_with("other.py", line_no=3, bind_variables=True, complete=True)
        self.assertIsNone(self.running_script.execute_while_paused_info)


if __name__ == "__main__":
    unittest.main()
