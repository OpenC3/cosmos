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
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.api.router_api import *
from openc3.interfaces.interface import Interface
from openc3.models.router_model import RouterModel


class TestRouterApi(unittest.TestCase):
    router_cmd_data = {}
    protocol_cmd_data = {}

    @patch("openc3.models.router_model.RouterModel.get_model")
    @patch("openc3.microservices.interface_microservice.System")
    def setUp(self, mock_system, mock_get_model):
        mock_redis(self)
        setup_system()

        class MyInterface(Interface):
            def __init__(self):
                super().__init__()
                self.target_names = ["INST"]
                self.cmd_target_names = ["INST"]
                self.tlm_target_names = ["INST"]

            def connected(self):
                return True

            def disconnect(self):
                pass

            def read_interface(self):
                time.sleep(0.05)
                return b"\x01\x02\x03\x04", None

            def interface_cmd(self, cmd_name, *cmd_params):
                TestRouterApi.router_cmd_data[cmd_name] = cmd_params

            def protocol_cmd(
                self, cmd_name, *cmd_params, read_write="READ_WRITE", index=-1
            ):
                TestRouterApi.protocol_cmd_data[cmd_name] = cmd_params

            # Allow the stubbed RouterModel.get_model to call build()
            @staticmethod
            def build():
                return MyInterface()

        mock_get_model.return_value = MyInterface

        model = RouterModel(
            name="ROUTE_INT",
            scope="DEFAULT",
            target_names=["INST"],
            cmd_target_names=["INST"],
            tlm_target_names=["INST"],
            config_params=["openc3/interfaces/interface.py"],
        )
        model.create()
        # self.im = RouterMicroservice("DEFAULT__INTERFACE__ROUTE_INT")
        # self.im_thread = threading.Thread(target=self.im.run)
        # self.im_thread.start()
        # time.sleep(0.001)  # Allow the thread to run

    # def tearDown(self):
    #     self.im.shutdown()
    #     time.sleep(0.001)

    # def test_returns_router_hash(self):
    #     interface = get_router("ROUTE_INT")
    #     self.assertEqual(type(interface), dict)
    #     self.assertEqual(interface["name"], "ROUTE_INT")
    #     # Verify it also includes the status
    #     self.assertEqual(interface["state"], "CONNECTED")
    #     self.assertEqual(interface["clients"], 0)

    def test_returns_all_router_names(self):
        model = RouterModel(name="INT1", scope="DEFAULT")
        model.create()
        model = RouterModel(name="INT2", scope="DEFAULT")
        model.create()
        self.assertEqual(get_router_names(), ["INT1", "INT2", "ROUTE_INT"])

    # def test_connects_the_router(self):
    #     self.assertEqual(get_router("ROUTE_INT")["state"], "CONNECTED")
    #     disconnect_router("ROUTE_INT")
    #     time.sleep(0.1)
    #     self.assertEqual(get_router("ROUTE_INT")["state"], "DISCONNECTED")
    #     connect_router("ROUTE_INT")
    #     time.sleep(0.1)
    #     self.assertIn(get_router("ROUTE_INT")["state"], ["ATTEMPTING", "CONNECTED"])

    # def test_should_start_and_stop_raw_logging_on_the_router(self):
    #     self.assertIsNone(self.im.interface.stream_log_pair)
    #     start_raw_logging_router("ROUTE_INT")
    #     time.sleep(0.1)
    #     self.assertTrue(self.im.interface.stream_log_pair.read_log.logging_enabled)
    #     self.assertTrue(self.im.interface.stream_log_pair.write_log.logging_enabled)
    #     stop_raw_logging_router("ROUTE_INT")
    #     time.sleep(0.1)
    #     self.assertFalse(self.im.interface.stream_log_pair.read_log.logging_enabled)
    #     self.assertFalse(self.im.interface.stream_log_pair.write_log.logging_enabled)

    #     start_raw_logging_router("ALL")
    #     time.sleep(0.1)
    #     self.assertTrue(self.im.interface.stream_log_pair.read_log.logging_enabled)
    #     self.assertTrue(self.im.interface.stream_log_pair.write_log.logging_enabled)
    #     stop_raw_logging_router("ALL")
    #     time.sleep(0.1)
    #     self.assertFalse(self.im.interface.stream_log_pair.read_log.logging_enabled)
    #     self.assertFalse(self.im.interface.stream_log_pair.write_log.logging_enabled)
    #     # TODO: Need to explicitly shutdown stream_log_pair once started
    #     self.im.interface.stream_log_pair.shutdown()

    # def test_gets_router_name_and_all_info(self):
    #     info = get_all_router_info()
    #     self.assertEqual(info[0][0], "ROUTE_INT")
    #     self.assertEqual(info[0][1], "CONNECTED")

    # def test_sends_an_router_cmd(self):
    #     TestRouterApi.router_cmd_data = {}
    #     router_cmd("ROUTE_INT", "cmd1")
    #     time.sleep(0.1)
    #     self.assertEqual(list(TestRouterApi.router_cmd_data.keys()), ["cmd1"])
    #     self.assertEqual(TestRouterApi.router_cmd_data["cmd1"], ())

    #     TestRouterApi.router_cmd_data = {}
    #     router_cmd("ROUTE_INT", "cmd2", "param1")
    #     time.sleep(0.1)
    #     self.assertEqual(list(TestRouterApi.router_cmd_data.keys()), ["cmd2"])
    #     self.assertEqual(TestRouterApi.router_cmd_data["cmd2"], ("param1",))

    #     TestRouterApi.router_cmd_data = {}
    #     router_cmd("ROUTE_INT", "cmd3", "param1", "param2")
    #     time.sleep(0.1)
    #     self.assertEqual(list(TestRouterApi.router_cmd_data.keys()), ["cmd3"])
    #     self.assertEqual(
    #         TestRouterApi.router_cmd_data["cmd3"],
    #         (
    #             "param1",
    #             "param2",
    #         ),
    #     )

    # def test_sends_a_protocol_cmd(self):
    #     TestRouterApi.protocol_cmd_data = {}
    #     router_protocol_cmd("ROUTE_INT", "cmd1")
    #     time.sleep(0.1)
    #     self.assertEqual(list(TestRouterApi.protocol_cmd_data.keys()), ["cmd1"])
    #     self.assertEqual(TestRouterApi.protocol_cmd_data["cmd1"], ())

    #     TestRouterApi.protocol_cmd_data = {}
    #     router_protocol_cmd("ROUTE_INT", "cmd2", "param1")
    #     time.sleep(0.1)
    #     self.assertEqual(list(TestRouterApi.protocol_cmd_data.keys()), ["cmd2"])
    #     self.assertEqual(TestRouterApi.protocol_cmd_data["cmd2"], ("param1",))

    #     TestRouterApi.protocol_cmd_data = {}
    #     router_protocol_cmd("ROUTE_INT", "cmd3", "param1", "param2")
    #     time.sleep(0.1)
    #     self.assertEqual(list(TestRouterApi.protocol_cmd_data.keys()), ["cmd3"])
    #     self.assertEqual(
    #         TestRouterApi.protocol_cmd_data["cmd3"],
    #         (
    #             "param1",
    #             "param2",
    #         ),
    #     )
