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

import json
import unittest
from unittest.mock import Mock

import openc3.script
from openc3.script.plugins import plugin_list


PLUGINS = [
    "openc3-cosmos-tool-admin-1.0.0.gem__20260101000000",
    "my-plugin-1.0.0.gem__20260101000000",
]


class TestPluginList(unittest.TestCase):
    def setUp(self):
        original_api_server = openc3.script.API_SERVER
        self.addCleanup(setattr, openc3.script, "API_SERVER", original_api_server)
        self.api_server_mock = Mock()
        openc3.script.API_SERVER = self.api_server_mock

    def _respond(self, status_code=200):
        response = Mock()
        response.status_code = status_code
        response.text = json.dumps(PLUGINS)
        self.api_server_mock.request.return_value = response

    def test_returns_all_plugins_when_default(self):
        self._respond()
        self.assertEqual(plugin_list(default=True, scope="OTHER"), PLUGINS)
        self.api_server_mock.request.assert_called_once_with("get", "/openc3-api/plugins?scope=OTHER", scope="OTHER")

    def test_excludes_default_plugins_by_default(self):
        self._respond()
        self.assertEqual(plugin_list(scope="OTHER"), PLUGINS)
        self.api_server_mock.request.assert_called_once_with(
            "get", "/openc3-api/plugins?scope=OTHER&exclude_default=true", scope="OTHER"
        )

    def test_raises_on_non_200(self):
        self._respond(status_code=500)
        with self.assertRaisesRegex(RuntimeError, "plugin_list failed"):
            plugin_list()

    def test_raises_on_no_response(self):
        self.api_server_mock.request.return_value = None
        with self.assertRaisesRegex(RuntimeError, "plugin_list failed"):
            plugin_list()

    def test_raises_on_invalid_json(self):
        response = Mock()
        response.status_code = 200
        response.text = "not json"
        self.api_server_mock.request.return_value = response
        with self.assertRaisesRegex(RuntimeError, "plugin_list failed"):
            plugin_list()
