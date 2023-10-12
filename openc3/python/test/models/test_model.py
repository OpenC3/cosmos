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

import time
import json
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.models.model import Model


class MyModel(Model):
    def __init__(self, name, scope, plugin=None, updated_at=None):
        super().__init__(
            f"{scope}__TEST",
            name=name,
            scope=scope,
            plugin=plugin,
            updated_at=updated_at,
        )

    @classmethod
    def get(cls, name, scope=None):
        return super().get(f"{scope}__TEST", name=name)

    @classmethod
    def names(cls, scope=None):
        return super().names(f"{scope}__TEST")

    @classmethod
    def all(cls, scope=None):
        return super().all(f"{scope}__TEST")


class TestModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_stores_model_based_on_primary_key_and_name(self):
        # start_time = Time.now.to_nsec_from_epoch
        model = Model(
            "primary_key",
            name="model",
            scope="DEFAULT",
            plugin="PLUGIN",
            updated_at="blah",
            other=True,
        )
        model.create()  # This overwrites updated_at
        vals = Model.get("primary_key", name="model")
        self.assertEqual(vals["name"], "model")
        self.assertEqual(vals["scope"], "DEFAULT")
        self.assertEqual(vals["plugin"], "PLUGIN")
        # self.assertEqual(vals["updated_at"]).to be_within(100_000_000).of(start_time)
        self.assertEqual(
            vals.get("other"), None
        )  # No other keyword arguments are stored by the constructor

    def test_complains_if_it_already_exists(self):
        model = Model("primary_key", name="model")
        model.create()
        with self.assertRaisesRegex(RuntimeError, "model already exists"):
            model.create()

    def test_complains_if_updating_non_existant(self):
        model = Model("primary_key", name="model")
        with self.assertRaisesRegex(RuntimeError, "model doesn't exist"):
            model.create(update=True)

    def test_create_updates_existing(self):
        model = Model("primary_key", name="model", plugin="plug-it")
        model.create()
        saved = Model.get("primary_key", name="model")
        self.assertEqual(saved["plugin"], "plug-it")

        model.plugin = True
        model.create(update=True)
        saved = Model.get("primary_key", name="model")
        self.assertTrue(saved["plugin"])

    def test_update_updates_existing(self):
        model = Model("primary_key", name="model", plugin=False)
        model.create()
        saved = Model.get("primary_key", name="model")
        self.assertFalse(saved["plugin"])

        model.plugin = True
        model.update()
        saved = Model.get("primary_key", name="model")
        self.assertTrue(saved["plugin"])

    def test_deploy_must_be_implemented_by_subclass(self):
        model = Model("primary_key", name="model")
        with self.assertRaisesRegex(RuntimeError, "must be implemented by subclass"):
            model.deploy(None, None)

    def test_removes_the_model(self):
        model = Model("primary_key", name="model")
        model.destroy()
        saved = Model.get("primary_key", name="model")
        self.assertIsNone(saved)

    # def test_handle_config_must_be_implemented_by_subclass(self):
    #     with self.assertRaisesRegex(RuntimeError, "must be implemented by subclass"):
    #         Model.handle_config("parser", "keyword", "parameters")

    def test_updates_the_model_configuration(self):
        model = MyModel(name="TEST1", scope="DEFAULT", plugin="ONE")
        model.create()
        model.plugin = "TWO"
        MyModel.set(model.as_json(), scope="DEFAULT")
        saved = MyModel.get(name="TEST1", scope="DEFAULT")
        self.assertEqual(saved["name"], "TEST1")
        self.assertEqual(saved["plugin"], "TWO")

    def test_round_trips_the_model_with_json(self):
        now = time.time()
        model = MyModel(name="TEST1", scope="DEFAULT", plugin="ONE", updated_at=now)
        model.create()
        hash = model.as_json()
        json_data = json.dumps(hash)
        model2 = MyModel.from_json(json_data, scope="DEFAULT")
        self.assertEqual(hash, (model2.as_json()))

    def test_returns_none_if_the_name_cant_be_found(self):
        self.assertIsNone(MyModel.get(name="BLAH", scope="DEFAULT"))

    def test_returns_the_model_object(self):
        model = MyModel(name="TEST1", scope="DEFAULT")
        model.create()
        model = MyModel.get_model(name="TEST1", scope="DEFAULT")
        self.assertEqual(model.name, "TEST1")
