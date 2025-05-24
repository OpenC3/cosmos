# encoding: utf-8

# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import patch, Mock
from openc3.script.autonomic import (
    autonomic_group_list,
    autonomic_group_create,
    autonomic_group_show,
    autonomic_group_destroy,
    autonomic_trigger_list,
    autonomic_trigger_create,
    autonomic_trigger_show,
    autonomic_trigger_enable,
    autonomic_trigger_disable,
    autonomic_trigger_update,
    autonomic_trigger_destroy,
    autonomic_reaction_list,
    autonomic_reaction_create,
    autonomic_reaction_show,
    autonomic_reaction_enable,
    autonomic_reaction_disable,
    autonomic_reaction_execute,
    autonomic_reaction_update,
    autonomic_reaction_destroy,
)


class TestAutonomic(unittest.TestCase):
    def setUp(self):
        self.mock_response = Mock()
        self.mock_response.status_code = 200
        self.mock_response.text = "{}"

    # Group Tests
    @patch("openc3.script.API_SERVER")
    def test_autonomic_group_list(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.text = '["group1", "group2"]'
        result = autonomic_group_list()
        mock_api_server.request.assert_called_with("get", "/openc3-api/autonomic/group", scope="DEFAULT")
        self.assertEqual(result, ["group1", "group2"])

    @patch("openc3.script.API_SERVER")
    def test_autonomic_group_create(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.status_code = 201
        self.mock_response.text = '{"name": "test_group"}'
        result = autonomic_group_create("test_group")
        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/group", data={"name": "test_group"}, json=True, scope="DEFAULT"
        )
        self.assertEqual(result, {"name": "test_group"})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_group_show(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.text = '{"name": "test_group", "triggers": []}'
        result = autonomic_group_show("test_group")
        mock_api_server.request.assert_called_with("get", "/openc3-api/autonomic/group/test_group", scope="DEFAULT")
        self.assertEqual(result, {"name": "test_group", "triggers": []})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_group_destroy(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_group_destroy("test_group")
        mock_api_server.request.assert_called_with("delete", "/openc3-api/autonomic/group/test_group", scope="DEFAULT")

    # Trigger Tests
    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_list(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.text = '["trigger1", "trigger2"]'
        result = autonomic_trigger_list(group="test_group")
        mock_api_server.request.assert_called_with("get", "/openc3-api/autonomic/test_group/trigger", scope="DEFAULT")
        self.assertEqual(result, ["trigger1", "trigger2"])

    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_create(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.status_code = 201
        self.mock_response.text = '{"name": "test_trigger", "enabled": "true"}'

        left = {
            "type": "item",
            "target": "INST",
            "packet": "HEALTH_STATUS",
            "item": "TEMP1",
            "valueType": "CONVERTED",
        }
        operator = ">"
        right = {
            "type": "float",
            "float": 0,
        }

        result = autonomic_trigger_create(left=left, operator=operator, right=right, group="test_group")

        expected_config = {"group": "test_group", "left": left, "operator": operator, "right": right}

        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/test_group/trigger", data=expected_config, json=True, scope="DEFAULT"
        )

        self.assertEqual(result, {"name": "test_trigger", "enabled": "true"})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_show(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.text = '{"name": "test_trigger", "enabled": "true"}'
        result = autonomic_trigger_show("test_trigger", group="test_group")
        mock_api_server.request.assert_called_with(
            "get", "/openc3-api/autonomic/test_group/trigger/test_trigger", scope="DEFAULT"
        )
        self.assertEqual(result, {"name": "test_trigger", "enabled": "true"})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_enable(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_trigger_enable("test_trigger", group="test_group")
        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/test_group/trigger/test_trigger/enable", json=True, scope="DEFAULT"
        )

    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_disable(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_trigger_disable("test_trigger", group="test_group")
        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/test_group/trigger/test_trigger/disable", json=True, scope="DEFAULT"
        )

    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_update(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response

        operator = "<="
        right = {
            "type": "float",
            "float": 100,
        }

        result = autonomic_trigger_update("test_trigger", operator=operator, right=right, group="test_group")

        expected_config = {"operator": operator, "right": right}

        mock_api_server.request.assert_called_with(
            "put",
            "/openc3-api/autonomic/test_group/trigger/test_trigger",
            data=expected_config,
            json=True,
            scope="DEFAULT",
        )

        self.assertEqual(result, {})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_destroy(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_trigger_destroy("test_trigger", group="test_group")
        mock_api_server.request.assert_called_with(
            "delete", "/openc3-api/autonomic/test_group/trigger/test_trigger", scope="DEFAULT"
        )

    # Reaction Tests
    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_list(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.text = '["reaction1", "reaction2"]'
        result = autonomic_reaction_list()
        mock_api_server.request.assert_called_with("get", "/openc3-api/autonomic/reaction", scope="DEFAULT")
        self.assertEqual(result, ["reaction1", "reaction2"])

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_create(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.status_code = 201
        self.mock_response.text = '{"name": "test_reaction", "enabled": "true"}'

        triggers = [
            {
                "name": "test_trigger",
                "group": "test_group",
            }
        ]
        actions = [{"type": "command", "value": "INST ABORT"}]

        result = autonomic_reaction_create(triggers=triggers, actions=actions, trigger_level="EDGE", snooze=0)

        expected_config = {
            "triggers": triggers,
            "actions": actions,
            "trigger_level": "EDGE",
            "snooze": 0,
        }

        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/reaction", data=expected_config, json=True, scope="DEFAULT"
        )

        self.assertEqual(result, {"name": "test_reaction", "enabled": "true"})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_show(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        self.mock_response.text = '{"name": "test_reaction", "enabled": "true"}'
        result = autonomic_reaction_show("test_reaction")
        mock_api_server.request.assert_called_with(
            "get", "/openc3-api/autonomic/reaction/test_reaction", scope="DEFAULT"
        )
        self.assertEqual(result, {"name": "test_reaction", "enabled": "true"})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_enable(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_reaction_enable("test_reaction")
        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/reaction/test_reaction/enable", json=True, scope="DEFAULT"
        )

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_disable(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_reaction_disable("test_reaction")
        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/reaction/test_reaction/disable", json=True, scope="DEFAULT"
        )

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_execute(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_reaction_execute("test_reaction")
        mock_api_server.request.assert_called_with(
            "post", "/openc3-api/autonomic/reaction/test_reaction/execute", json=True, scope="DEFAULT"
        )

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_update(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response

        result = autonomic_reaction_update("test_reaction", trigger_level="LEVEL", snooze=300)

        expected_config = {"trigger_level": "LEVEL", "snooze": 300}

        mock_api_server.request.assert_called_with(
            "put", "/openc3-api/autonomic/reaction/test_reaction", data=expected_config, json=True, scope="DEFAULT"
        )

        self.assertEqual(result, {})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_destroy(self, mock_api_server):
        mock_api_server.request.return_value = self.mock_response
        autonomic_reaction_destroy("test_reaction")
        mock_api_server.request.assert_called_with(
            "delete", "/openc3-api/autonomic/reaction/test_reaction", scope="DEFAULT"
        )

    # Error Tests
    @patch("openc3.script.API_SERVER")
    def test_autonomic_group_list_error(self, mock_api_server):
        mock_api_server.request.return_value = None
        with self.assertRaises(RuntimeError):
            autonomic_group_list()

    @patch("openc3.script.API_SERVER")
    def test_autonomic_group_create_error(self, mock_api_server):
        self.mock_response.status_code = 400
        self.mock_response.text = '{"message": "Group already exists"}'
        mock_api_server.request.return_value = self.mock_response
        with self.assertRaises(RuntimeError):
            autonomic_group_create("test_group")

    @patch("openc3.script.API_SERVER")
    def test_autonomic_trigger_create_error(self, mock_api_server):
        self.mock_response.status_code = 400
        self.mock_response.text = '{"error": "Invalid trigger configuration"}'
        mock_api_server.request.return_value = self.mock_response

        left = {"type": "item", "target": "INST", "packet": "HEALTH_STATUS", "item": "TEMP1"}
        with self.assertRaises(RuntimeError):
            autonomic_trigger_create(left=left, operator=">", right={"type": "float", "float": 0})

    @patch("openc3.script.API_SERVER")
    def test_autonomic_reaction_create_error(self, mock_api_server):
        self.mock_response.status_code = 400
        self.mock_response.text = '{"error": "Invalid reaction configuration"}'
        mock_api_server.request.return_value = self.mock_response

        with self.assertRaises(RuntimeError):
            autonomic_reaction_create(
                triggers=[{"name": "invalid", "group": "DEFAULT"}], actions=[{"type": "command", "value": "INST ABORT"}]
            )


if __name__ == "__main__":
    unittest.main()
