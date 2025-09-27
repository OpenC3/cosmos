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
import threading
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.api.interface_api import *
from openc3.interfaces.interface import Interface
from openc3.models.target_model import TargetModel
from openc3.models.interface_model import InterfaceModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.microservices.interface_microservice import InterfaceMicroservice


class TestInterfaceApi(unittest.TestCase):
    interface_cmd_data = {}
    protocol_cmd_data = {}

    @patch("openc3.models.interface_model.InterfaceModel.get_model")
    @patch("openc3.microservices.interface_microservice.System")
    def setUp(self, mock_system, mock_get_model):
        mock_redis(self)
        setup_system()

        class MyInterface(Interface):
            target_names = ["INST"]

            def connected(self):
                return True

            def disconnect(self):
                pass

            def read_interface(self):
                time.sleep(0.001)
                return (b"\x01\x02\x03\x04", None)

            def interface_cmd(self, cmd_name, *cmd_params):
                TestInterfaceApi.interface_cmd_data[cmd_name] = cmd_params

            def protocol_cmd(self, cmd_name, *cmd_params, read_write="READ_WRITE", index=-1):
                TestInterfaceApi.protocol_cmd_data[cmd_name] = cmd_params

            # Allow the stubbed InterfaceModel.get_model to call build()
            @staticmethod
            def build():
                return MyInterface()

        mock_get_model.return_value = MyInterface

        model = InterfaceModel(
            name="INST_INT",
            scope="DEFAULT",
            target_names=["INST"],
            cmd_target_names=["INST"],
            tlm_target_names=["INST"],
            config_params=["openc3/interfaces/interface.py"],
        )
        model.create()
        self.im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        self.im_thread = threading.Thread(target=self.im.run)
        self.im_thread.start()
        time.sleep(0.001)  # Allow the thread to run

    def tearDown(self):
        self.im.shutdown()
        self.im.graceful_kill()
        self.im_thread.join()

    def test_returns_interface_hash(self):
        interface = get_interface("INST_INT")
        self.assertEqual(type(interface), dict)
        self.assertEqual(interface["name"], "INST_INT")
        # Verify it also includes the status
        self.assertIn(get_interface("INST_INT")["state"], ["ATTEMPTING", "CONNECTED"])
        self.assertEqual(interface["clients"], 0)

    def test_returns_all_interface_names(self):
        model = InterfaceModel(name="INT1", scope="DEFAULT")
        model.create()
        model = InterfaceModel(name="INT2", scope="DEFAULT")
        model.create()
        self.assertEqual(get_interface_names(), ["INST_INT", "INT1", "INT2"])

    def test_connects_the_interface(self):
        self.assertIn(get_interface("INST_INT")["state"], ["ATTEMPTING", "CONNECTED"])
        disconnect_interface("INST_INT")
        time.sleep(0.05)
        self.assertEqual(get_interface("INST_INT")["state"], "DISCONNECTED")
        connect_interface("INST_INT")
        time.sleep(0.05)
        self.assertIn(get_interface("INST_INT")["state"], ["ATTEMPTING", "CONNECTED"])

    def test_should_start_and_stop_raw_logging_on_the_interface(self):
        self.assertIsNone(self.im.interface.stream_log_pair)
        start_raw_logging_interface("INST_INT")
        time.sleep(0.05)
        self.assertTrue(self.im.interface.stream_log_pair.read_log.logging_enabled)
        self.assertTrue(self.im.interface.stream_log_pair.write_log.logging_enabled)
        stop_raw_logging_interface("INST_INT")
        time.sleep(0.05)
        self.assertFalse(self.im.interface.stream_log_pair.read_log.logging_enabled)
        self.assertFalse(self.im.interface.stream_log_pair.write_log.logging_enabled)

        start_raw_logging_interface("ALL")
        time.sleep(0.05)
        self.assertTrue(self.im.interface.stream_log_pair.read_log.logging_enabled)
        self.assertTrue(self.im.interface.stream_log_pair.write_log.logging_enabled)
        stop_raw_logging_interface("ALL")
        time.sleep(0.05)
        self.assertFalse(self.im.interface.stream_log_pair.read_log.logging_enabled)
        self.assertFalse(self.im.interface.stream_log_pair.write_log.logging_enabled)
        self.im.interface.stream_log_pair.shutdown()

    def test_gets_interface_name_and_all_info(self):
        info = get_all_interface_info()
        self.assertEqual(info[0][0], "INST_INT")
        self.assertIn(info[0][1], ["ATTEMPTING", "CONNECTED"])
        self.assertEqual(info[0][2], 0)
        self.assertEqual(info[0][3], 0)
        self.assertEqual(info[0][4], 0)
        self.assertEqual(info[0][5], 0)
        self.assertEqual(info[0][6], 0)
        self.assertEqual(info[0][7], 0)
        # self.assertEqual(info[0][8], 0) # Might increment because InterfaceMicroservice is running
        self.assertEqual(info[0][9], False)

        model = InterfaceModel.get_model(name="INST_INT", scope="DEFAULT")
        model.disable_disconnect = True
        model.update()

        info = get_all_interface_info()
        self.assertEqual(info[0][0], "INST_INT")
        self.assertIn(info[0][1], ["ATTEMPTING", "CONNECTED"])
        self.assertEqual(info[0][2], 0)
        self.assertEqual(info[0][3], 0)
        self.assertEqual(info[0][4], 0)
        self.assertEqual(info[0][5], 0)
        self.assertEqual(info[0][6], 0)
        self.assertEqual(info[0][7], 0)
        # self.assertEqual(info[0][8], 0) # Might increment because InterfaceMicroservice is running
        self.assertEqual(info[0][9], True)

    def test_successfully_maps_a_target_to_an_interface(self):
        TargetModel(name="INST", scope="DEFAULT").create()
        TargetModel(name="INST2", scope="DEFAULT").create()

        model = MicroserviceModel(
            name="DEFAULT__INTERFACE__INST_INT",
            scope="DEFAULT",
            target_names=["INST"],
        )
        model.create()
        model = MicroserviceModel(
            name="DEFAULT__INTERFACE__INST2_INT",
            scope="DEFAULT",
            target_names=["INST2"],
        )
        model.create()

        model2 = InterfaceModel(
            name="INST2_INT",
            scope="DEFAULT",
            target_names=["INST2"],
            cmd_target_names=["INST2"],
            tlm_target_names=["INST2"],
            config_params=["openc3/interfaces/interface.py"],
        )
        model2.create()
        self.assertEqual(model2.target_names, ["INST2"])

        map_target_to_interface("INST2", "INST_INT")

        model1 = InterfaceModel.get_model(name="INST_INT", scope="DEFAULT")
        model2 = InterfaceModel.get_model(name="INST2_INT", scope="DEFAULT")
        self.assertEqual(model1.target_names, ["INST", "INST2"])
        self.assertEqual(model2.target_names, [])

    @patch("openc3.models.interface_model.InterfaceModel.get_model")
    def test_unmaps_target_from_interface(self, mock_get_model):
        # Create mock interface with unmap_target method
        mock_interface = Mock()
        mock_interface.unmap_target = Mock()
        mock_get_model.return_value = mock_interface

        # Test unmapping single target
        unmap_target_from_interface("INST", "INST_INT")
        mock_get_model.assert_called_with(name="INST_INT", scope="DEFAULT")
        mock_interface.unmap_target.assert_called_with("INST", cmd_only=False, tlm_only=False)

        # Test unmapping with cmd_only=True
        unmap_target_from_interface("INST", "INST_INT", cmd_only=True)
        mock_interface.unmap_target.assert_called_with("INST", cmd_only=True, tlm_only=False)

        # Test unmapping with tlm_only=True
        unmap_target_from_interface("INST", "INST_INT", tlm_only=True)
        mock_interface.unmap_target.assert_called_with("INST", cmd_only=False, tlm_only=True)

        # Test unmapping list of targets
        mock_interface.unmap_target.reset_mock()
        unmap_target_from_interface(["INST", "INST2"], "INST_INT")
        self.assertEqual(mock_interface.unmap_target.call_count, 2)
        mock_interface.unmap_target.assert_any_call("INST", cmd_only=False, tlm_only=False)
        mock_interface.unmap_target.assert_any_call("INST2", cmd_only=False, tlm_only=False)

        # Test with custom scope
        unmap_target_from_interface("INST", "INST_INT", scope="TEST")
        mock_get_model.assert_called_with(name="INST_INT", scope="TEST")

    @patch("openc3.models.interface_model.InterfaceModel.get_model")
    def test_unmap_target_from_interface_error_handling(self, mock_get_model):
        # Test with non-existent interface
        mock_get_model.side_effect = RuntimeError("Interface 'NONEXISTENT_INT' does not exist")
        with self.assertRaises(RuntimeError):
            unmap_target_from_interface("INST", "NONEXISTENT_INT")

        # Test with interface.unmap_target raising exception
        mock_interface = Mock()
        mock_interface.unmap_target.side_effect = Exception("Unmap failed")
        mock_get_model.side_effect = None
        mock_get_model.return_value = mock_interface
        
        with self.assertRaises(Exception):
            unmap_target_from_interface("INST", "INST_INT")

    def test_sends_an_interface_cmd(self):
        TestInterfaceApi.interface_cmd_data = {}
        interface_cmd("INST_INT", "cmd1")
        time.sleep(0.05)
        self.assertEqual(list(TestInterfaceApi.interface_cmd_data.keys()), ["cmd1"])
        self.assertEqual(TestInterfaceApi.interface_cmd_data["cmd1"], ())

        TestInterfaceApi.interface_cmd_data = {}
        interface_cmd("INST_INT", "cmd2", "param1")
        time.sleep(0.05)
        self.assertEqual(list(TestInterfaceApi.interface_cmd_data.keys()), ["cmd2"])
        self.assertEqual(TestInterfaceApi.interface_cmd_data["cmd2"], ("param1",))

        TestInterfaceApi.interface_cmd_data = {}
        interface_cmd("INST_INT", "cmd3", "param1", "param2")
        time.sleep(0.05)
        self.assertEqual(list(TestInterfaceApi.interface_cmd_data.keys()), ["cmd3"])
        self.assertEqual(
            TestInterfaceApi.interface_cmd_data["cmd3"],
            (
                "param1",
                "param2",
            ),
        )

    def test_sends_a_protocol_cmd(self):
        TestInterfaceApi.protocol_cmd_data = {}
        interface_protocol_cmd("INST_INT", "cmd1")
        time.sleep(0.05)
        self.assertEqual(list(TestInterfaceApi.protocol_cmd_data.keys()), ["cmd1"])
        self.assertEqual(TestInterfaceApi.protocol_cmd_data["cmd1"], ())

        TestInterfaceApi.protocol_cmd_data = {}
        interface_protocol_cmd("INST_INT", "cmd2", "param1")
        time.sleep(0.05)
        self.assertEqual(list(TestInterfaceApi.protocol_cmd_data.keys()), ["cmd2"])
        self.assertEqual(TestInterfaceApi.protocol_cmd_data["cmd2"], ("param1",))

        TestInterfaceApi.protocol_cmd_data = {}
        interface_protocol_cmd("INST_INT", "cmd3", "param1", "param2")
        time.sleep(0.05)
        self.assertEqual(list(TestInterfaceApi.protocol_cmd_data.keys()), ["cmd3"])
        self.assertEqual(
            TestInterfaceApi.protocol_cmd_data["cmd3"],
            (
                "param1",
                "param2",
            ),
        )

    @patch("openc3.topics.interface_topic.InterfaceTopic.interface_target_enable")
    def test_enables_a_target_on_an_interface(self, mock_enable):
        interface_target_enable("INST_INT", "INST")
        mock_enable.assert_called_with("INST_INT", "INST", cmd_only=False, tlm_only=False, scope="DEFAULT")

        interface_target_enable("INST_INT", "INST", cmd_only=True)
        mock_enable.assert_called_with("INST_INT", "INST", cmd_only=True, tlm_only=False, scope="DEFAULT")

        interface_target_enable("INST_INT", "INST", tlm_only=True)
        mock_enable.assert_called_with("INST_INT", "INST", cmd_only=False, tlm_only=True, scope="DEFAULT")

    @patch("openc3.topics.interface_topic.InterfaceTopic.interface_target_disable")
    def test_disables_a_target_on_an_interface(self, mock_disable):
        interface_target_disable("INST_INT", "INST")
        mock_disable.assert_called_with("INST_INT", "INST", cmd_only=False, tlm_only=False, scope="DEFAULT")

        interface_target_disable("INST_INT", "INST", cmd_only=True)
        mock_disable.assert_called_with("INST_INT", "INST", cmd_only=True, tlm_only=False, scope="DEFAULT")

        interface_target_disable("INST_INT", "INST", tlm_only=True)
        mock_disable.assert_called_with("INST_INT", "INST", cmd_only=False, tlm_only=True, scope="DEFAULT")

    @patch("openc3.topics.interface_topic.InterfaceTopic.interface_details")
    def test_gets_interface_details(self, mock_details):
        interface_details("INST_INT")
        mock_details.assert_called_with("INST_INT", scope="DEFAULT")
