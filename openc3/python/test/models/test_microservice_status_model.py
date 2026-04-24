# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
import unittest
from unittest.mock import *

from openc3.microservices.microservice import Microservice
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.microservice_status_model import MicroserviceStatusModel
from test.test_helper import *


class TestMicroserviceStatusModel(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)
        MicroserviceStatusModel._db_shard_cache = {}

    def test_stores_microservice_status(self):
        microservice1 = Microservice("DEFAULT__TYPE__TEST")
        MicroserviceStatusModel.set(microservice1.as_json(), scope="DEFAULT")
        microservice2 = Microservice("DEFAULT__TYPE__TEST2")
        MicroserviceStatusModel.set(microservice2.as_json(), scope="DEFAULT")
        self.assertListEqual(
            ["DEFAULT__TYPE__TEST", "DEFAULT__TYPE__TEST2"],
            MicroserviceStatusModel.names(scope="DEFAULT"),
        )
        micro = MicroserviceStatusModel.get("DEFAULT__TYPE__TEST", scope="DEFAULT")
        self.assertEqual(micro["name"], "DEFAULT__TYPE__TEST")
        self.assertEqual(micro["state"], "INITIALIZED")
        self.assertEqual(micro["count"], 0)
        self.assertEqual(micro["plugin"], None)
        microservice1.shutdown()
        microservice2.shutdown()
        time.sleep(0.1)

    def test_get_from_correct_db_shard(self):
        MicroserviceModel("DEFAULT__TYPE__TEST", scope="DEFAULT", db_shard=0).create()
        MicroserviceStatusModel.set({"name": "DEFAULT__TYPE__TEST", "state": "RUNNING"}, scope="DEFAULT")
        result = MicroserviceStatusModel.get("DEFAULT__TYPE__TEST", scope="DEFAULT")
        self.assertEqual(result["name"], "DEFAULT__TYPE__TEST")
        self.assertEqual(result["state"], "RUNNING")

    def test_get_with_nonzero_db_shard(self):
        MicroserviceModel("DEFAULT__TYPE__DB_SHARD", scope="DEFAULT", db_shard=1).create()
        MicroserviceStatusModel.set({"name": "DEFAULT__TYPE__DB_SHARD", "state": "RUNNING"}, scope="DEFAULT")
        result = MicroserviceStatusModel.get("DEFAULT__TYPE__DB_SHARD", scope="DEFAULT")
        self.assertEqual(result["name"], "DEFAULT__TYPE__DB_SHARD")
        self.assertEqual(result["state"], "RUNNING")

    def test_names_across_db_shards(self):
        MicroserviceModel("DEFAULT__TYPE__MS1", scope="DEFAULT", db_shard=0).create()
        MicroserviceModel("DEFAULT__TYPE__MS2", scope="DEFAULT", db_shard=1).create()
        MicroserviceStatusModel.set({"name": "DEFAULT__TYPE__MS1", "state": "RUNNING"}, scope="DEFAULT")
        MicroserviceStatusModel.set({"name": "DEFAULT__TYPE__MS2", "state": "RUNNING"}, scope="DEFAULT")
        names = MicroserviceStatusModel.names(scope="DEFAULT")
        self.assertIn("DEFAULT__TYPE__MS1", names)
        self.assertIn("DEFAULT__TYPE__MS2", names)

    def test_all_across_db_shards(self):
        MicroserviceModel("DEFAULT__TYPE__MS1", scope="DEFAULT", db_shard=0).create()
        MicroserviceModel("DEFAULT__TYPE__MS2", scope="DEFAULT", db_shard=1).create()
        MicroserviceStatusModel.set({"name": "DEFAULT__TYPE__MS1", "state": "RUNNING"}, scope="DEFAULT")
        MicroserviceStatusModel.set({"name": "DEFAULT__TYPE__MS2", "state": "STOPPED"}, scope="DEFAULT")
        all_statuses = MicroserviceStatusModel.all(scope="DEFAULT")
        self.assertIn("DEFAULT__TYPE__MS1", all_statuses)
        self.assertIn("DEFAULT__TYPE__MS2", all_statuses)
        self.assertEqual(all_statuses["DEFAULT__TYPE__MS1"]["state"], "RUNNING")
        self.assertEqual(all_statuses["DEFAULT__TYPE__MS2"]["state"], "STOPPED")

    def test_create_and_destroy(self):
        MicroserviceModel("DEFAULT__TYPE__TEST", scope="DEFAULT", db_shard=1).create()
        model = MicroserviceStatusModel(name="DEFAULT__TYPE__TEST", state="RUNNING", scope="DEFAULT")
        model.create(force=True)
        result = MicroserviceStatusModel.get("DEFAULT__TYPE__TEST", scope="DEFAULT")
        self.assertEqual(result["state"], "RUNNING")
        model.destroy()
        result = MicroserviceStatusModel.get("DEFAULT__TYPE__TEST", scope="DEFAULT")
        self.assertIsNone(result)

    def test_db_shard_for_name_returns_0_when_missing(self):
        db_shard = MicroserviceStatusModel._db_shard_for_name("DEFAULT__TYPE__NONE", "DEFAULT")
        self.assertEqual(db_shard, 0)

    def test_db_shard_for_name_returns_db_shard(self):
        MicroserviceModel("DEFAULT__TYPE__TEST", scope="DEFAULT", db_shard=2).create()
        db_shard = MicroserviceStatusModel._db_shard_for_name("DEFAULT__TYPE__TEST", "DEFAULT")
        self.assertEqual(db_shard, 2)

    def test_active_db_shards_always_includes_zero(self):
        db_shards = MicroserviceStatusModel._active_db_shards("DEFAULT")
        self.assertIn(0, db_shards)

    def test_active_db_shards_includes_unique_db_shards(self):
        MicroserviceModel("DEFAULT__TYPE__MS1", scope="DEFAULT", db_shard=0).create()
        MicroserviceModel("DEFAULT__TYPE__MS2", scope="DEFAULT", db_shard=2).create()
        MicroserviceModel("DEFAULT__TYPE__MS3", scope="DEFAULT", db_shard=2).create()
        db_shards = MicroserviceStatusModel._active_db_shards("DEFAULT")
        self.assertEqual(db_shards, {0, 2})

    def test_active_db_shards_scoped(self):
        MicroserviceModel("DEFAULT__TYPE__MS1", scope="DEFAULT", db_shard=1).create()
        MicroserviceModel("OTHER__TYPE__MS2", scope="OTHER", db_shard=3).create()
        db_shards = MicroserviceStatusModel._active_db_shards("DEFAULT")
        self.assertEqual(db_shards, {0, 1})
