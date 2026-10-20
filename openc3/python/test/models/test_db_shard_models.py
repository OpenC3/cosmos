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

# Verifies models write to and read from the correct db_shard. Each db_shard has
# its own FakeValkey (mock_redis_db_shards) so data on the wrong db_shard is missed.

import json
import unittest

from openc3.models.cvt_model import CvtModel
from openc3.models.interface_model import InterfaceModel
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.models.metric_model import MetricModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.microservice_status_model import MicroserviceStatusModel
from openc3.models.router_model import RouterModel
from openc3.models.router_status_model import RouterStatusModel
from openc3.models.target_model import TargetModel
from openc3.system.system import System
from openc3.utilities.store import EphemeralStore, Store
from test.test_helper import mock_redis_db_shards, set_target_db_shard, setup_system


def store(db_shard):
    return Store.instance(db_shard=db_shard)


def ephemeral(db_shard):
    return EphemeralStore.instance(db_shard=db_shard)


class DbShardModelTestCase(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)
        for model in (InterfaceStatusModel, MicroserviceStatusModel, MetricModel):
            model._db_shard_cache = {}
        # Remove any cache RouterStatusModel has of its own so it starts like a new process
        if "_db_shard_cache" in vars(RouterStatusModel):
            del RouterStatusModel._db_shard_cache


class TestInterfaceStatusModelDbShard(DbShardModelTestCase):
    def setUp(self):
        super().setUp()
        InterfaceModel(name="INT0", scope="DEFAULT").create()
        InterfaceModel(name="INT1", scope="DEFAULT", db_shard=1).create()

    def status(self, name, state="CONNECTED"):
        return InterfaceStatusModel(name=name, state=state, scope="DEFAULT")

    def test_creates_gets_and_destroys_a_status_on_the_db_shard_of_its_interface(self):
        self.status("INT1").create()
        self.assertIsNotNone(store(1).hget("DEFAULT__openc3_interface_status", "INT1"))
        self.assertIsNone(store(0).hget("DEFAULT__openc3_interface_status", "INT1"))
        self.assertEqual(InterfaceStatusModel.get("INT1", "DEFAULT")["state"], "CONNECTED")

        self.status("INT1").destroy()
        self.assertIsNone(store(1).hget("DEFAULT__openc3_interface_status", "INT1"))
        self.assertIsNone(InterfaceStatusModel.get("INT1", "DEFAULT"))

    def test_checks_for_an_existing_status_on_the_db_shard_of_its_interface(self):
        # A status on another db_shard doesn't count
        store(0).hset("DEFAULT__openc3_interface_status", "INT1", json.dumps({"state": "OLD"}))
        with self.assertRaisesRegex(RuntimeError, "doesn't exist at update"):
            self.status("INT1").create(update=True)
        self.status("INT1").create()
        with self.assertRaisesRegex(RuntimeError, "already exists at create"):
            self.status("INT1").create()
        self.status("INT1", "DISCONNECTED").create(update=True)
        self.assertEqual(InterfaceStatusModel.get("INT1", "DEFAULT")["state"], "DISCONNECTED")
        self.status("INT1", "ATTEMPTING").create(force=True)
        self.assertEqual(InterfaceStatusModel.get("INT1", "DEFAULT")["state"], "ATTEMPTING")

    def test_writes_a_queued_status_to_the_db_shard_of_its_interface(self):
        self.status("INT1").create(queued=True)
        self.assertIsNotNone(store(1).hget("DEFAULT__openc3_interface_status", "INT1"))
        self.assertIsNone(store(0).hget("DEFAULT__openc3_interface_status", "INT1"))

    def test_returns_names_and_all_from_every_db_shard(self):
        InterfaceModel(name="INT2", scope="DEFAULT", db_shard=2).create()
        for name in ("INT0", "INT1", "INT2"):
            self.status(name).create()
        self.assertEqual(store(2).hkeys("DEFAULT__openc3_interface_status"), [b"INT2"])
        self.assertEqual(InterfaceStatusModel.names("DEFAULT"), ["INT0", "INT1", "INT2"])
        self.assertEqual(sorted(InterfaceStatusModel.all("DEFAULT").keys()), ["INT0", "INT1", "INT2"])
        self.assertEqual(InterfaceStatusModel._active_db_shards("DEFAULT"), {0, 1, 2})

    def test_caches_the_db_shard_for_create_but_not_for_get(self):
        self.status("INT1").create()
        InterfaceModel(name="INT1", scope="DEFAULT", db_shard=2).create(update=True)
        # create keeps using the cached db_shard 1
        self.status("INT1", "DISCONNECTED").create(update=True)
        self.assertEqual(json.loads(store(1).hget("DEFAULT__openc3_interface_status", "INT1"))["state"], "DISCONNECTED")
        # get looks up the db_shard every time
        self.assertIsNone(InterfaceStatusModel.get("INT1", "DEFAULT"))


class TestRouterStatusModelDbShard(DbShardModelTestCase):
    def test_uses_the_db_shard_of_its_router_not_an_interface_of_the_same_name(self):
        InterfaceModel(name="SAME", scope="DEFAULT", db_shard=1).create()
        RouterModel(name="SAME", scope="DEFAULT", db_shard=2).create()
        InterfaceStatusModel(name="SAME", state="CONNECTED", scope="DEFAULT").create()
        RouterStatusModel(name="SAME", state="DISCONNECTED", scope="DEFAULT").create()
        self.assertIsNotNone(store(1).hget("DEFAULT__openc3_interface_status", "SAME"))
        self.assertIsNotNone(store(2).hget("DEFAULT__openc3_router_status", "SAME"))
        self.assertIsNone(store(1).hget("DEFAULT__openc3_router_status", "SAME"))
        self.assertEqual(RouterStatusModel.get("SAME", "DEFAULT")["state"], "DISCONNECTED")
        self.assertEqual(RouterStatusModel.names("DEFAULT"), ["SAME"])


class TestMicroserviceStatusModelDbShard(DbShardModelTestCase):
    def test_uses_the_db_shard_of_its_microservice_and_only_that_scopes_db_shards(self):
        MicroserviceModel("DEFAULT__TYPE__MS1", scope="DEFAULT", db_shard=1).create()
        MicroserviceModel("OTHER__TYPE__MS3", scope="OTHER", db_shard=3).create()
        MicroserviceStatusModel(name="DEFAULT__TYPE__MS1", state="RUNNING", scope="DEFAULT").create()
        self.assertIsNotNone(store(1).hget("DEFAULT__openc3_microservice_status", "DEFAULT__TYPE__MS1"))
        self.assertIsNone(store(0).hget("DEFAULT__openc3_microservice_status", "DEFAULT__TYPE__MS1"))
        self.assertEqual(MicroserviceStatusModel.get("DEFAULT__TYPE__MS1", "DEFAULT")["state"], "RUNNING")
        self.assertEqual(MicroserviceStatusModel.names("DEFAULT"), ["DEFAULT__TYPE__MS1"])
        self.assertEqual(MicroserviceStatusModel._active_db_shards("DEFAULT"), {0, 1})

        MicroserviceStatusModel(name="DEFAULT__TYPE__MS1", scope="DEFAULT").destroy()
        self.assertIsNone(store(1).hget("DEFAULT__openc3_microservice_status", "DEFAULT__TYPE__MS1"))


class TestMetricModelDbShard(DbShardModelTestCase):
    def setUp(self):
        super().setUp()
        MicroserviceModel("DEFAULT__TYPE__MS1", scope="DEFAULT", db_shard=1).create()

    def test_sets_gets_and_destroys_metrics_on_the_db_shard_of_the_microservice(self):
        MetricModel.set({"name": "DEFAULT__TYPE__MS1", "values": {"a": {"value": 1}}, "db_shard": 1}, scope="DEFAULT")
        MetricModel.set_process(
            {"name": "DEFAULT__TYPE__MS1", "values": {"b": {"value": 2}}, "db_shard": 1}, scope="DEFAULT"
        )
        self.assertIsNotNone(ephemeral(1).hget("DEFAULT__openc3__metric", "DEFAULT__TYPE__MS1"))
        self.assertIsNotNone(ephemeral(1).hget("DEFAULT__openc3__process_metric", "DEFAULT__TYPE__MS1"))
        self.assertEqual(ephemeral(0).hkeys("DEFAULT__openc3__metric"), [])
        # Metrics are ephemeral so nothing goes to the persistent store
        self.assertEqual(store(1).hkeys("DEFAULT__openc3__metric"), [])

        self.assertEqual(sorted(MetricModel.get("DEFAULT__TYPE__MS1", "DEFAULT")["values"].keys()), ["a", "b"])
        self.assertEqual(MetricModel.names("DEFAULT"), ["DEFAULT__TYPE__MS1"])
        self.assertEqual(list(MetricModel.all("DEFAULT").keys()), ["DEFAULT__TYPE__MS1"])

        MetricModel.destroy(scope="DEFAULT", name="DEFAULT__TYPE__MS1")
        self.assertEqual(ephemeral(1).hkeys("DEFAULT__openc3__metric"), [])
        self.assertEqual(ephemeral(1).hkeys("DEFAULT__openc3__process_metric"), [])

    def test_creates_a_metric_with_an_expiry_on_its_own_db_shard(self):
        MetricModel(name="DEFAULT__TYPE__MS1", values={}, db_shard=1, scope="DEFAULT").create(expire_seconds=10)
        self.assertEqual(ephemeral(1).hkeys("DEFAULT__openc3__metric"), [b"DEFAULT__TYPE__MS1"])
        self.assertEqual(ephemeral(0).hkeys("DEFAULT__openc3__metric"), [])


class TestTargetDbShard(DbShardModelTestCase):
    def setUp(self):
        super().setUp()
        setup_system()
        TargetModel.clear_packet_cache()
        TargetModel.item_map_cache = {}
        CvtModel.packet_cache = {}
        CvtModel.override_cache = {}
        # setup_system stores every target on db_shard 0 so remove INST from there
        for key in ("DEFAULT__openc3tlm__INST", "DEFAULT__openc3cmd__INST", "DEFAULT__tlm__INST"):
            store(0).delete(key)
        self.model = TargetModel(name="INST", folder_name="INST", scope="DEFAULT", db_shard=1)
        self.model.create()
        TargetModel(name="SYSTEM", folder_name="SYSTEM", scope="DEFAULT").create()
        # Python TargetModel doesn't store db_shard (the Ruby plugin install does)
        set_target_db_shard("INST", 1)
        self.model.update_store_telemetry({"INST": System.telemetry.packets("INST")})
        self.model.update_store_commands({"INST": System.commands.packets("INST")})
        self.model.update_store_item_map()

    def test_stores_the_target_definition_on_db_shard_0_and_its_packets_on_its_db_shard(self):
        self.assertIsNotNone(store(0).hget("DEFAULT__openc3_targets", "INST"))
        self.assertIsNone(store(1).hget("DEFAULT__openc3_targets", "INST"))
        for key in (
            "DEFAULT__openc3tlm__INST",
            "DEFAULT__openc3cmd__INST",
            "DEFAULT__tlm__INST",
            "DEFAULT__openc3tlm__INST__allitems",
            "DEFAULT__INST__item_to_packet_map",
        ):
            self.assertEqual(store(1).exists(key), 1, f"{key} not on db_shard 1")
            self.assertEqual(store(0).exists(key), 0, f"{key} on db_shard 0")

    def test_reads_packets_items_and_the_item_map_from_the_targets_db_shard(self):
        self.assertEqual(TargetModel.packet("INST", "HEALTH_STATUS", scope="DEFAULT")["packet_name"], "HEALTH_STATUS")
        self.assertEqual(TargetModel.packet("INST", "ABORT", type="CMD", scope="DEFAULT")["packet_name"], "ABORT")
        packet_names = [packet["packet_name"] for packet in TargetModel.packets("INST", scope="DEFAULT")]
        self.assertIn("HEALTH_STATUS", packet_names)
        self.assertIn(b"TEMP1", TargetModel.all_item_names("INST", scope="DEFAULT"))
        TargetModel.item_map_cache = {}
        self.assertEqual(TargetModel.get_item_to_packet_map("INST", scope="DEFAULT")["TEMP1"], ["HEALTH_STATUS"])

        packet = TargetModel.packet("INST", "HEALTH_STATUS", scope="DEFAULT")
        packet["description"] = "Changed"
        TargetModel.set_packet("INST", "HEALTH_STATUS", packet, scope="DEFAULT")
        self.assertEqual(
            json.loads(store(1).hget("DEFAULT__openc3tlm__INST", "HEALTH_STATUS"))["description"], "Changed"
        )

    def test_counts_packets_on_each_targets_db_shard(self):
        TargetModel.increment_telemetry_count("INST", "HEALTH_STATUS", 2, scope="DEFAULT")
        TargetModel.increment_telemetry_count("SYSTEM", "META", 3, scope="DEFAULT")
        TargetModel.increment_command_count("INST", "ABORT", 4, scope="DEFAULT")
        self.assertEqual(store(1).hget("DEFAULT__TELEMETRYCNTS__{INST}", "HEALTH_STATUS"), b"2")
        self.assertEqual(store(0).hget("DEFAULT__TELEMETRYCNTS__{SYSTEM}", "META"), b"3")
        self.assertEqual(store(1).hget("DEFAULT__COMMANDCNTS__{INST}", "ABORT"), b"4")
        self.assertEqual(TargetModel.get_telemetry_count("INST", "HEALTH_STATUS", scope="DEFAULT"), 2)
        self.assertEqual(TargetModel.get_command_count("INST", "ABORT", scope="DEFAULT"), 4)
        # Batched lookups across db_shards keep the requested order
        counts = TargetModel.get_telemetry_counts(
            [["SYSTEM", "META"], ["INST", "HEALTH_STATUS"], ["INST", "ADCS"]], scope="DEFAULT"
        )
        self.assertEqual(counts, [3, 2, 0])
        self.assertEqual(
            TargetModel.get_command_counts([["INST", "ABORT"], ["SYSTEM", "STARTLOGGING"]], scope="DEFAULT"), [4, 0]
        )

    def test_sets_gets_and_overrides_the_cvt_on_the_targets_db_shard(self):
        CvtModel.set({"TEMP1": 1.5}, "INST", "HEALTH_STATUS", scope="DEFAULT")
        self.assertEqual(json.loads(store(1).hget("DEFAULT__tlm__INST", "HEALTH_STATUS")), {"TEMP1": 1.5})
        self.assertIsNone(store(0).hget("DEFAULT__tlm__INST", "HEALTH_STATUS"))
        CvtModel.packet_cache = {}
        self.assertEqual(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"), 1.5)

        CvtModel.set({"TEMP1": 2.5}, "INST", "HEALTH_STATUS", queued=True, scope="DEFAULT")
        self.assertEqual(json.loads(store(1).hget("DEFAULT__tlm__INST", "HEALTH_STATUS")), {"TEMP1": 2.5})

        CvtModel.override("INST", "HEALTH_STATUS", "TEMP1", 10, type="RAW", scope="DEFAULT")
        self.assertIsNotNone(store(1).hget("DEFAULT__override__INST", "HEALTH_STATUS"))
        self.assertIsNone(store(0).hget("DEFAULT__override__INST", "HEALTH_STATUS"))
        self.assertEqual([item["value"] for item in CvtModel.overrides(scope="DEFAULT")], [10])
        CvtModel.override_cache = {}
        self.assertEqual(CvtModel.get_item("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT"), 10)
        CvtModel.normalize("INST", "HEALTH_STATUS", "TEMP1", type="RAW", scope="DEFAULT")
        self.assertIsNone(store(1).hget("DEFAULT__override__INST", "HEALTH_STATUS"))

        CvtModel.delete("INST", "HEALTH_STATUS", scope="DEFAULT")
        self.assertIsNone(store(1).hget("DEFAULT__tlm__INST", "HEALTH_STATUS"))

    def test_clears_the_old_definition_from_the_targets_db_shard_on_update(self):
        TargetModel.increment_telemetry_count("INST", "HEALTH_STATUS", 2, scope="DEFAULT")
        TargetModel.increment_command_count("INST", "ABORT", 4, scope="DEFAULT")
        store(1).hset("DEFAULT__openc3tlm__INST", "OLD_PACKET", "{}")
        store(1).hset("DEFAULT__openc3cmd__INST", "OLD_PACKET", "{}")
        self.model.update_store_telemetry({"INST": System.telemetry.packets("INST")})
        self.model.update_store_commands({"INST": System.commands.packets("INST")})
        self.assertIsNone(store(1).hget("DEFAULT__openc3tlm__INST", "OLD_PACKET"))
        self.assertIsNone(store(1).hget("DEFAULT__openc3cmd__INST", "OLD_PACKET"))
        self.assertEqual(store(1).exists("DEFAULT__TELEMETRYCNTS__{INST}"), 0)
        self.assertEqual(store(1).exists("DEFAULT__COMMANDCNTS__{INST}"), 0)
        self.assertIsNotNone(store(1).hget("DEFAULT__openc3tlm__INST", "HEALTH_STATUS"))
