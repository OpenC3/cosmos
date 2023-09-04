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
import datetime
import threading
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.stream_interface import StreamInterface
from openc3.interfaces.protocols.ignore_packet_protocol import IgnorePacketProtocol
from openc3.packets.packet import Packet
from openc3.streams.stream import Stream


class TestIgnorePacketProtocol(unittest.TestCase):
    buffer = None
    packet = None

    class IgnorePreStream(Stream):
        def __init__(self, *args):
            super().__init__(*args)
            self.run = True

        def connect(self):
            self.run = True

        def connected(self):
            return True

        def disconnect(self):
            self.run = False

        def read(self):
            if self.run:
                time.sleep(0.01)
                return TestIgnorePacketProtocol.buffer
            else:
                raise RuntimeError("Done")

        def write(self, data):
            TestIgnorePacketProtocol.buffer = data

    class MyInterface(StreamInterface):
        def connected(self):
            return True

    @classmethod
    def setUpClass(cls):
        setup_system()

    def setUp(self):
        self.interface = TestIgnorePacketProtocol.MyInterface()
        self.interface.target_names = ["SYSTEM", "INST"]
        self.interface.cmd_target_names = ["SYSTEM", "INST"]
        self.interface.tlm_target_names = ["SYSTEM", "INST"]

    def test_complains_if_target_is_not_given(self):
        with self.assertRaises(TypeError):
            self.interface.add_protocol(IgnorePacketProtocol, [], "READ_WRITE")

    def test_complains_if_packet_is_not_given(self):
        with self.assertRaises(TypeError):
            self.interface.add_protocol(IgnorePacketProtocol, ["SYSTEM"], "READ_WRITE")

    def test_complains_if_the_target_is_not_found(self):
        with self.assertRaisesRegex(RuntimeError, "target 'BLAH' does not exist"):
            self.interface.add_protocol(
                IgnorePacketProtocol, ["BLAH", "META"], "READ_WRITE"
            )

    def test_complains_if_the_packet_is_not_found(self):
        with self.assertRaisesRegex(
            RuntimeError, "packet 'SYSTEM BLAH' does not exist"
        ):
            self.interface.add_protocol(
                IgnorePacketProtocol, ["SYSTEM", "BLAH"], "READ_WRITE"
            )

    def test_read_ignores_the_packet_specified(self):
        self.interface.stream = TestIgnorePacketProtocol.IgnorePreStream()
        pkt = System.telemetry.packet("SYSTEM", "META")
        # Ensure the ID items are set so this packet can be identified
        for item in pkt.id_items:
            pkt.write_item(item, item.id_value)
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        # Verify the write went out
        self.assertEqual(pkt.buffer, TestIgnorePacketProtocol.buffer)
        # Verify we read the packet back
        packet = self.interface.read()
        self.assertEqual(packet.buffer, TestIgnorePacketProtocol.buffer)

        # Now add the protocol to ignore the packet
        self.interface.add_protocol(IgnorePacketProtocol, ["SYSTEM", "META"], "READ")
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)

        # Try to read the interface
        # We put this in a thread because it blocks and calls it continuously
        def my_read():
            try:
                TestIgnorePacketProtocol.packet = self.interface.read()
            except RuntimeError:
                pass

        thread = threading.Thread(target=my_read)
        thread.start()
        time.sleep(0.1)
        self.interface.disconnect()
        self.interface.stream.disconnect()
        self.assertIsNone(TestIgnorePacketProtocol.packet)

    def test_read_can_be_added_multiple_times_to_ignore_different_packets(self):
        self.interface.stream = TestIgnorePacketProtocol.IgnorePreStream()

        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        # Ensure the ID items are set so this packet can be identified
        for item in pkt.id_items:
            pkt.write_item(item, item.id_value)
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        self.assertEqual(TestIgnorePacketProtocol.buffer, pkt.buffer)

        # Verify we read the packet back
        packet = self.interface.read()
        self.assertEqual(packet.buffer, TestIgnorePacketProtocol.buffer)

        # Now add the protocol to ignore the packet
        self.interface.add_protocol(
            IgnorePacketProtocol, ["INST", "HEALTH_STATUS"], "READ"
        )
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        self.assertEqual(TestIgnorePacketProtocol.buffer, pkt.buffer)

        # Try to read the interface
        # We put this in a thread because it calls it continuously
        def my_read():
            try:
                TestIgnorePacketProtocol.packet = self.interface.read()
            except RuntimeError:
                pass

        thread = threading.Thread(target=my_read)
        thread.start()
        time.sleep(0.1)
        self.interface.disconnect()
        self.interface.stream.disconnect()
        thread.join()
        self.interface.connect()
        self.interface.stream.connect()
        self.assertIsNone(TestIgnorePacketProtocol.packet)

        # Add another protocol to ignore another packet
        self.interface.add_protocol(IgnorePacketProtocol, ["INST", "ADCS"], "READ")

        pkt = System.telemetry.packet("INST", "ADCS")
        # Ensure the ID items are set so this packet can be identified
        for item in pkt.id_items:
            pkt.write_item(item, item.id_value)
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        self.assertEqual(TestIgnorePacketProtocol.buffer, pkt.buffer)

        # Try to read the interface
        # We put this in a thread because it calls it continuously
        def my_read2():
            try:
                TestIgnorePacketProtocol.packet = self.interface.read()
            except RuntimeError:
                pass

        thread = threading.Thread(target=my_read2)
        thread.start()
        time.sleep(0.1)
        self.interface.disconnect()
        self.interface.stream.disconnect()
        thread.join()
        self.interface.connect()
        self.interface.stream.connect()
        self.assertIsNone(TestIgnorePacketProtocol.packet)

        pkt = System.telemetry.packet("INST", "PARAMS")
        # Ensure the ID items are set so this packet can be identified
        for item in pkt.id_items:
            pkt.write_item(item, item.id_value)
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        # Verify the write went out
        self.assertEqual(TestIgnorePacketProtocol.buffer, pkt.buffer)

        packet = self.interface.read()
        self.assertEqual(packet.buffer, pkt.buffer)

    def test_write_ignores_the_packet_specified(self):
        self.interface.stream = TestIgnorePacketProtocol.IgnorePreStream()
        self.interface.add_protocol(IgnorePacketProtocol, ["SYSTEM", "META"], "WRITE")
        pkt = System.telemetry.packet("SYSTEM", "META")
        pkt.write("OPENC3_VERSION", "TEST")
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        # Verify the write was ignored
        self.assertIsNone(TestIgnorePacketProtocol.buffer)

        # Verify reading the interface works
        TestIgnorePacketProtocol.buffer = pkt.buffer
        packet = self.interface.read()
        self.assertEqual(packet.buffer, TestIgnorePacketProtocol.buffer)

    def test_write_can_be_added_multiple_times_to_ignore_different_packets(self):
        self.interface.stream = TestIgnorePacketProtocol.IgnorePreStream()
        self.interface.add_protocol(
            IgnorePacketProtocol, ["INST", "HEALTH_STATUS"], "WRITE"
        )
        self.interface.add_protocol(IgnorePacketProtocol, ["INST", "ADCS"], "WRITE")

        pkt = System.telemetry.packet("INST", "HEALTH_STATUS")
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        # Verify the write was ignored
        self.assertIsNone(TestIgnorePacketProtocol.buffer)

        pkt = System.telemetry.packet("INST", "ADCS")
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        # Verify the write was ignored
        self.assertIsNone(TestIgnorePacketProtocol.buffer)

        pkt = System.telemetry.packet("INST", "PARAMS")
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        # Verify the write went out
        self.assertEqual(TestIgnorePacketProtocol.buffer, pkt.buffer)

    def test_read_write_ignores_the_packet_specified(self):
        self.interface.stream = TestIgnorePacketProtocol.IgnorePreStream()
        self.interface.add_protocol(
            IgnorePacketProtocol, ["SYSTEM", "META"], "READ_WRITE"
        )
        pkt = System.telemetry.packet("SYSTEM", "META")
        pkt.write("OPENC3_VERSION", "TEST")
        pkt.received_time = datetime.datetime.now()
        TestIgnorePacketProtocol.buffer = None
        self.interface.write(pkt)
        # Verify the write was ignored
        self.assertIsNone(TestIgnorePacketProtocol.buffer)

        def my_read():
            try:
                TestIgnorePacketProtocol.packet = self.interface.read()
            except RuntimeError:
                pass

        thread = threading.Thread(target=my_read)
        thread.start()
        time.sleep(0.1)
        self.interface.disconnect()
        self.interface.stream.disconnect()
        thread.join()
        self.assertIsNone(TestIgnorePacketProtocol.packet)

    def test_reads_and_writes_unknown_packets(self):
        self.interface.stream = TestIgnorePacketProtocol.IgnorePreStream()
        self.interface.add_protocol(
            IgnorePacketProtocol, ["SYSTEM", "META"], "READ_WRITE"
        )
        TestIgnorePacketProtocol.buffer = None
        pkt = Packet("TGT", "PTK")
        pkt.append_item("ITEM", 8, "INT")
        pkt.write("ITEM", 33, "RAW")
        self.interface.write(pkt)
        # Verify the write went out
        self.assertEqual(pkt.buffer, TestIgnorePacketProtocol.buffer)

        # Verify the read works
        packet = self.interface.read()
        self.assertEqual(packet.buffer, TestIgnorePacketProtocol.buffer)
