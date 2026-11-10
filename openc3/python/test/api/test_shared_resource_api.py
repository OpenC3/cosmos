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
from unittest.mock import call, patch

from openc3.api.cmd_api import cmd, send_raw
from openc3.api.interface_api import connect_interface, interface_cmd, interface_details, interface_protocol_cmd
from openc3.api.router_api import connect_router, router_cmd, router_details, router_protocol_cmd
from openc3.api.shared_resource_api import (
    get_shared_resource,
    get_shared_resources,
    release_shared_resource,
    switch_shared_resource,
)
from openc3.models.shared_resource_model import SharedResourceModel
from test.test_helper import mock_redis


class TestSharedResourceApi(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        SharedResourceModel.clear_cache()
        for scope in ["DEFAULT", "OTHER"]:
            SharedResourceModel.add_member(
                "CHAMBER", scope=scope, type="INTERFACE", member_name=f"{scope}__INTERFACE__INT"
            )
            SharedResourceModel.add_member("CHAMBER", scope=scope, type="ROUTER", member_name=f"{scope}__ROUTER__ROUTE")
            SharedResourceModel.add_member("CHAMBER", scope=scope, type="TARGET", member_name="INST")
        SharedResourceModel.add_member("LAB", scope="THIRD", type="TARGET", member_name="INST")

    def test_get_shared_resources(self):
        resources = get_shared_resources(scope="DEFAULT")
        self.assertEqual([r["name"] for r in resources], ["CHAMBER"])
        self.assertEqual(resources[0]["owner"], "DEFAULT")
        self.assertEqual([r["name"] for r in get_shared_resources(scope="THIRD")], ["LAB"])
        self.assertEqual(get_shared_resources(scope="NONE"), [])

    def test_get_shared_resource(self):
        self.assertEqual(list(get_shared_resource("chamber")["members"].keys()), ["DEFAULT", "OTHER"])
        self.assertIsNone(get_shared_resource("NOPE"))

    def test_switch_defaults_to_current_scope(self):
        record = switch_shared_resource("CHAMBER", scope="OTHER")
        self.assertEqual(record["state"], "RELEASING")
        self.assertEqual(record["to"], "OTHER")

    @patch("openc3.api.shared_resource_api.authorize")
    def test_switch_requires_admin_in_both_scopes(self, authorize):
        switch_shared_resource("CHAMBER", "OTHER", scope="DEFAULT")
        self.assertEqual(
            authorize.call_args_list,
            [
                call(permission="admin", scope="OTHER", manual=False),
                call(permission="admin", scope="DEFAULT", manual=False),
            ],
        )

    def test_switch_force_and_errors(self):
        record = switch_shared_resource("CHAMBER", "OTHER", force=True)
        self.assertEqual(record["owner"], "OTHER")
        with self.assertRaisesRegex(RuntimeError, "Shared resource 'NOPE' does not exist"):
            switch_shared_resource("NOPE", "OTHER")
        with self.assertRaisesRegex(RuntimeError, "no members in scope 'THIRD'"):
            switch_shared_resource("CHAMBER", "THIRD")

    @patch("openc3.api.shared_resource_api.authorize")
    def test_release_requires_admin_in_owner_scope(self, authorize):
        record = release_shared_resource("CHAMBER", force=True, scope="OTHER")
        self.assertIsNone(record["owner"])
        self.assertEqual(
            authorize.call_args_list,
            [
                call(permission="admin", scope="OTHER", manual=False),
                call(permission="admin", scope="DEFAULT", manual=False),
            ],
        )
        with self.assertRaisesRegex(RuntimeError, "Shared resource 'NOPE' does not exist"):
            release_shared_resource("NOPE")

    @patch("openc3.api.cmd_api.TargetModel.packet")
    def test_rejects_commands_in_inactive_scope(self, packet):
        with self.assertRaisesRegex(
            RuntimeError, "Target INST is part of shared resource CHAMBER which is active in scope DEFAULT"
        ):
            cmd("INST", "ABORT", {}, scope="OTHER")
        packet.assert_not_called()

    @patch("openc3.api.cmd_api.TargetModel.packet", side_effect=RuntimeError("reached packet"))
    def test_allows_commands_in_active_scope(self, _packet):
        with self.assertRaisesRegex(RuntimeError, "reached packet"):
            cmd("INST", "ABORT", {}, scope="DEFAULT")

    @patch("openc3.api.interface_api.InterfaceTopic")
    def test_rejects_interface_commands_in_inactive_scope(self, topic):
        for func, args in [
            (connect_interface, ["INT"]),
            (interface_cmd, ["INT", "CMD"]),
            (interface_protocol_cmd, ["INT", "CMD"]),
            (interface_details, ["INT"]),
        ]:
            with self.assertRaisesRegex(RuntimeError, "Interface INT is part of shared resource CHAMBER"):
                func(*args, scope="OTHER")
        self.assertEqual(topic.mock_calls, [])
        connect_interface("INT", scope="DEFAULT")
        topic.connect_interface.assert_called_once()

    @patch("openc3.api.cmd_api.get_interface")
    @patch("openc3.api.cmd_api.InterfaceTopic")
    def test_rejects_send_raw_in_inactive_scope(self, topic, _get_interface):
        with self.assertRaisesRegex(RuntimeError, "Interface INT is part of shared resource CHAMBER"):
            send_raw("INT", b"\x00", scope="OTHER")
        topic.write_raw.assert_not_called()

    @patch("openc3.api.router_api.RouterTopic")
    def test_rejects_router_commands_in_inactive_scope(self, topic):
        for func, args in [
            (connect_router, ["ROUTE"]),
            (router_cmd, ["ROUTE", "CMD"]),
            (router_protocol_cmd, ["ROUTE", "CMD"]),
            (router_details, ["ROUTE"]),
        ]:
            with self.assertRaisesRegex(RuntimeError, "Router ROUTE is part of shared resource CHAMBER"):
                func(*args, scope="OTHER")
        self.assertEqual(topic.mock_calls, [])
        connect_router("ROUTE", scope="DEFAULT")
        topic.connect_router.assert_called_once()
