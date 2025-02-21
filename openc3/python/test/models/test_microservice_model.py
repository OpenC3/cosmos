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

import inspect
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.models.microservice_model import MicroserviceModel


class TestMicroserviceModel(unittest.TestCase):
    def setUp(self):
        self.redis = mock_redis(self)

    def test_returns_the_specified_model_with_or_without_scope(self):
        model = MicroserviceModel(
            "DEFAULT__TYPE__TEST",
            folder_name="TEST",
            scope="DEFAULT",
        )
        model.create()
        model = MicroserviceModel("DEFAULT__TYPE__SPEC", folder_name="SPEC", scope="DEFAULT")
        model.create()
        target = MicroserviceModel.get("DEFAULT__TYPE__TEST", scope="DEFAULT")
        self.assertEqual(target["name"], "DEFAULT__TYPE__TEST")
        self.assertEqual(target["folder_name"], "TEST")
        target = MicroserviceModel.get("DEFAULT__TYPE__SPEC")  # No scope
        self.assertEqual(target["name"], "DEFAULT__TYPE__SPEC")
        self.assertEqual(target["folder_name"], "SPEC")

    def test_returns_all_model_names(self):
        model = MicroserviceModel(folder_name="TEST", name="DEFAULT__TYPE__TEST", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="SPEC", name="DEFAULT__TYPE__SPEC", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="OTHER", name="OTHER__TYPE__TEST", scope="OTHER")
        model.create()
        names = MicroserviceModel.names()
        self.assertEqual(
            names,
            ["DEFAULT__TYPE__SPEC", "DEFAULT__TYPE__TEST", "OTHER__TYPE__TEST"],
        )

    def test_returns_scoped_model_names(self):
        model = MicroserviceModel(folder_name="TEST", name="DEFAULT__TYPE__TEST", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="SPEC", name="DEFAULT__TYPE__SPEC", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="OTHER", name="OTHER__TYPE__TEST", scope="OTHER")
        model.create()
        names = MicroserviceModel.names(scope="DEFAULT")
        self.assertEqual(names, ["DEFAULT__TYPE__SPEC", "DEFAULT__TYPE__TEST"])
        names = MicroserviceModel.names(scope="OTHER")
        self.assertEqual(names, ["OTHER__TYPE__TEST"])

    def test_returns_all_the_parsed_models(self):
        model = MicroserviceModel(folder_name="TEST", name="DEFAULT__TYPE__TEST", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="SPEC", name="DEFAULT__TYPE__SPEC", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="OTHER", name="OTHER__TYPE__TEST", scope="OTHER")
        model.create()
        keys = list(MicroserviceModel.all().keys())
        keys.sort()
        self.assertListEqual(
            keys,
            ["DEFAULT__TYPE__SPEC", "DEFAULT__TYPE__TEST", "OTHER__TYPE__TEST"],
        )

    def test_returns_scoped_parsed_models(self):
        model = MicroserviceModel(folder_name="TEST", name="DEFAULT__TYPE__TEST", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="SPEC", name="DEFAULT__TYPE__SPEC", scope="DEFAULT")
        model.create()
        model = MicroserviceModel(folder_name="OTHER", name="OTHER__TYPE__TEST", scope="OTHER")
        model.create()
        keys = list(MicroserviceModel.all(scope="DEFAULT").keys())
        keys.sort()
        self.assertEqual(keys, ["DEFAULT__TYPE__SPEC", "DEFAULT__TYPE__TEST"])
        keys = list(MicroserviceModel.all(scope="OTHER").keys())
        MicroserviceModel.all(scope="OTHER")
        self.assertEqual(keys, ["OTHER__TYPE__TEST"])

    def test_requires_name_to_be_formatted_scope__type__name(self):
        with self.assertRaisesRegex(
            RuntimeError,
            "name 'SCOPE' must be formatted as SCOPE__TYPE__NAME",
        ):
            MicroserviceModel(name="SCOPE", folder_name="FOLDER", scope="DEFAULT")
        with self.assertRaisesRegex(
            RuntimeError,
            "name 'SCOPE__TYPE' must be formatted as SCOPE__TYPE__NAME",
        ):
            MicroserviceModel(name="SCOPE__TYPE", folder_name="FOLDER", scope="DEFAULT")
        with self.assertRaisesRegex(
            RuntimeError,
            "name 'SCOPE__TYPE__NAME' scope 'SCOPE' doesn't match scope parameter 'DEFAULT'",
        ):
            MicroserviceModel(name="SCOPE__TYPE__NAME", folder_name="FOLDER", scope="DEFAULT")
        model = MicroserviceModel(folder_name="TEST", name="DEFAULT__TYPE__NAME", scope="DEFAULT")
        self.assertEqual(model.name, "DEFAULT__TYPE__NAME")

    def test_encodes_all_the_input_parameters(self):
        model = MicroserviceModel(folder_name="TEST", name="DEFAULT__TYPE__NAME", scope="DEFAULT")
        json = model.as_json()
        self.assertEqual(json["name"], "DEFAULT__TYPE__NAME")
        for key in inspect.signature(model.__init__).parameters.keys():
            # Scope isn't included in as_json as it is part of the key used to get the model
            if key == "scope":
                continue
            self.assertIn(key, json.keys())
