# Copyright 2024 OpenC3, Inc.
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
from datetime import datetime, timezone
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.interface import Interface
from openc3.system.system import System
from openc3.config.config_parser import ConfigParser
from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel
from openc3.models.interface_model import InterfaceModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.topics.topic import Topic
from openc3.topics.interface_topic import InterfaceTopic
from openc3.microservices.interface_microservice import InterfaceMicroservice
from openc3.utilities.time import from_nsec_from_epoch


# This must be here in order to work when running more than this individual file
class MyInterface(Interface):
    connect_raise = False
    read_interface_raise = False

    def __init__(self, hostname="default", port=12345):
        self.hostname = hostname
        self.port = port
        self._connected = False
        self.connect_count = 0
        self.disconnect_count = 0
        self.disconnect_delay = 0
        self.connect_calls = 0
        super().__init__()

    def connect(self):
        self.connect_count += 1
        time.sleep(0.001)
        super().connect()
        self.data = b"\x00"
        self._connected = True
        if MyInterface.connect_raise:
            raise RuntimeError("test-error")

    def connected(self):
        return self._connected

    def disconnect(self):
        time.sleep(0.001)
        self.disconnect_count += 1
        self.data = None  # Upon disconnect the read_interface should return None
        time.sleep(self.disconnect_delay)
        self._connected = False
        super().disconnect()

    def read_interface(self):
        time.sleep(0.001)
        if MyInterface.read_interface_raise:
            raise RuntimeError("test-error")
        time.sleep(0.1)
        return self.data, None

    def interface_cmd(self, cmd_name, *cmd_args):
        self.interface_cmd_name = cmd_name
        self.interface_cmd_args = cmd_args

    def protocol_cmd(self, cmd_name, *cmd_args, read_write="READ_WRITE", index=-1):
        self.protocol_cmd_name = cmd_name
        self.protocol_cmd_args = cmd_args
        self.protocol_read_write = read_write
        self.protocol_index = index


class TestInterfaceMicroservice(unittest.TestCase):
    CONNECTING_MSG = "Connect"
    CONN_SUCCESS_MSG = "Connection Success"

    def setUp(self):
        mock_redis(self)
        setup_system()

        target = "INST"
        model = TargetModel(folder_name=target, name=target, scope="DEFAULT")
        model.create()

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc)
        packet.stored = False
        packet.check_limits()
        TelemetryDecomTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)  # Allow the write to happen

        mock_system = Mock(System)
        self.patch_system = patch("openc3.system.system.System", return_value=mock_system)
        self.mock_system = self.patch_system.start()
        self.addCleanup(self.patch_system.stop)

        self.patch_get_class = patch(
            "openc3.models.interface_model.get_class_from_module",
            return_value=MyInterface,
        )
        self.patch_get_class.start()
        self.addCleanup(self.patch_get_class.stop)

        # allow(System).to receive(:setup_targets).and_return(None)
        # self.interface = double("Interface").as_null_object
        # allow(self.interface).to receive(:connected?).and_return(True)
        # allow(System).to receive(:targets).and_return({ "INST" : self.interface })

        model = InterfaceModel(
            name="INST_INT",
            scope="DEFAULT",
            target_names=["INST"],
            cmd_target_names=["INST"],
            tlm_target_names=["INST"],
            config_params=["test_interface.py"],
        )
        model.create()
        model = MicroserviceModel(
            folder_name="INST",
            name="DEFAULT__INTERFACE__INST_INT",
            scope="DEFAULT",
            target_names=["INST"],
        )
        model.create()

        # Initialize the CVT so the setting of the packet_count can work
        for _, packet in System.telemetry.packets("INST").items():
            json_hash = CvtModel.build_json_from_packet(packet)
            CvtModel.set(
                json_hash,
                packet.target_name,
                packet.packet_name,
                scope="DEFAULT",
            )

    def test_creates_an_interface_updates_status_and_starts_cmd_thread(self):
        init_threads = threading.active_count()
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        self.assertEqual(im.config["name"], "DEFAULT__INTERFACE__INST_INT")
        self.assertEqual(im.interface.name, "INST_INT")
        self.assertEqual(im.interface.state, "ATTEMPTING")
        self.assertEqual(im.interface.target_names, ["INST"])
        self.assertEqual(im.interface.cmd_target_names, ["INST"])
        self.assertEqual(im.interface.tlm_target_names, ["INST"])
        data = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(data["INST_INT"]["name"], "INST_INT")
        self.assertEqual(data["INST_INT"]["state"], "ATTEMPTING")

        # Each interface microservice starts 3 threads: microservice_status_thread in microservice.rb
        # and the InterfaceCmdHandlerThread in interface_microservice.rb
        # and a metrics thread
        self.assertEqual(threading.active_count() - init_threads, 3)
        im.shutdown()
        time.sleep(0.1)  # Allow threads to exit
        self.assertEqual(threading.active_count(), init_threads)

    # def test_preserves_existing_packet_counts(self):
    #     # Initialize the telemetry topic with a non-zero RECEIVED_COUNT
    #     for _, packet in System.telemetry.packets("INST").items():
    #         packet.received_time = datetime.now(timezone.utc)
    #         packet.received_count = 10
    #         TelemetryTopic.write_packet(packet, scope="DEFAULT")
    #     im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
    #     for _, packet in System.telemetry.packets("INST").items():
    #         print(packet.read("RECEIVED_COUNT"))
    #         self.assertEqual(packet.read("RECEIVED_COUNT"), 10)
    #     im.shutdown()
    #     time.sleep(0.1)  # Allow threads to exit

    def test_handles_exceptions_in_connect(self):
        MyInterface.connect_raise = True
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")
        im.interface.reconnect_delay = 0.1  # Override the reconnect delay to be quick

        for stdout in capture_io():
            thread = threading.Thread(target=im.run)
            thread.start()
            time.sleep(0.1)
            self.assertIn(
                TestInterfaceMicroservice.CONNECTING_MSG,
                stdout.getvalue(),
            )
            self.assertIn(
                "Connection INST_INT failed due to RuntimeError('test-error')",
                stdout.getvalue(),
            )

            MyInterface.connect_raise = False
            time.sleep(0.5)
            all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
            self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")

            self.assertIn(
                TestInterfaceMicroservice.CONN_SUCCESS_MSG,
                stdout.getvalue(),
            )
            im.shutdown()

    def test_handles_exceptions_while_reading(self):
        MyInterface.read_interface_raise = True
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], ("ATTEMPTING"))
        im.interface.reconnect_delay = 0.1  # Override the reconnect delay to be quick
        for stdout in capture_io():
            thread = threading.Thread(target=im.run)
            thread.start()
            time.sleep(0.1)
            self.assertIn(TestInterfaceMicroservice.CONNECTING_MSG, stdout.getvalue())
            self.assertIn(TestInterfaceMicroservice.CONN_SUCCESS_MSG, stdout.getvalue())
            self.assertIn("Connection Lost: RuntimeError('test-error')", stdout.getvalue())

            MyInterface.read_interface_raise = False
            time.sleep(0.1)  # Allow to reconnect
            all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
            self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")
            im.shutdown()

    def test_connect_handles_parameters(self):
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")
        im.interface.reconnect_delay = 0.1  # Override the reconnect delay to be quick
        self.assertEqual(im.interface.hostname, "default")
        self.assertEqual(im.interface.port, 12345)

        for stdout in capture_io():
            thread = threading.Thread(target=im.run)
            thread.start()
            time.sleep(0.1)
            self.assertIn(TestInterfaceMicroservice.CONNECTING_MSG, stdout.getvalue())
            self.assertIn(TestInterfaceMicroservice.CONN_SUCCESS_MSG, stdout.getvalue())
            all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
            self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")
            self.assertEqual(im.interface.connect_count, 1)

        for stdout in capture_io():
            InterfaceTopic.connect_interface("INST_INT", "test-host", 54321, scope="DEFAULT")
            time.sleep(0.5)
            self.assertIn("Connection Lost", stdout.getvalue())
            self.assertIn(TestInterfaceMicroservice.CONNECTING_MSG, stdout.getvalue())
            self.assertIn(TestInterfaceMicroservice.CONN_SUCCESS_MSG, stdout.getvalue())
            all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
            self.assertIn(all_interfaces["INST_INT"]["state"], "CONNECTED")

            self.assertEqual(im.interface.port, 54321)
            im.shutdown()

    # def test_handles_exceptions_in_monitor_thread(self):
    #     im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
    #     all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
    #     self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")
    #     im.interface.reconnect_delay = 0.1  # Override the reconnect delay to be quick

    #     # for stdout in capture_io():
    #     thread = threading.Thread(target=im.run)
    #     thread.start()
    #     time.sleep(0.1)
    #     # self.assertIn(["RuntimeError"], stdout.getvalue())

    #     time.sleep(1.1)  # Give it time but it shouldn't connect
    #     all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
    #     self.assertIn(all_interfaces["INST_INT"]["state"], ["DISCONNECTED", "ATTEMPTING"])
    #     im.shutdown()

    def test_handles_a_clean_disconnect(self):
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")
        im.interface.reconnect_delay = 0.1  # Override the reconnect delay to be quick

        for stdout in capture_io():
            thread = threading.Thread(target=im.run)
            thread.start()
            time.sleep(0.1)
            all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
            self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")
            self.assertIn(TestInterfaceMicroservice.CONNECTING_MSG, stdout.getvalue())
            self.assertIn(TestInterfaceMicroservice.CONN_SUCCESS_MSG, stdout.getvalue())

            InterfaceTopic.disconnect_interface("INST_INT")
            time.sleep(1.01)  # Allow disconnect
            all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
            self.assertEqual(all_interfaces["INST_INT"]["state"], "DISCONNECTED")
            self.assertIn("Disconnect requested", stdout.getvalue())
            self.assertIn("Connection Lost", stdout.getvalue())

            # Wait and verify still DISCONNECTED and not ATTEMPTING
            time.sleep(0.5)
            all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
            self.assertEqual(all_interfaces["INST_INT"]["state"], "DISCONNECTED")
            self.assertEqual(im.interface.disconnect_count, 1)
            im.shutdown()

    # TODO: Not sure why this doesn't work ... the disconnect command never gets processed
    # def test_handles_a_interface_that_doesnt_allow_reads(self):
    #     im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
    #     all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
    #     self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")
    #     im.interface.read_allowed = False

    #     for stdout in capture_io():
    #         # Shouldn't cause error because read_interface shouldn't be called
    #         MyInterface.read_interface_raise = True
    #         thread = threading.Thread(target=im.run)
    #         thread.start()
    #         time.sleep(1.1)
    #         all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
    #         self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")
    #         self.assertIn(TestInterfaceMicroservice.CONNECTING_MSG, stdout.getvalue())
    #         self.assertIn(TestInterfaceMicroservice.CONN_SUCCESS_MSG, stdout.getvalue())
    #         self.assertIn("Starting connection maintenance", stdout.getvalue())

    #         print("SEND disconnect_interface")
    #         InterfaceTopic.disconnect_interface("INST_INT")
    #         time.sleep(
    #             2.01
    #         )  # Allow disconnect and wait for self.interface_thread_sleeper.sleep(1)
    #         all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
    #         self.assertEqual(all_interfaces["INST_INT"]["state"], "DISCONNECTED")
    #         self.assertIn("Disconnect requested", stdout.getvalue())
    #         self.assertIn("Connection Lost", stdout.getvalue())

    #         # Wait and verify still DISCONNECTED and not ATTEMPTING
    #         time.sleep(0.5)
    #         all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
    #         self.assertEqual(all_interfaces["INST_INT"]["state"], "DISCONNECTED")
    #         self.assertEqual(im.interface.disconnect_count, 1)
    #         im.shutdown()

    def test_supports_inject_tlm(self):
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")

        thread = threading.Thread(target=im.run)
        thread.start()
        time.sleep(0.1)
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")

        Topic.update_topic_offsets(["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"])
        InterfaceTopic.inject_tlm(
            "INST_INT",
            "INST",
            "HEALTH_STATUS",
            {"TEMP1": 10},
            type="RAW",
            scope="DEFAULT",
        )
        time.sleep(0.1)
        for _, _, msg_hash, _ in Topic.read_topics(["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"]):
            packet = System.telemetry.packet("INST", "HEALTH_STATUS")
            packet.stored = ConfigParser.handle_true_false(msg_hash[b"stored"].decode())
            packet.received_time = from_nsec_from_epoch(int(msg_hash[b"received_time"].decode()))
            packet.received_count = int(msg_hash[b"received_count"].decode())
            packet.buffer = msg_hash[b"buffer"]
            self.assertEqual(packet.read("TEMP1", "RAW"), 10)

        im.shutdown()

    def test_supports_interface_cmd(self):
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")

        thread = threading.Thread(target=im.run)
        thread.start()
        time.sleep(0.1)
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")

        InterfaceTopic.interface_cmd("INST_INT", "DO_THE_THING", "PARAM1", 2, scope="DEFAULT")
        time.sleep(0.5)
        self.assertEqual("DO_THE_THING", im.interface.interface_cmd_name)
        self.assertEqual(("PARAM1", 2), im.interface.interface_cmd_args)
        im.shutdown()

    def test_supports_protocol_cmd(self):
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "ATTEMPTING")

        thread = threading.Thread(target=im.run)
        thread.start()
        time.sleep(0.1)
        all_interfaces = InterfaceStatusModel.all(scope="DEFAULT")
        self.assertEqual(all_interfaces["INST_INT"]["state"], "CONNECTED")

        InterfaceTopic.protocol_cmd(
            "INST_INT",
            "DO_THE_OTHER_THING",
            "PARAM2",
            3,
            read_write="READ",
            index=3,
            scope="DEFAULT",
        )
        time.sleep(0.5)
        self.assertEqual("DO_THE_OTHER_THING", im.interface.protocol_cmd_name)
        self.assertEqual(("PARAM2", 3), im.interface.protocol_cmd_args)
        self.assertEqual("READ", im.interface.protocol_read_write)
        self.assertEqual(3, im.interface.protocol_index)
        im.shutdown()
