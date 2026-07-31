# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import threading
import time
import unittest
from datetime import datetime, timezone
from unittest.mock import *

from openc3.interfaces.interface import Interface
from openc3.microservices.router_microservice import RouterMicroservice
from openc3.models.cvt_model import CvtModel
from openc3.models.microservice_model import MicroserviceModel
from openc3.models.router_model import RouterModel
from openc3.models.router_status_model import RouterStatusModel
from openc3.models.target_model import TargetModel
from openc3.packets.packet import Packet
from openc3.system.system import System
from openc3.topics.router_topic import RouterTopic
from openc3.topics.telemetry_topic import TelemetryTopic
from openc3.topics.topic import Topic
from test.test_helper import *


# A router uses an Interface instance for its underlying connection, so we reuse
# the same simple test interface used by the interface microservice tests.
class MyInterface(Interface):
    def __init__(self, hostname="default", port=12345):
        self.hostname = hostname
        self.port = port
        self._connected = False
        self.connect_count = 0
        self.disconnect_count = 0
        self.disconnect_delay = 0
        self.written_packets = []
        super().__init__()

    def connect(self):
        self.connect_count += 1
        time.sleep(0.001)
        super().connect()
        self.data = b"\x00"
        self._connected = True

    def connected(self):
        return self._connected

    def disconnect(self):
        time.sleep(0.001)
        self.disconnect_count += 1
        self.data = None
        self._connected = False
        super().disconnect()

    def read_interface(self):
        time.sleep(0.01)
        return self.data, None

    def write_interface(self, data, extra=None):
        return data, extra

    def write(self, packet):
        self.written_packets.append(packet)

    def interface_cmd(self, cmd_name, *cmd_args):
        self.interface_cmd_name = cmd_name
        self.interface_cmd_args = cmd_args

    def protocol_cmd(self, cmd_name, *cmd_args, read_write="READ_WRITE", index=-1):
        self.protocol_cmd_name = cmd_name
        self.protocol_cmd_args = cmd_args
        self.protocol_read_write = read_write
        self.protocol_index = index


class TestRouterMicroservice(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

        model = TargetModel(folder_name="INST", name="INST", scope="DEFAULT")
        model.create()

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc)
        packet.stored = False
        packet.check_limits()
        TelemetryTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.01)

        mock_system = Mock(System)
        self.patch_system = patch("openc3.system.system.System", return_value=mock_system)
        self.patch_system.start()
        self.addCleanup(self.patch_system.stop)

        # RouterModel.build() resolves the interface class through interface_model
        self.patch_get_class = patch(
            "openc3.models.interface_model.get_class_from_module",
            return_value=MyInterface,
        )
        self.patch_get_class.start()
        self.addCleanup(self.patch_get_class.stop)

        model = RouterModel(
            name="TEST_INT",
            scope="DEFAULT",
            target_names=["INST"],
            cmd_target_names=["INST"],
            tlm_target_names=["INST"],
            config_params=["test_interface.py"],
        )
        model.create()
        model = MicroserviceModel(
            folder_name="TEST",
            name="DEFAULT__ROUTER__TEST_INT",
            scope="DEFAULT",
            target_names=["INST"],
        )
        model.create()

        # Initialize the CVT so packet counts can be set
        for _, packet in System.telemetry.packets("INST").items():
            json_hash = CvtModel.build_json_from_packet(packet)
            CvtModel.set(json_hash, packet.target_name, packet.packet_name, scope="DEFAULT")

    def _run(self, im):
        """Start the router read loop and register cleanup (LIFO: shutdown then join)."""
        thread = threading.Thread(target=im.run)
        thread.start()
        self.addCleanup(thread.join, 5)
        self.addCleanup(im.shutdown)
        time.sleep(0.2)  # Allow connect + handler thread startup
        return thread

    def test_creates_a_router_updates_status_and_starts_tlm_thread(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self.assertEqual(im.config["name"], "DEFAULT__ROUTER__TEST_INT")
        self.assertEqual(im.interface.name, "TEST_INT")
        self.assertEqual(im.interface.state, "ATTEMPTING")
        self.assertEqual(im.interface.target_names, ["INST"])
        self.assertEqual(im.interface.cmd_target_names, ["INST"])
        self.assertEqual(im.interface.tlm_target_names, ["INST"])

        data = RouterStatusModel.all(scope="DEFAULT")
        self.assertEqual(data["TEST_INT"]["name"], "TEST_INT")
        self.assertEqual(data["TEST_INT"]["state"], "ATTEMPTING")

        # The router telemetry handler thread is created and running. We check the
        # handler thread directly rather than the global thread count because the
        # metrics thread is a process-wide singleton, so the delta depends on test
        # ordering across the full suite.
        self.assertIsNotNone(im.handler_thread)
        self.assertTrue(im.handler_thread.thread.is_alive())

        # Shutdown cleanly stops the handler thread (the blocking read loop unwinds)
        im.shutdown()
        im.handler_thread.thread.join(5)  # Wait for the handler to exit (no fixed sleep race)
        self.assertFalse(im.handler_thread.thread.is_alive())

    def test_supports_router_cmd(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)
        data = RouterStatusModel.all(scope="DEFAULT")
        self.assertEqual(data["TEST_INT"]["state"], "CONNECTED")

        RouterTopic.router_cmd("TEST_INT", "DO_THE_THING", "PARAM1", 2, scope="DEFAULT")
        time.sleep(0.2)
        self.assertEqual("DO_THE_THING", im.interface.interface_cmd_name)
        self.assertEqual(("PARAM1", 2), im.interface.interface_cmd_args)

    def test_supports_protocol_cmd(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)

        RouterTopic.protocol_cmd(
            "TEST_INT", "DO_THE_OTHER_THING", "PARAM2", 3, read_write="READ", index=1, scope="DEFAULT"
        )
        time.sleep(0.2)
        self.assertEqual("DO_THE_OTHER_THING", im.interface.protocol_cmd_name)
        self.assertEqual(("PARAM2", 3), im.interface.protocol_cmd_args)
        self.assertEqual("READ", im.interface.protocol_read_write)
        self.assertEqual(1, im.interface.protocol_index)

    def test_supports_target_control(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)

        RouterTopic.router_target_disable("TEST_INT", "INST", scope="DEFAULT")
        time.sleep(0.2)
        self.assertFalse(im.interface.cmd_target_enabled["INST"])
        self.assertFalse(im.interface.tlm_target_enabled["INST"])

        RouterTopic.router_target_enable("TEST_INT", "INST", scope="DEFAULT")
        time.sleep(0.2)
        self.assertTrue(im.interface.cmd_target_enabled["INST"])
        self.assertTrue(im.interface.tlm_target_enabled["INST"])

    def test_supports_router_details(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)

        details = RouterTopic.router_details("TEST_INT", scope="DEFAULT", timeout=2.0)
        self.assertEqual(details["name"], "TEST_INT")

    def test_forwards_telemetry_to_the_router(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)
        data = RouterStatusModel.all(scope="DEFAULT")
        self.assertEqual(data["TEST_INT"]["state"], "CONNECTED")

        packet = System.telemetry.packet("INST", "HEALTH_STATUS")
        packet.received_time = datetime.now(timezone.utc)
        packet.received_count = 1
        TelemetryTopic.write_packet(packet, scope="DEFAULT")
        time.sleep(0.2)

        # The telemetry handler saw the packet and forwarded it out the router
        self.assertGreaterEqual(im.handler_thread.count, 1)
        self.assertGreaterEqual(len(im.interface.written_packets), 1)

    def test_handle_packet_routes_an_identified_command(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)
        im.interface.cmd_target_enabled["INST"] = True

        command = System.commands.build_cmd("INST", "ABORT")
        Topic.update_topic_offsets(["{DEFAULT__CMD}TARGET__INST"])
        im.handle_packet(command)

        # The command was routed to the target command topic
        found = False
        for _, _, msg_hash, _ in Topic.read_topics(["{DEFAULT__CMD}TARGET__INST"]):
            if msg_hash[b"target_name"].decode() == "INST" and msg_hash[b"cmd_name"].decode() == "ABORT":
                found = True
        self.assertTrue(found)

    def test_router_directive_disconnect_and_unknown(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)

        # An unrecognized router directive falls through to SUCCESS without error
        Topic.write_topic("{DEFAULT__CMD}ROUTER__TEST_INT", {"unknown": "1"}, "*", 100)
        time.sleep(0.2)

        # Disconnect directive disconnects the underlying interface
        RouterTopic.disconnect_router("TEST_INT", scope="DEFAULT")
        time.sleep(0.2)
        self.assertGreaterEqual(im.interface.disconnect_count, 1)

    def test_handle_packet_ignores_a_disabled_unidentified_packet(self):
        im = RouterMicroservice("DEFAULT__ROUTER__TEST_INT")
        self._run(im)

        # An unidentified packet maps to UNKNOWN which is not cmd enabled, so it
        # is not routed and does not raise
        packet = Packet(None, None, "BIG_ENDIAN")
        im.handle_packet(packet)
