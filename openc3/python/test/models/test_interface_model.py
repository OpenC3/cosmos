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

import unittest
from unittest.mock import patch, MagicMock
from test.test_helper import *
from openc3.models.interface_model import InterfaceModel
from openc3.models.router_model import RouterModel
from openc3.utilities.redis_secrets import RedisSecrets


class TestInterfaceModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_returns_the_specified_interface(self):
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            connect_on_startup=False,
            auto_reconnect=False,
        )  # Set a few things to check
        model.create()
        model = InterfaceModel(
            name="SPEC_INT",
            scope="DEFAULT",
            connect_on_startup=True,
            auto_reconnect=True,
        )  # Set to opposite of TEST_INT
        model.create()
        test = InterfaceModel.get(name="TEST_INT", scope="DEFAULT")
        self.assertEqual(test["name"], "TEST_INT")
        self.assertFalse(test["connect_on_startup"])
        self.assertFalse(test["auto_reconnect"])

    def test_works_with_same_named_routers(self):
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            connect_on_startup=False,
            auto_reconnect=False,
        )  # Set a few things to check
        model.create()
        model = RouterModel(
            name="TEST_INT",
            scope="DEFAULT",
            connect_on_startup=True,
            auto_reconnect=True,
        )  # Set to opposite
        model.create()
        test = InterfaceModel.get(name="TEST_INT", scope="DEFAULT")
        self.assertEqual(test["name"], "TEST_INT")
        self.assertFalse(test["connect_on_startup"])
        self.assertFalse(test["auto_reconnect"])
        test = RouterModel.get(name="TEST_INT", scope="DEFAULT")
        self.assertEqual(test["name"], "TEST_INT")
        self.assertTrue(test["connect_on_startup"])
        self.assertTrue(test["auto_reconnect"])

    def test_returns_all_interface_names(self):
        model = InterfaceModel(name="TEST_INT", scope="DEFAULT")
        model.create()
        model = InterfaceModel(name="SPEC_INT", scope="DEFAULT")
        model.create()
        model = InterfaceModel(name="OTHER_INT", scope="OTHER")
        model.create()
        names = InterfaceModel.names(scope="DEFAULT")
        self.assertListEqual(names, ["SPEC_INT", "TEST_INT"])
        names = InterfaceModel.names(scope="OTHER")
        self.assertListEqual(names, ["OTHER_INT"])

    def test_returns_all_the_parsed_interfaces(self):
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            connect_on_startup=False,
            auto_reconnect=False,
        )  # Set a few things to check
        model.create()
        model = InterfaceModel(
            name="SPEC_INT",
            scope="DEFAULT",
            connect_on_startup=True,
            auto_reconnect=True,
        )  # Set to opposite of TEST_INT
        model.create()
        all = InterfaceModel.all(scope="DEFAULT")
        keys = list(all.keys())
        keys.sort()
        self.assertListEqual(keys, ["SPEC_INT", "TEST_INT"])
        self.assertFalse(all["TEST_INT"]["connect_on_startup"])
        self.assertFalse(all["TEST_INT"]["auto_reconnect"])
        self.assertTrue(all["SPEC_INT"]["connect_on_startup"])
        self.assertTrue(all["SPEC_INT"]["auto_reconnect"])

    def test_requires_name_and_scope(self):
        model = InterfaceModel(name="TEST_INT", scope="DEFAULT")
        self.assertEqual(model.name, "TEST_INT")

    def test_only_handles_python(self):
        with self.assertRaisesRegex(RuntimeError, "Unknown file type interface.rb"):
            InterfaceModel(
                name="TEST_INT", scope="DEFAULT", config_params=["interface.rb"]
            )

    def test_stores_model_based_on_scope_and_class_name(self):
        model = InterfaceModel(name="TEST_INT", scope="DEFAULT")
        model.create()
        keys = Store.scan(0)
        # This is an implementation detail but Redis keys are pretty critical so test it
        self.assertIn("DEFAULT__openc3_interfaces", keys[1][0].decode())

    def test_instantiates_the_interface(self):
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            config_params=["openc3/interfaces/interface.py"],
        )
        interface = model.build()
        self.assertEqual(interface.__class__.__name__, "Interface")
        self.assertEqual(interface.stream_log_pair, None)
        # Now instantiate a more complex option
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            config_params=[
                "openc3/interfaces/tcpip_client_interface.py",
                "127.0.0.1",
                "8080",
                "8081",
                "10.0",
                "None",
                "BURST",
                "4",
                "0xDEADBEEF",
            ],
        )
        interface = model.build()
        self.assertEqual(interface.__class__.__name__, "TcpipClientInterface")

    def test_sets_options_on_the_interface(self):
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            config_params=[
                "openc3/interfaces/interface.py",
            ],
            options=[["option1", "with", 10, "options"], ["Option2", 100]],
        )
        interface = model.build()
        self.assertEqual(interface.options["OPTION1"], ["with", 10, "options"])
        self.assertEqual(interface.options["OPTION2"], [100])

    def test_sets_secret_options_on_the_interface(self):
        secrets = RedisSecrets()
        secrets.set("password", "abc123", scope="DEFAULT")
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            config_params=[
                "openc3/interfaces/interface.py",
            ],
            # TODO: How does secrets work?
            # secrets=["redis", "password", "abc123", RedisSecrets],
            secret_options=[["password", "password"]],
        )
        interface = model.build()
        self.assertEqual(interface.options["PASSWORD"], ["abc123"])
        json = model.as_json()
        self.assertEqual(json["secret_options"], [["password", "password"]])

    def test_encodes_all_the_input_parameters(self):
        model = InterfaceModel(name="TEST_INT", scope="DEFAULT")
        json = model.as_json()
        # Check the defaults
        self.assertEqual(json["name"], "TEST_INT")
        self.assertEqual(json["config_params"], [])
        self.assertEqual(json["target_names"], [])
        self.assertEqual(json["cmd_target_names"], [])
        self.assertEqual(json["tlm_target_names"], [])
        self.assertEqual(json["connect_on_startup"], True)
        self.assertEqual(json["auto_reconnect"], True)
        self.assertEqual(json["reconnect_delay"], 5.0)
        self.assertEqual(json["disable_disconnect"], False)
        self.assertEqual(json["options"], [])
        self.assertEqual(json["secret_options"], [])
        self.assertEqual(json["protocols"], [])
        self.assertEqual(json["log_stream"], None)
        self.assertEqual(json["plugin"], None)
        self.assertEqual(json["needs_dependencies"], False)
        self.assertEqual(json["secrets"], [])
        self.assertEqual(
            json["cmd"],
            ["python", "interface_microservice.py", "DEFAULT__INTERFACE__TEST_INT"],
        )
        self.assertEqual(json["env"], ({}))
        self.assertEqual(json["work_dir"], "/openc3/python/openc3/microservices")
        self.assertEqual(json["ports"], [])
        self.assertEqual(json["container"], None)
        self.assertEqual(json["prefix"], None)

        # params = model.method(:initialize).parameters
        # for type, name in params:
        #   # Scope isn't included in as_json as it is part of the key used to get the model
        #   if name == :scope:
        #       next

        #   self.assertTrue(json.key?( str(name)))
