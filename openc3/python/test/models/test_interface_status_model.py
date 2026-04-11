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

from openc3.interfaces.interface import Interface
from openc3.models.interface_model import InterfaceModel
from openc3.models.interface_status_model import InterfaceStatusModel
from test.test_helper import *


class MyInterface(Interface):
    pass


class OtherInterface(Interface):
    pass


class TestInterfaceStatusModel(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)
        InterfaceStatusModel._shard_cache = {}

    def test_set_and_get(self):
        my = MyInterface()
        InterfaceStatusModel.set(my.as_json(), "DEFAULT")
        status = InterfaceStatusModel.get("MyInterface", "DEFAULT")
        self.assertEqual(my.name, status["name"])

    def test_names_and_all(self):
        my = MyInterface()
        InterfaceStatusModel.set(my.as_json(), "DEFAULT")
        other = OtherInterface()
        InterfaceStatusModel.set(other.as_json(), "DEFAULT")

        names = InterfaceStatusModel.names("DEFAULT")
        self.assertEqual(names, ["MyInterface", "OtherInterface"])
        all = InterfaceStatusModel.all("DEFAULT")
        self.assertEqual(list(all.keys()), ["MyInterface", "OtherInterface"])
        self.assertEqual(all["OtherInterface"]["name"], "OtherInterface")

        all = InterfaceStatusModel.names("OTHER")
        self.assertEqual(all, [])  # Nothing in 'OTHER' scope
        all = InterfaceStatusModel.all("OTHER")
        self.assertEqual(all, {})  # Nothing in 'OTHER' scope

    def test_get_from_correct_shard(self):
        InterfaceModel(name="TEST_INT", scope="DEFAULT", db_shard=0).create()
        InterfaceStatusModel.set({"name": "TEST_INT", "state": "CONNECTED"}, "DEFAULT")
        result = InterfaceStatusModel.get("TEST_INT", "DEFAULT")
        self.assertEqual(result["name"], "TEST_INT")
        self.assertEqual(result["state"], "CONNECTED")

    def test_get_with_nonzero_db_shard(self):
        InterfaceModel(name="SHARD_INT", scope="DEFAULT", db_shard=1).create()
        InterfaceStatusModel.set({"name": "SHARD_INT", "state": "ATTEMPTING"}, "DEFAULT")
        result = InterfaceStatusModel.get("SHARD_INT", "DEFAULT")
        self.assertEqual(result["name"], "SHARD_INT")
        self.assertEqual(result["state"], "ATTEMPTING")

    def test_names_across_shards(self):
        InterfaceModel(name="INT1", scope="DEFAULT", db_shard=0).create()
        InterfaceModel(name="INT2", scope="DEFAULT", db_shard=1).create()
        InterfaceStatusModel.set({"name": "INT1", "state": "CONNECTED"}, "DEFAULT")
        InterfaceStatusModel.set({"name": "INT2", "state": "DISCONNECTED"}, "DEFAULT")
        names = InterfaceStatusModel.names("DEFAULT")
        self.assertIn("INT1", names)
        self.assertIn("INT2", names)

    def test_all_across_shards(self):
        InterfaceModel(name="INT1", scope="DEFAULT", db_shard=0).create()
        InterfaceModel(name="INT2", scope="DEFAULT", db_shard=1).create()
        InterfaceStatusModel.set({"name": "INT1", "state": "CONNECTED"}, "DEFAULT")
        InterfaceStatusModel.set({"name": "INT2", "state": "DISCONNECTED"}, "DEFAULT")
        all_statuses = InterfaceStatusModel.all("DEFAULT")
        self.assertIn("INT1", all_statuses)
        self.assertIn("INT2", all_statuses)
        self.assertEqual(all_statuses["INT1"]["state"], "CONNECTED")
        self.assertEqual(all_statuses["INT2"]["state"], "DISCONNECTED")

    def test_create_and_destroy(self):
        InterfaceModel(name="TEST_INT", scope="DEFAULT", db_shard=1).create()
        model = InterfaceStatusModel(name="TEST_INT", state="CONNECTED", scope="DEFAULT")
        model.create(force=True)
        result = InterfaceStatusModel.get("TEST_INT", "DEFAULT")
        self.assertEqual(result["state"], "CONNECTED")
        model.destroy()
        result = InterfaceStatusModel.get("TEST_INT", "DEFAULT")
        self.assertIsNone(result)

    def test_shard_for_name_returns_0_when_missing(self):
        shard = InterfaceStatusModel._shard_for_name("NONEXISTENT", "DEFAULT")
        self.assertEqual(shard, 0)

    def test_shard_for_name_returns_db_shard(self):
        InterfaceModel(name="MY_INT", scope="DEFAULT", db_shard=2).create()
        shard = InterfaceStatusModel._shard_for_name("MY_INT", "DEFAULT")
        self.assertEqual(shard, 2)

    def test_active_shards_always_includes_zero(self):
        shards = InterfaceStatusModel._active_shards("DEFAULT")
        self.assertIn(0, shards)

    def test_active_shards_includes_unique_db_shards(self):
        InterfaceModel(name="INT1", scope="DEFAULT", db_shard=0).create()
        InterfaceModel(name="INT2", scope="DEFAULT", db_shard=2).create()
        InterfaceModel(name="INT3", scope="DEFAULT", db_shard=2).create()
        shards = InterfaceStatusModel._active_shards("DEFAULT")
        self.assertEqual(shards, {0, 2})
