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

from openc3.script import open_bucket_dialog


class TestOpenBucketDialog(unittest.TestCase):
    def test_returns_user_input(self):
        with patch("builtins.input", return_value="config/foo.txt"), redirect_stdout(io.StringIO()):
            self.assertEqual(
                open_bucket_dialog("Title"), "config/foo.txt"
            )

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


if __name__ == "__main__":
    unittest.main()
