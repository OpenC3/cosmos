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

import io
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from openc3.script import open_bucket_dialog, open_file_dialog, open_files_dialog, prompt_for_critical_cmd


class TestOpenBucketDialog(unittest.TestCase):
    def test_returns_user_input(self):
        with patch("builtins.input", return_value="config/foo.txt"), redirect_stdout(io.StringIO()):
            self.assertEqual(open_bucket_dialog("Title"), "config/foo.txt")

    def test_accepts_default_path_and_filter_kwargs(self):
        buf = io.StringIO()
        with patch("builtins.input", return_value="config/foo.txt"), redirect_stdout(buf):
            result = open_bucket_dialog(
                "Title",
                "Msg",
                default_path="config/DEFAULT/targets/INST2/procedures/",
                filter=".py",
            )
        self.assertEqual(result, "config/foo.txt")
        output = buf.getvalue()
        # Hint text should mention both kwargs to the user.
        self.assertIn("config/DEFAULT/targets/INST2/procedures/", output)
        self.assertIn(".py", output)


class TestOpenFileDialogs(unittest.TestCase):
    def test_open_file_dialog_returns_user_input(self):
        with patch("builtins.input", return_value="foo.txt"), redirect_stdout(io.StringIO()):
            self.assertEqual(open_file_dialog("Title"), "foo.txt")

    def test_open_files_dialog_returns_user_input(self):
        with patch("builtins.input", return_value="foo.txt"), redirect_stdout(io.StringIO()):
            self.assertEqual(open_files_dialog("Title"), "foo.txt")


class TestPromptForCriticalCmd(unittest.TestCase):
    def test_waits_until_approved(self):
        statuses = iter(["WAITING", "WAITING", "APPROVED"])
        with (
            patch("openc3.script.critical_cmd_status", side_effect=lambda uuid, scope: next(statuses)) as status,
            patch("openc3.script.time.sleep") as sleep,
            redirect_stdout(io.StringIO()),
        ):
            prompt_for_critical_cmd("uuid", "user", "INST", "CLEAR", {}, 'cmd("INST CLEAR")', scope="OTHER")
        self.assertEqual(sleep.call_count, 2)
        status.assert_called_with("uuid", scope="OTHER")

    def test_raises_when_rejected(self):
        statuses = iter(["WAITING", "REJECTED"])
        with (
            patch("openc3.script.critical_cmd_status", side_effect=lambda uuid, scope: next(statuses)),
            patch("openc3.script.time.sleep"),
            redirect_stdout(io.StringIO()),
            self.assertRaisesRegex(RuntimeError, "Critical command rejected"),
        ):
            prompt_for_critical_cmd("uuid", "user", "INST", "CLEAR", {}, 'cmd("INST CLEAR")')


if __name__ == "__main__":
    unittest.main()
