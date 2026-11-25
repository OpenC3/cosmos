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
from unittest.mock import patch

from openc3.models.interface_model import InterfaceModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.shared_resource_model import SharedResourceModel
from openc3.models.target_model import TargetModel
from openc3.utilities.store import Store
from test.test_helper import mock_redis


def add_interface(scope, name="INT", shard=0):
    return SharedResourceModel.add_member(
        "CHAMBER", scope=scope, type="INTERFACE", member_name=f"{scope}__INTERFACE__{name}", shard=shard
    )


class TestSharedResourceModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        SharedResourceModel.clear_cache()

    def test_validate_name(self):
        self.assertEqual(SharedResourceModel.validate_name("chamber_1"), "CHAMBER_1")
        for bad in ["BAD NAME", "BAD__NAME", ""]:
            with self.assertRaisesRegex(RuntimeError, "Invalid shared resource name"):
                SharedResourceModel.validate_name(bad)

    def test_stores_the_global_record_on_db_shard_0(self):
        with patch.object(Store, "instance", wraps=Store.instance) as instance:
            add_interface("DEFAULT", shard=1)
            for call in instance.call_args_list:
                self.assertEqual(call.kwargs.get("db_shard"), 0)
        self.assertIsNotNone(Store.instance(db_shard=0).hget("openc3_shared_resources", "CHAMBER"))

    def test_first_scope_owns(self):
        add_interface("DEFAULT")
        add_interface("OTHER")
        record = SharedResourceModel.get("CHAMBER")
        self.assertEqual(record["owner"], "DEFAULT")
        self.assertEqual(record["state"], "ACTIVE")
        self.assertEqual(list(record["members"].keys()), ["DEFAULT", "OTHER"])
        self.assertEqual(
            record["members"]["OTHER"], [{"type": "INTERFACE", "name": "OTHER__INTERFACE__INT", "shard": 0}]
        )
        self.assertEqual(SharedResourceModel.names(), ["CHAMBER"])
        self.assertEqual(list(SharedResourceModel.all().keys()), ["CHAMBER"])

    def test_add_member_is_idempotent(self):
        add_interface("DEFAULT")
        add_interface("DEFAULT", shard=2)
        members = SharedResourceModel.get("CHAMBER")["members"]["DEFAULT"]
        self.assertEqual(members, [{"type": "INTERFACE", "name": "DEFAULT__INTERFACE__INT", "shard": 2}])

    def test_rejects_unknown_member_types(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid shared resource member type"):
            SharedResourceModel.add_member("CHAMBER", scope="DEFAULT", type="TOOL", member_name="X")

    def test_is_member(self):
        name = "DEFAULT__INTERFACE__INT"
        self.assertFalse(SharedResourceModel.is_member("CHAMBER", scope="DEFAULT", type="INTERFACE", member_name=name))
        add_interface("DEFAULT")
        self.assertTrue(SharedResourceModel.is_member("chamber", scope="DEFAULT", type="interface", member_name=name))
        self.assertFalse(SharedResourceModel.is_member("CHAMBER", scope="OTHER", type="INTERFACE", member_name=name))
        self.assertFalse(SharedResourceModel.is_member("CHAMBER", scope="DEFAULT", type="ROUTER", member_name=name))

    def test_remove_member_keeps_ownership(self):
        add_interface("DEFAULT")
        add_interface("OTHER")
        SharedResourceModel.remove_member(
            "CHAMBER", scope="DEFAULT", type="INTERFACE", member_name="DEFAULT__INTERFACE__INT"
        )
        record = SharedResourceModel.get("CHAMBER")
        self.assertEqual(record["owner"], "DEFAULT")
        self.assertEqual(list(record["members"].keys()), ["OTHER"])
        self.assertIsNone(
            SharedResourceModel.remove_member(
                "CHAMBER", scope="OTHER", type="INTERFACE", member_name="OTHER__INTERFACE__INT"
            )
        )
        self.assertIsNone(SharedResourceModel.get("CHAMBER"))

    def test_switch_errors(self):
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            SharedResourceModel.switch("NOPE", to_scope="DEFAULT")
        add_interface("DEFAULT")
        with self.assertRaisesRegex(RuntimeError, "no members in scope 'OTHER'"):
            SharedResourceModel.switch("CHAMBER", to_scope="OTHER")

    def test_switch_immediately_without_process_members(self):
        SharedResourceModel.add_member("CHAMBER", scope="DEFAULT", type="TARGET", member_name="INST")
        SharedResourceModel.add_member("CHAMBER", scope="OTHER", type="TARGET", member_name="INST")
        record = SharedResourceModel.switch("CHAMBER", to_scope="OTHER")
        self.assertEqual(record["owner"], "OTHER")
        self.assertEqual(record["state"], "ACTIVE")

    def test_hands_off_once_every_member_is_acknowledged(self):
        add_interface("DEFAULT")
        SharedResourceModel.add_member(
            "CHAMBER", scope="DEFAULT", type="MICROSERVICE", member_name="DEFAULT__USER__CTRL", shard=1
        )
        SharedResourceModel.add_member("CHAMBER", scope="DEFAULT", type="TARGET", member_name="INST")
        add_interface("OTHER")

        record = SharedResourceModel.switch("CHAMBER", to_scope="OTHER")
        self.assertEqual(record["state"], "RELEASING")
        self.assertEqual(record["to"], "OTHER")
        self.assertEqual(
            record["waiting"],
            [{"name": "DEFAULT__INTERFACE__INT", "shard": 0}, {"name": "DEFAULT__USER__CTRL", "shard": 1}],
        )
        self.assertFalse(SharedResourceModel.is_active(record, "DEFAULT"))
        self.assertFalse(SharedResourceModel.is_active(record, "OTHER"))

        record = SharedResourceModel.acknowledge("CHAMBER", ["DEFAULT__INTERFACE__INT"])
        self.assertEqual(record["state"], "RELEASING")
        record = SharedResourceModel.acknowledge("CHAMBER", ["DEFAULT__USER__CTRL"])
        self.assertEqual(record["state"], "ACTIVE")
        self.assertEqual(record["owner"], "OTHER")
        self.assertTrue(SharedResourceModel.is_active(record, "OTHER"))

    def test_changes_destination_while_releasing_and_force(self):
        add_interface("DEFAULT")
        add_interface("OTHER")
        add_interface("THIRD")
        SharedResourceModel.switch("CHAMBER", to_scope="OTHER")
        record = SharedResourceModel.switch("CHAMBER", to_scope="THIRD")
        self.assertEqual(record["to"], "THIRD")
        record = SharedResourceModel.switch("CHAMBER", to_scope="OTHER", force=True)
        self.assertEqual(record["owner"], "OTHER")
        self.assertEqual(record["state"], "ACTIVE")

    def test_waits_for_member_removed_during_handoff(self):
        add_interface("DEFAULT")
        add_interface("OTHER")
        SharedResourceModel.switch("CHAMBER", to_scope="OTHER")
        SharedResourceModel.remove_member(
            "CHAMBER", scope="OTHER", type="INTERFACE", member_name="OTHER__INTERFACE__INT"
        )
        record = SharedResourceModel.remove_member(
            "CHAMBER", scope="DEFAULT", type="INTERFACE", member_name="DEFAULT__INTERFACE__INT"
        )
        self.assertEqual(len(record["waiting"]), 1)
        self.assertIsNone(SharedResourceModel.acknowledge("CHAMBER", ["DEFAULT__INTERFACE__INT"]))
        self.assertIsNone(SharedResourceModel.get("CHAMBER"))

    def test_release(self):
        add_interface("DEFAULT")
        record = SharedResourceModel.release("CHAMBER")
        self.assertEqual(record["state"], "RELEASING")
        record = SharedResourceModel.acknowledge("CHAMBER", ["DEFAULT__INTERFACE__INT"])
        self.assertIsNone(record["owner"])
        add_interface("DEFAULT")
        self.assertIsNone(SharedResourceModel.get("CHAMBER")["owner"])
        with self.assertRaisesRegex(RuntimeError, "does not exist"):
            SharedResourceModel.release("NOPE")

    def test_checks(self):
        add_interface("DEFAULT")
        add_interface("OTHER")
        SharedResourceModel.add_member("CHAMBER", scope="DEFAULT", type="TARGET", member_name="INST")
        SharedResourceModel.add_member("CHAMBER", scope="OTHER", type="TARGET", member_name="INST")
        SharedResourceModel.check_target_active("inst", scope="DEFAULT")
        SharedResourceModel.check_target_active("INST2", scope="OTHER")
        SharedResourceModel.check_interface_active("INTERFACE", "int", scope="DEFAULT")
        with self.assertRaisesRegex(
            RuntimeError, "Target INST is part of shared resource CHAMBER which is active in scope DEFAULT"
        ):
            SharedResourceModel.check_target_active("INST", scope="OTHER")
        with self.assertRaisesRegex(RuntimeError, "Interface INT is part of shared resource CHAMBER"):
            SharedResourceModel.check_interface_active("INTERFACE", "INT", scope="OTHER")
        SharedResourceModel.switch("CHAMBER", to_scope="OTHER")
        with self.assertRaisesRegex(RuntimeError, "switching from scope DEFAULT to scope OTHER"):
            SharedResourceModel.check_target_active("INST", scope="OTHER")
        SharedResourceModel.release("CHAMBER")
        with self.assertRaisesRegex(RuntimeError, "being released from scope DEFAULT"):
            SharedResourceModel.check_target_active("INST", scope="DEFAULT")
        SharedResourceModel.acknowledge("CHAMBER", ["DEFAULT__INTERFACE__INT"])
        with self.assertRaisesRegex(RuntimeError, "not active in any scope"):
            SharedResourceModel.check_target_active("INST", scope="DEFAULT")

    def test_lock_times_out(self):
        Store.instance(db_shard=0).set("openc3_shared_resources__lock", "someone-else")
        with (
            patch.object(SharedResourceModel, "LOCK_WAIT_SECONDS", 0.1),
            self.assertRaisesRegex(RuntimeError, "Timeout waiting for shared resource lock"),
        ):
            add_interface("DEFAULT")
        self.assertEqual(Store.instance(db_shard=0).get("openc3_shared_resources__lock"), b"someone-else")


class TestSharedResourceModelFields(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_models_accept_shared_resource(self):
        # Ruby writes shared_resource into the model json so from_json must accept it
        micro = MicroserviceModel.from_json(
            {"name": "DEFAULT__USER__CTRL", "shared_resource": "CHAMBER"}, scope="DEFAULT"
        )
        self.assertEqual(micro.shared_resource, "CHAMBER")
        self.assertEqual(micro.as_json()["shared_resource"], "CHAMBER")
        interface = InterfaceModel.from_json({"name": "INT", "shared_resource": "CHAMBER"}, scope="DEFAULT")
        self.assertEqual(interface.shared_resource, "CHAMBER")
        self.assertEqual(interface.as_json()["shared_resource"], "CHAMBER")
        target = TargetModel(name="INST", shared_resource="CHAMBER", scope="DEFAULT")
        self.assertEqual(target.shared_resource, "CHAMBER")
