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

            def protocol_cmd(self, cmd_name, *cmd_params, read_write="READ_WRITE", index=-1):
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

    @patch("openc3.models.router_model.RouterModel.get_model")
    def test_maps_target_to_router(self, mock_get_model):
        # Create mock router with map_target method
        mock_router = Mock()
        mock_router.map_target = Mock()
        mock_get_model.return_value = mock_router

        # Test mapping single target
        map_target_to_router("INST", "ROUTE_INT")
        mock_get_model.assert_called_with(name="ROUTE_INT", scope="DEFAULT")
        mock_router.map_target.assert_called_with("INST", cmd_only=False, tlm_only=False, unmap_old=True)

        # Test mapping with cmd_only=True
        map_target_to_router("INST", "ROUTE_INT", cmd_only=True)
        mock_router.map_target.assert_called_with("INST", cmd_only=True, tlm_only=False, unmap_old=True)

        # Test mapping with tlm_only=True
        map_target_to_router("INST", "ROUTE_INT", tlm_only=True)
        mock_router.map_target.assert_called_with("INST", cmd_only=False, tlm_only=True, unmap_old=True)

        # Test mapping with unmap_old=False
        map_target_to_router("INST", "ROUTE_INT", unmap_old=False)
        mock_router.map_target.assert_called_with("INST", cmd_only=False, tlm_only=False, unmap_old=False)

        # Test mapping list of targets
        mock_router.map_target.reset_mock()
        map_target_to_router(["INST", "INST2"], "ROUTE_INT")
        self.assertEqual(mock_router.map_target.call_count, 2)
        mock_router.map_target.assert_any_call("INST", cmd_only=False, tlm_only=False, unmap_old=True)
        mock_router.map_target.assert_any_call("INST2", cmd_only=False, tlm_only=False, unmap_old=True)

        # Test with custom scope
        map_target_to_router("INST", "ROUTE_INT", scope="TEST")
        mock_get_model.assert_called_with(name="ROUTE_INT", scope="TEST")

    @patch("openc3.models.router_model.RouterModel.get_model")
    def test_unmaps_target_from_router(self, mock_get_model):
        # Create mock router with unmap_target method
        mock_router = Mock()
        mock_router.unmap_target = Mock()
        mock_get_model.return_value = mock_router

        # Test unmapping single target
        unmap_target_from_router("INST", "ROUTE_INT")
        mock_get_model.assert_called_with(name="ROUTE_INT", scope="DEFAULT")
        mock_router.unmap_target.assert_called_with("INST", cmd_only=False, tlm_only=False)

        # Test unmapping with cmd_only=True
        unmap_target_from_router("INST", "ROUTE_INT", cmd_only=True)
        mock_router.unmap_target.assert_called_with("INST", cmd_only=True, tlm_only=False)

        # Test unmapping with tlm_only=True
        unmap_target_from_router("INST", "ROUTE_INT", tlm_only=True)
        mock_router.unmap_target.assert_called_with("INST", cmd_only=False, tlm_only=True)

        # Test unmapping list of targets
        mock_router.unmap_target.reset_mock()
        unmap_target_from_router(["INST", "INST2"], "ROUTE_INT")
        self.assertEqual(mock_router.unmap_target.call_count, 2)
        mock_router.unmap_target.assert_any_call("INST", cmd_only=False, tlm_only=False)
        mock_router.unmap_target.assert_any_call("INST2", cmd_only=False, tlm_only=False)

        # Test with custom scope
        unmap_target_from_router("INST", "ROUTE_INT", scope="TEST")
        mock_get_model.assert_called_with(name="ROUTE_INT", scope="TEST")

    @patch("openc3.models.router_model.RouterModel.get_model")
    def test_map_target_to_router_error_handling(self, mock_get_model):
        # Test with non-existent router
        mock_get_model.side_effect = RuntimeError("Router 'NONEXISTENT_ROUTER' does not exist")
        with self.assertRaises(RuntimeError):
            map_target_to_router("INST", "NONEXISTENT_ROUTER")

        # Test with router.map_target raising exception
        mock_router = Mock()
        mock_router.map_target.side_effect = Exception("Map failed")
        mock_get_model.side_effect = None
        mock_get_model.return_value = mock_router
        
        with self.assertRaises(Exception):
            map_target_to_router("INST", "ROUTE_INT")

    @patch("openc3.models.router_model.RouterModel.get_model")
    def test_unmap_target_from_router_error_handling(self, mock_get_model):
        # Test with non-existent router
        mock_get_model.side_effect = RuntimeError("Router 'NONEXISTENT_ROUTER' does not exist")
        with self.assertRaises(RuntimeError):
            unmap_target_from_router("INST", "NONEXISTENT_ROUTER")

        # Test with router.unmap_target raising exception
        mock_router = Mock()
        mock_router.unmap_target.side_effect = Exception("Unmap failed")
        mock_get_model.side_effect = None
        mock_get_model.return_value = mock_router
        
        with self.assertRaises(Exception):
            unmap_target_from_router("INST", "ROUTE_INT")

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

    @patch("openc3.topics.router_topic.RouterTopic.router_target_enable")
    def test_enables_a_target_on_a_router(self, mock_enable):
        router_target_enable("ROUTE_INT", "INST")
        mock_enable.assert_called_with("ROUTE_INT", "INST", cmd_only=False, tlm_only=False, scope="DEFAULT")

        router_target_enable("ROUTE_INT", "INST", cmd_only=True)
        mock_enable.assert_called_with("ROUTE_INT", "INST", cmd_only=True, tlm_only=False, scope="DEFAULT")

        router_target_enable("ROUTE_INT", "INST", tlm_only=True)
        mock_enable.assert_called_with("ROUTE_INT", "INST", cmd_only=False, tlm_only=True, scope="DEFAULT")

    @patch("openc3.topics.router_topic.RouterTopic.router_target_disable")
    def test_disables_a_target_on_a_router(self, mock_disable):
        router_target_disable("ROUTE_INT", "INST")
        mock_disable.assert_called_with("ROUTE_INT", "INST", cmd_only=False, tlm_only=False, scope="DEFAULT")

        router_target_disable("ROUTE_INT", "INST", cmd_only=True)
        mock_disable.assert_called_with("ROUTE_INT", "INST", cmd_only=True, tlm_only=False, scope="DEFAULT")

        router_target_disable("ROUTE_INT", "INST", tlm_only=True)
        mock_disable.assert_called_with("ROUTE_INT", "INST", cmd_only=False, tlm_only=True, scope="DEFAULT")

    @patch("openc3.topics.router_topic.RouterTopic.router_details")
    def test_gets_router_details(self, mock_details):
        router_details("ROUTE_INT")
        mock_details.assert_called_with("ROUTE_INT", scope="DEFAULT")
