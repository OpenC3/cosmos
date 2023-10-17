# Copyright 2023 OpenC3, Inc.
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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.api.config_api import *


class TestConfigApi(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_save_load_list_delete(self):
        data = {"key": "value", "longer key": "more data"}
        save_config("TestConfigApiTool", "config", json.dumps(data), local_mode=False)
        configs = list_configs("TestConfigApiTool")
        self.assertEqual(configs, ["config"])
        config = load_config("TestConfigApiTool", "config")
        self.assertEqual(data, config)
        delete_config("TestConfigApiTool", "config", local_mode=False)
        configs = list_configs("TestConfigApiTool")
        self.assertEqual(configs, [])
