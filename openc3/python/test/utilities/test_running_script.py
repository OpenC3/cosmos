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

import tempfile
import unittest
from unittest.mock import MagicMock, patch

from openc3.utilities import running_script
from openc3.utilities.running_script import RunningScript, running_script_method


class TestOpenBucketDialog(unittest.TestCase):
    def setUp(self):
        self.instance = MagicMock()
        self.instance.scope.return_value = "DEFAULT"
        self.instance.user_input = {
            "bucket": "OPENC3_CONFIG_BUCKET",
            "path": "DEFAULT/targets/INST/procedures/test.py",
            "filename": "test.py",
        }
        patcher = patch.object(RunningScript, "instance", self.instance)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_returns_file_with_bucket_info(self):
        file = tempfile.NamedTemporaryFile(mode="w+b")  # noqa: SIM115 - closed below
        self.addCleanup(file.close)
        with patch.object(running_script, "_get_storage_file", return_value=file) as get_file:
            result = running_script_method("open_bucket_dialog", "Title")
        get_file.assert_called_once_with(
            "targets/INST/procedures/test.py", bucket="OPENC3_CONFIG_BUCKET", scope="DEFAULT"
        )
        self.assertIs(result, file)
        self.assertEqual(result.filename(), "test.py")
        self.assertEqual(result.bucket(), "OPENC3_CONFIG_BUCKET")
        self.assertEqual(result.bucket_path(), "DEFAULT/targets/INST/procedures/test.py")


if __name__ == "__main__":
    unittest.main()
