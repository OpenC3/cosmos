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
from io import StringIO
from unittest.mock import MagicMock, patch

import openc3.script
import openc3.script.api_shared
import openc3.utilities
from openc3.io.io_multiplexer import IoMultiplexer


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
        self.running_script.pause = False
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

    def test_goto_while_paused_lands_paused(self):
        self.running_script.script_status.state = "paused"
        self.running_script.pause = False
        self.running_script.execute_while_paused("test_script.py", 7)

        # The goto line must pause before it executes so the user can inspect it
        pause_at_start = []
        self.mock_start.side_effect = lambda *args, **kwargs: pause_at_start.append(self.running_script.pause)
        self.running_script.check_execute_while_paused()
        self.mock_start.assert_called_with("test_script.py", line_no=7, bind_variables=True, complete=True)
        self.assertEqual(pause_at_start, [True])

    def test_goto_while_running_jumps_without_pausing(self):
        self.running_script.script_status.state = "running"
        self.running_script.pause = False
        self.running_script.execute_while_paused("test_script.py", 7)

        pause_at_start = []
        self.mock_start.side_effect = lambda *args, **kwargs: pause_at_start.append(self.running_script.pause)
        self.running_script.check_execute_while_paused(pause=False)
        self.mock_start.assert_called_with("test_script.py", line_no=7, bind_variables=True, complete=True)
        self.assertEqual(pause_at_start, [False])

    def test_execute_selection_rejected_while_running(self):
        self.running_script.script_status.state = "running"
        self.running_script.scriptrunner_puts = MagicMock()
        self.running_script.execute_while_paused("test_script.py", 7, 9)
        self.assertIsNone(self.running_script.execute_while_paused_info)

    def test_goto_rejected_while_waiting_on_prompt(self):
        self.running_script.script_status.state = "waiting"
        self.running_script.scriptrunner_puts = MagicMock()
        self.running_script.execute_while_paused("test_script.py", 7)
        self.assertIsNone(self.running_script.execute_while_paused_info)

    def test_pre_line_performs_goto_requested_while_running(self):
        rs = self.running_script
        rs.script_status.state = "running"
        rs.pause = False
        rs.stop = False
        rs.go = False
        rs.use_instrumentation = True
        rs.line_offset = 0
        rs.handle_potential_tab_change = MagicMock()
        rs.update_running_script_store = MagicMock()
        rs.handle_pause = MagicMock()
        rs.handle_line_delay = MagicMock()
        rs.execute_while_paused("test_script.py", 7)

        with patch.object(running_script, "running_script_anycable_publish"):
            rs.pre_line_instrumentation("test_script.py", 3, {}, {})
        self.mock_start.assert_called_with("test_script.py", line_no=7, bind_variables=True, complete=True)

    def test_debug_prompt_goto_forms(self):
        rs = self.running_script
        rs.script_status.state = "paused"
        rs.script_engine = None
        rs.script_binding = [{}, {}]
        rs.handle_output_io = MagicMock()
        rs.current_filename = MagicMock(return_value="test_script.py")
        cases = [
            ("GOTO 32", "test_script.py", 32),
            ("goto 32", "test_script.py", 32),
            ("  Goto   32  ", "test_script.py", 32),
            ("goto(32)", "test_script.py", 32),
            ("goto INST/procedures/other.py 12", "INST/procedures/other.py", 12),
            ("GOTO 'other.py', 12", "other.py", 12),
            ('goto("other.py", 12)', "other.py", 12),
        ]
        for text, filename, line_no in cases:
            with self.subTest(text=text):
                rs.execute_while_paused_info = None
                with patch("builtins.exec") as mock_exec:
                    rs.debug(text)
                mock_exec.assert_not_called()
                self.assertEqual(
                    rs.execute_while_paused_info,
                    {"filename": filename, "line_no": line_no, "end_line_no": None, "bind_variables": True},
                )

    def test_debug_prompt_other_goto_text_is_executed(self):
        rs = self.running_script
        rs.script_engine = None
        rs.script_binding = [{}, {}]
        rs.handle_output_io = MagicMock()
        rs.current_filename = MagicMock(return_value="test_script.py")
        with patch("builtins.exec") as mock_exec:
            rs.debug("goto_line = 5")
        mock_exec.assert_called_once()
        self.assertIsNone(rs.execute_while_paused_info)

    COLLECT_PY = (
        "def collect(type, duration):\n"
        "    collects = tlm('INST HEALTH_STATUS COLLECTS')\n"
        "    if collects > 10:\n"
        "        return\n"
        "    else:\n"
        "        cmd(f'INST COLLECT with TYPE {type}')\n"
        "print('done')\n"
    )

    def test_validate_partial_script_rejects_start_inside_block(self):
        # Line 5 is the else: of an if that starts above it
        partial = "".join(self.COLLECT_PY.splitlines(keepends=True)[4:])
        with self.assertRaisesRegex(
            RunningScript.InvalidStartLineError, r"Cannot start at line 5 of collect.py.*inside a method or block"
        ):
            RunningScript.validate_partial_script(self.COLLECT_PY, partial, "collect.py", 5, None)

    def test_validate_partial_script_rejects_incomplete_selection(self):
        partial = "".join(self.COLLECT_PY.splitlines(keepends=True)[2:3])
        with self.assertRaisesRegex(RunningScript.InvalidStartLineError, r"Cannot run lines 3-3 of collect.py"):
            RunningScript.validate_partial_script(self.COLLECT_PY, partial, "collect.py", 3, 3)

    def test_validate_partial_script_allows_complete_code(self):
        partial = "print('done')\n"
        RunningScript.validate_partial_script(self.COLLECT_PY, partial, "collect.py", 7, None)

    def test_validate_partial_script_leaves_broken_file_to_normal_error(self):
        broken = self.COLLECT_PY + "    else:\n"
        RunningScript.validate_partial_script(broken, "    else:\n", "collect.py", 8, None)

    def test_invalid_goto_target_stays_paused(self):
        self.running_script.script_status.state = "paused"
        self.running_script.pause = False
        self.running_script.scriptrunner_puts = MagicMock()
        self.running_script.execute_while_paused("collect.py", 5)
        self.mock_start.side_effect = RunningScript.InvalidStartLineError("Cannot start at line 5")

        self.running_script.check_execute_while_paused()
        self.running_script.scriptrunner_puts.assert_called_with("Cannot start at line 5", "RED")
        # The pause set for the goto must not leak into the next line
        self.assertFalse(self.running_script.pause)
        self.assertIsNone(self.running_script.execute_while_paused_info)

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


class TestScriptrunnerPuts(unittest.TestCase):
    def setUp(self):
        # Skip __init__ since it redirects stdout/stderr and talks to Redis
        self.running_script = RunningScript.__new__(RunningScript)
        self.running_script.script_status = MagicMock(id=1)
        self.running_script.output_io = StringIO("")
        self.console = StringIO("")
        self.message_log = MagicMock()
        for patcher in (
            patch.object(running_script, "running_script_anycable_publish"),
            patch.object(running_script.Stdout, "STDOUT", self.console),
            patch.object(RunningScript, "message_log", return_value=self.message_log),
        ):
            mock = patcher.start()
            self.addCleanup(patcher.stop)
            if patcher.attribute == "running_script_anycable_publish":
                self.mock_publish = mock

    def test_publishes_and_logs_once_while_capturing_stdout(self):
        # Like run_thread_body: sys.stdout feeds output_io for handle_output_io
        capture = IoMultiplexer()
        capture.add_stream(self.running_script.output_io)
        self.running_script.capturing_output = True
        with patch.object(sys, "stdout", capture):
            self.running_script.scriptrunner_puts("Cannot start at line 4", "RED")

        self.mock_publish.assert_called_once()
        self.assertIn("(SCRIPTRUNNER): Cannot start at line 4", self.mock_publish.call_args[0][1]["line"])
        self.assertIn("(SCRIPTRUNNER): Cannot start at line 4", self.console.getvalue())
        self.message_log.write.assert_called_once()
        self.assertTrue(self.message_log.write.call_args[0][0].endswith("Cannot start at line 4\n"))
        # Nothing left for handle_output_io to publish again
        self.assertEqual(self.running_script.output_io.getvalue(), "")

    def test_does_not_write_message_log_when_not_capturing(self):
        self.running_script.capturing_output = False
        self.running_script.scriptrunner_puts("Cannot execute selection")
        self.mock_publish.assert_called_once()
        self.message_log.write.assert_not_called()


if __name__ == "__main__":
    unittest.main()
