# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import importlib
import sys
import threading
import unittest
from unittest.mock import MagicMock, patch

import openc3.script
import openc3.script.api_shared
import openc3.utilities


running_script = None
RunningScript = None


class TestGoto(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Importing running_script replaces functions on openc3.script and
        # openc3.script.api_shared for the whole process, which breaks other tests.
        # Import it here and put those modules back when we're done.
        global running_script, RunningScript
        cls.saved_script = dict(vars(openc3.script))
        cls.saved_api_shared = dict(vars(openc3.script.api_shared))
        running_script = importlib.import_module("openc3.utilities.running_script")
        RunningScript = running_script.RunningScript

    @classmethod
    def tearDownClass(cls):
        for module, saved in (
            (openc3.script, cls.saved_script),
            (openc3.script.api_shared, cls.saved_api_shared),
        ):
            vars(module).clear()
            vars(module).update(saved)
        sys.modules.pop("openc3.utilities.running_script", None)
        if hasattr(openc3.utilities, "running_script"):
            delattr(openc3.utilities, "running_script")

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
