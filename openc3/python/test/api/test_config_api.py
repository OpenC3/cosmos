# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import *

from openc3.api.config_api import *
from test.test_helper import *


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
