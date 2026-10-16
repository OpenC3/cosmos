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
    "openc3-cosmos-tool-admin-1.0.0.gem",
    "openc3-tool-base-1.0.0.gem",
    "openc3-cosmos-enterprise-tool-admin-1.0.0.gem",
    "openc3-enterprise-tool-base-1.0.0.gem",
    "openc3-cosmos-demo-1.0.0.gem",
    "my-openc3-cosmos-tool-custom-1.0.0.gem",
]


class TestPluginList(unittest.TestCase):
    def setUp(self):
        original_api_server = openc3.script.API_SERVER
        self.addCleanup(setattr, openc3.script, "API_SERVER", original_api_server)
        self.api_server_mock = Mock()
        openc3.script.API_SERVER = self.api_server_mock

    def _respond(self, status_code=200, body=None):
        response = Mock()
        response.status_code = status_code
        response.text = json.dumps(PLUGINS if body is None else body)
        self.api_server_mock.request.return_value = response

    def test_requests_plugins_endpoint_with_scope(self):
        self._respond()
        plugin_list(scope="OTHER")
        self.api_server_mock.request.assert_called_once_with("get", "/openc3-api/plugins?scope=OTHER", scope="OTHER")

    def test_returns_all_plugins_when_default(self):
        self._respond()
        self.assertEqual(plugin_list(default=True), PLUGINS)

    def test_filters_core_tool_plugins_by_prefix(self):
        self._respond()
        self.assertEqual(
            plugin_list(),
            ["openc3-cosmos-demo-1.0.0.gem", "my-openc3-cosmos-tool-custom-1.0.0.gem"],
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
