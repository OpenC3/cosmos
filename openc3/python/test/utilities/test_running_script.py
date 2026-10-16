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
import types
import unittest
from unittest.mock import MagicMock, patch

import openc3.script
import openc3.script.api_shared


# Importing running_script monkeypatches openc3.script and api_shared at module
# level (RUNNING_SCRIPT, openc3_script_sleep, etc). Import it only while this
# module's tests run and restore the originals afterwards so other test files
# don't see a RunningScript with no instance.
_PATCHED_MODULES = (openc3.script, openc3.script.api_shared)
_saved_attrs = {}
running_script = None


def setUpModule():
    global running_script
    for module in _PATCHED_MODULES:
        _saved_attrs[module] = dict(vars(module))
    from openc3.utilities import running_script as rs

    running_script = rs


def tearDownModule():
    for module, saved in _saved_attrs.items():
        for name, value in list(vars(module).items()):
            if name not in saved and not isinstance(value, types.ModuleType):
                delattr(module, name)
        for name, value in saved.items():
            setattr(module, name, value)
    sys.modules.pop("openc3.utilities.running_script", None)


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


if __name__ == "__main__":
    unittest.main()
