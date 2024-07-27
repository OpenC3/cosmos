# Copyright 2023, 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.models.tool_config_model import ToolConfigModel

class TestToolConfigModel(unittest.TestCase):
    def setUp(self):
      mock_redis(self)
      setup_system()

    #def test_self_load_config(self):
        #config = ToolConfigModel.load_config('toolie', 'namely', scope= 'DEFAULT')
        #self.assertEqual(config, {})

    #def test_self_save_config(self):
        #self.assertRaises(ValueError,
        #  result = ToolConfigModel.save_config(
        #  'toolie',
        #  'namely',
        #  '{"data":"value", "other":42, "not":null}',
        #   local_mode= True,
        #   scope= 'DEFAULT')
        #) # message (/Read-only file system self. dir_s_mkdir - \/plugins/)

    def test_self_list_configs(self):
        all = ToolConfigModel.list_configs('toolie', scope= 'DEFAULT')
        self.assertEqual(all, []) # eq('ps')

    def test_self_config_tool_names(self):
        names = ToolConfigModel.config_tool_names(scope= 'DEFAULT')
        self.assertEqual(names, []) # eq('ps')

    #def test_deletes(self):
        #name = ToolConfigModel.delete_config('toolie', 'namely', local_mode= True, scope= 'DEFAULT')

    # some overlap

    def test_save_load_list_delete(self):
        data = {"key": "value", "longer key": "more data"}
        ToolConfigModel.save_config(
            "TestTool", "config", json.dumps(data), local_mode=False
        )
        # self.assertTrue(
        #     os.path.isfile(f"{TEST_DIR}/DEFAULT/tool_config/TestTool/config.json")
        # )
        configs = ToolConfigModel.list_configs("TestTool")
        self.assertEqual(configs, ["config"])
        config = ToolConfigModel.load_config("TestTool", "config")
        self.assertEqual(config, json.dumps(data))
        ToolConfigModel.delete_config("TestTool", "config", local_mode=False)
        # self.assertFalse(
        #     os.path.isfile(f"{TEST_DIR}/DEFAULT/tool_config/TestTool/config.json")
        # )
