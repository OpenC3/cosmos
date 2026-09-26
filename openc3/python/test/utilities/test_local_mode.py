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
import shutil
import tempfile
import unittest
from unittest.mock import patch

from openc3.utilities.local_mode import LocalMode


class TestLocalMode(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.mkdtemp()
        patcher = patch.object(LocalMode, "LOCAL_MODE_PATH", self.tmp_dir)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(shutil.rmtree, self.tmp_dir, ignore_errors=True)
        # The traversal only resolves on disk if the caller's own directory exists, as it does in a real install
        os.makedirs(f"{self.tmp_dir}/DEFAULT/targets_modified")

    def test_safe_key(self):
        self.assertTrue(LocalMode.safe_key("DEFAULT/targets_modified/INST/procedures/a.rb"))
        for key in ["../OTHER", "DEFAULT/../OTHER", "DEFAULT/./x", "/etc/passwd", "DEFAULT//x", "DEFAULT\\x", "", None]:
            self.assertFalse(LocalMode.safe_key(key), key)

    def test_path_within(self):
        self.assertTrue(LocalMode.path_within("/plugins/DEFAULT/x", "/plugins"))
        self.assertFalse(LocalMode.path_within("/plugins_old/DEFAULT/x", "/plugins"))
        self.assertFalse(LocalMode.path_within("/plugins/DEFAULT/../OTHER/x", "/plugins/DEFAULT"))

    def test_put_target_file_stays_in_scope(self):
        LocalMode.put_target_file("DEFAULT/targets_modified/INST/a.rb", "data", scope="DEFAULT")
        self.assertTrue(os.path.exists(f"{self.tmp_dir}/DEFAULT/targets_modified/INST/a.rb"))
        LocalMode.put_target_file("DEFAULT/targets_modified/../../OTHER/x.rb", "data", scope="DEFAULT")
        LocalMode.put_target_file("OTHER/targets_modified/INST/x.rb", "data", scope="DEFAULT")
        self.assertFalse(os.path.exists(f"{self.tmp_dir}/OTHER"))

    def test_open_local_file_stays_in_scope(self):
        victim = f"{self.tmp_dir}/OTHER/targets_modified/INST/secret.txt"
        os.makedirs(os.path.dirname(victim))
        with open(victim, "w") as file:
            file.write("secret")
        self.assertIsNone(LocalMode.open_local_file("../../OTHER/targets_modified/INST/secret.txt", scope="DEFAULT"))

    def test_tool_config_stays_in_scope(self):
        LocalMode.save_tool_config("DEFAULT", "tlm-viewer", "../../../OTHER/temps", "{}")
        LocalMode.save_tool_config("../OTHER", "tlm-viewer", "temps", "{}")
        self.assertFalse(os.path.exists(f"{self.tmp_dir}/OTHER"))
        LocalMode.save_tool_config("DEFAULT", "tlm-viewer", "temps", "{}")
        self.assertTrue(os.path.exists(f"{self.tmp_dir}/DEFAULT/tool_config/tlm-viewer/temps.json"))
        LocalMode.delete_tool_config("DEFAULT", "tlm-viewer", "temps")
        self.assertFalse(os.path.exists(f"{self.tmp_dir}/DEFAULT/tool_config/tlm-viewer/temps.json"))

    def test_save_setting_stays_in_scope(self):
        LocalMode.save_setting("DEFAULT", "../../OTHER/settings/x", "data")
        self.assertFalse(os.path.exists(f"{self.tmp_dir}/OTHER"))
