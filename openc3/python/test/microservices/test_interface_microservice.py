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
import threading
from datetime import datetime, timezone
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.interface import Interface
from openc3.system.system import System
from openc3.models.cvt_model import CvtModel
from openc3.models.target_model import TargetModel
from openc3.models.interface_model import InterfaceModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.interface_status_model import InterfaceStatusModel
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.microservices.interface_microservice import InterfaceMicroservice


# This must be here in order to work when running more than this individual file
class MyInterface(Interface):
    read_allow_raise = False
    connect_raise = False
    disconnect_count = 0
    disconnect_delay = 0

    def __init__(self, hostname="default", port=12345):
        self.hostname = hostname
        self.port = port
        self.connected = False
        super().__init__()

    def read_allowed(self):
        if MyInterface.read_allowed_raise:
            raise RuntimeError("test-error")
        super().read_allowed()

    def connect(self):
        time.sleep(0.001)
        super().connect()
        self.data = b"\x00"
        self.connected = True
        if MyInterface.connect_raise:
            raise RuntimeError("test-error")

    def connected(self):
        return self.connected

    def disconnect(self):
        time.sleep(0.001)
        MyInterface.disconnect_count += 1
        self.data = None  # Upon disconnect the read_interface should return None
        time.sleep(MyInterface.disconnect_delay)
        self.connected = False
        super().disconnect()

    def read_interface(self):
        time.sleep(0.001)
        if MyInterface.read_interface_raise:
            raise RuntimeError("test-error")
        time.sleep(0.1)
        return self.data


class TestInterfaceMicroservice(unittest.TestCase):
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
        self.patch_system = patch(
            "openc3.system.system.System", return_value=mock_system
        )
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
        for packet_name, packet in System.telemetry.packets("INST").items():
            json_hash = CvtModel.build_json_from_packet(packet)
            CvtModel.set(
                json_hash,
                packet.target_name,
                packet.packet_name,
                scope="DEFAULT",
            )

    def test_creates_an_interface_updates_status_and_starts_cmd_thread(self):
        self.skipTest("not yet ready")
        init_threads = threading.active_count()
        im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
        self.assertEqual(im.config["name"], "DEFAULT__INTERFACE__INST_INT")
        self.assertEqual(im.interface.name, "INST_INT")
        self.assertEqual(im.interface.state, "ATTEMPTING")
        self.assertEqual(im.interface.target_names, ["INST"])
        self.assertEqual(im.interface.cmd_target_names, ["INST"])
        self.assertEqual(im.interface.tlm_target_names, ["INST"])
        time.sleep(0.1)
        data = InterfaceStatusModel.all(scope="DEFAULT")
        print(data)
        # self.assertEqual(data["INST_INT"]["name"], "INST_INT")
        # self.assertEqual(data["INST_INT"]["state"], "ATTEMPTING")

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
    #         # self.assertEqual(packet.read("RECEIVED_COUNT"), 10)
    #     im.shutdown()
    #     time.sleep(1.1)  # Allow threads to exit

    # def test_handles_exceptions_in_connect(self):
    #     MyInterface.connect_raise = True
    #     im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
    #     # all = InterfaceStatusModel.all(scope="DEFAULT")
    #     # self.assertEqual(all["INST_INT"]["state"], "ATTEMPTING")
    #     im.interface.reconnect_delay = 0.1  # Override the reconnect delay to be quick

    #     thread = threading.Thread(target=im.run)
    #     thread.start()
    #     time.sleep(1)

    #     MyInterface.connect_raise = False
    #     time.sleep(1)
    #     all = InterfaceStatusModel.all(scope="DEFAULT")
    #     self.assertEqual(all["INST_INT"]["state"], "CONNECTED")

    #     im.shutdown()
    #     time.sleep(0.1)

    # capture_io do |stdout|
    #   Thread() { im.run }
    #   sleep 1
    #   self.assertIn(["Connecting :"], stdout.string)
    #   expect(stdout.string).to_not include("Connection Success")
    #   self.assertIn(["Connection Failed= RuntimeError : test-error"], stdout.string)
    #   all = InterfaceStatusModel.all(scope= "DEFAULT")
    #   self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")

    #   $connect_raise = False
    #   sleep 1 # Allow it to reconnect successfully
    #   all = InterfaceStatusModel.all(scope= "DEFAULT")
    #   self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")
    #   im.shutdown()


#     def test_handles_exceptions_while_reading(self):
#         $read_interface_raise = True
#         im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"], ("ATTEMPTING"))
#         interface = im.instance_variable_get(:self.interface)
#         interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick
#         capture_io do |stdout|
#           Thread() { im.run }
#           sleep 1
#           self.assertIn(["Connecting :"], stdout.string)
#           self.assertIn(["Connection Success"], stdout.string)
#           self.assertIn(["Connection Lost= RuntimeError : test-error"], stdout.string)

#           $read_interface_raise = False
#           sleep 1 # Allow to reconnect
#           all = InterfaceStatusModel.all(scope= "DEFAULT")
#           self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")
#           im.shutdown

# class Connect(unittest.TestCase):
#     def test_handles_parameters(self):
#         im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")
#         time.sleep(0.1)
#         interface = im.instance_variable_get(:self.interface)
#         interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick
#         self.assertEqual(interface.instance_variable_get(:self.hostname),  'default')
#         self.assertEqual(interface.instance_variable_get(:self.port),  12345)

#         capture_io do |stdout|
#           Thread() { im.run }
#           sleep 1
#           self.assertIn(["Connecting :"], stdout.string)
#           self.assertIn(["Connection Success"], stdout.string)
#           all = InterfaceStatusModel.all(scope= "DEFAULT")
#           self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")

#         # Expect the interface double to have interface= called on it to set the new interface
#         expect(self.interface).to receive(:interface=)
#         capture_io do |stdout|
#           InterfaceTopic.connect_interface("INST_INT", 'test-host', 54321, scope= 'DEFAULT')
#           sleep 1
#           self.assertIn(["Connection Lost"], stdout.string)
#           self.assertIn(["Connecting :"], stdout.string)
#           self.assertIn(["Connection Success"], stdout.string)
#           all = InterfaceStatusModel.all(scope= "DEFAULT")
#           self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")

#         interface = im.instance_variable_get(:self.interface)
#         self.assertEqual(interface.instance_variable_get(:self.hostname),  'test-host')
#         self.assertEqual(interface.instance_variable_get(:self.port),  54321)
#         im.shutdown

#     def test_handles_exceptions_in_monitor_thread(self):
#       $read_allowed_raise = True
#       im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")
#       interface = im.instance_variable_get(:self.interface)
#       interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

#       capture_io do |stdout|
#         Thread() { im.run }
#         time.sleep(0.1) # Allow to start and immediately crash
#         self.assertIn(["RuntimeError"], stdout.string)

#         sleep 1 # Give it time but it shouldn't connect
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertIn('DISCONNECTED|ATTEMPTING', all["INST_INT"]["state"])
#         im.shutdown

#     def test_handles_a_clean_disconnect(self):
#       im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")
#       interface = im.instance_variable_get(:self.interface)
#       interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

#       capture_io do |stdout|
#         Thread() { im.run }
#         sleep 0.5 # Allow to start
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")
#         self.assertIn(["Connecting :"], stdout.string)
#         self.assertIn(["Connection Success"], stdout.string)

#         self.api.disconnect_interface("INST_INT")
#         sleep 1 # Allow disconnect
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "DISCONNECTED")
#         self.assertIn(["Disconnect requested"], stdout.string)
#         self.assertIn(["Connection Lost"], stdout.string)

#         # Wait and verify still DISCONNECTED and not ATTEMPTING
#         sleep 0.5
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "DISCONNECTED")
#         self.assertEqual($disconnect_count,  1)

#         im.shutdown

#     def test_handles_long_disconnect_delays(self):
#       im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")
#       interface = im.instance_variable_get(:self.interface)
#       interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

#       capture_io do |stdout|
#         Thread() { im.run }
#         sleep 0.5 # Allow to start
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")
#         self.assertIn(["Connecting :"], stdout.string)
#         self.assertIn(["Connection Success"], stdout.string)

#         $disconnect_delay = 0.5
#         self.api.disconnect_interface("INST_INT")
#         sleep 1 # Allow disconnect
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "DISCONNECTED")
#         self.assertIn(["Disconnect requested"], stdout.string)
#         self.assertIn(["Connection Lost"], stdout.string)

#         # Wait and verify still DISCONNECTED and not ATTEMPTING
#         sleep 0.5
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "DISCONNECTED")
#         self.assertEqual($disconnect_count,  1)

#         im.shutdown

#     def test_handles_a_interface_that_doesnt_allow_reads(self):
#       im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")
#       interface = im.instance_variable_get(:self.interface)
#       interface.instance_variable_set(:self.read_allowed, False)

#       capture_io do |stdout|
#         # Shouldn't cause error because read_interface shouldn't be called
#         $read_interface_raise = True
#         Thread() { im.run }
#         sleep 0.5 # Allow to start
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")
#         self.assertIn(["Connecting :"], stdout.string)
#         self.assertIn(["Connection Success"], stdout.string)
#         self.assertIn(["Starting connection maintenance"], stdout.string)

#         self.api.disconnect_interface("INST_INT")
#         sleep 2 # Allow disconnect and wait for self.interface_thread_sleeper.sleep(1)
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "DISCONNECTED")
#         expect(stdout.string).to match(/Disconnect requested/m)
#         expect(stdout.string).to match(/Connection Lost/m)

#         # Wait and verify still DISCONNECTED and not ATTEMPTING
#         sleep 0.5
#         all = InterfaceStatusModel.all(scope= "DEFAULT")
#         self.assertEqual(all["INST_INT"]["state"],  "DISCONNECTED")
#         self.assertEqual($disconnect_count,  1)

#         im.shutdown

#     def test_supports_inject_tlm(self):
#       im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")

#       Thread() { im.run }
#       sleep 0.5 # Allow to start
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")

#       Topic.update_topic_offsets(["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"])
#       self.api.inject_tlm("INST", "HEALTH_STATUS", { TEMP1: 10 }, type= 'RAW')
#       sleep 2
#       packets = Topic.read_topics(["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"])
#       self.assertEqual(len(packets),  1)
#       msg_hash = packets["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"][0][1]
#       packet = System.telemetry.packet("INST", "HEALTH_STATUS")
#       packet.stored = ConfigParser.handle_True_False(msg_hash["stored"])
#       packet.received_time = Time.from_nsec_from_epoch(msg_hash["received_time"] int())
#       packet.received_count = msg_hash["received_count"] int()
#       packet.buffer = msg_hash["buffer"]
#       self.assertEqual(packet.read("TEMP1", 'RAW'),  10)
#       im.shutdown

#     def test_supports_interface_cmd(self):
#       im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")
#       interface = im.instance_variable_get(:self.interface)
#       expect(interface).to receive(:interface_cmd).with("DO_THE_THING", "PARAM1", 2)

#       Thread() { im.run }
#       sleep 0.5 # Allow to start
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")

#       self.api.interface_cmd("INST_INT", "DO_THE_THING", "PARAM1", 2, scope= "DEFAULT")
#       im.shutdown

#     def test_supports_protocol_cmd(self):
#       im = InterfaceMicroservice("DEFAULT__INTERFACE__INST_INT")
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "ATTEMPTING")
#       interface = im.instance_variable_get(:self.interface)
#       expect(interface).to receive(:protocol_cmd).with("DO_THE_OTHER_THING", "PARAM1", 2, {:index : -1, :read_write : "READ_WRITE"})

#       Thread() { im.run }
#       sleep 0.5 # Allow to start
#       all = InterfaceStatusModel.all(scope= "DEFAULT")
#       self.assertEqual(all["INST_INT"]["state"],  "CONNECTED")

#       self.api.interface_protocol_cmd("INST_INT", "DO_THE_OTHER_THING", "PARAM1", 2, scope= "DEFAULT")
#       im.shutdown
