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
import socket
import threading
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.udp_interface import UdpInterface
from openc3.io.udp_sockets import UdpReadSocket, UdpWriteSocket
from openc3.packets.packet import Packet
from openc3.top_level import close_socket
from openc3.utilities.bucket_utilities import BucketUtilities


class TestUdpInterface(unittest.TestCase):
    def test_initializes_the_instance_variables(self):
        i = UdpInterface(
            "localhost",
            "8888",
            "8889",
            "8890",
            "localhost",
            "64",
            "5",
            "5",
            "localhost",
        )
        self.assertEqual(i.hostname, "127.0.0.1")
        self.assertEqual(i.interface_address, "127.0.0.1")
        self.assertEqual(i.bind_address, "127.0.0.1")
        i = UdpInterface(
            "10.10.10.1",
            "8888",
            "8889",
            "8890",
            "10.10.10.2",
            "64",
            "5",
            "5",
            "10.10.10.3",
        )
        self.assertEqual(i.hostname, "10.10.10.1")
        self.assertEqual(i.interface_address, "10.10.10.2")
        self.assertEqual(i.bind_address, "10.10.10.3")

    def test_is_not_writeable_if_no_write_port_given(self):
        i = UdpInterface("localhost", "None", "8889")
        self.assertEqual(i.name, "UdpInterface")
        self.assertFalse(i.write_allowed)
        self.assertFalse(i.write_raw_allowed)
        self.assertTrue(i.read_allowed)

    def test_is_not_readable_if_no_read_port_given(self):
        i = UdpInterface("localhost", "8888", "None")
        self.assertEqual(i.name, "UdpInterface")
        self.assertTrue(i.write_allowed)
        self.assertTrue(i.write_raw_allowed)
        self.assertFalse(i.read_allowed)

    def test_creates_a_udpwritesocket_and_udpreadsocket_if_both_given(self):
        i = UdpInterface("localhost", "8888", "8889")
        self.assertFalse(i.connected())
        i.connect()
        self.assertTrue(i.connected())
        self.assertIsNotNone(i.write_socket)
        self.assertIsNotNone(i.read_socket)
        i.disconnect()
        self.assertFalse(i.connected())
        self.assertIsNone(i.write_socket)
        self.assertIsNone(i.read_socket)

    def test_creates_a_udpwritesocket_if_write_port_given(self):
        i = UdpInterface("localhost", "8888", "None")
        self.assertFalse(i.connected())
        i.connect()
        self.assertTrue(i.connected())
        self.assertIsNotNone(i.write_socket)
        self.assertIsNone(i.read_socket)
        i.disconnect()
        self.assertFalse(i.connected())
        self.assertIsNone(i.write_socket)
        self.assertIsNone(i.read_socket)

    def test_creates_a_udpreadsocket_if_read_port_given(self):
        i = UdpInterface("localhost", "None", "8889")
        self.assertFalse(i.connected())
        i.connect()
        self.assertTrue(i.connected())
        self.assertIsNone(i.write_socket)
        self.assertIsNotNone(i.read_socket)
        i.disconnect()
        self.assertFalse(i.connected())
        self.assertIsNone(i.write_socket)
        self.assertIsNone(i.read_socket)

    def test_creates_one_socket_if_read_port_write_src_port(self):
        i = UdpInterface("localhost", "8888", "8889", "8889")
        self.assertFalse(i.connected())
        i.connect()
        self.assertTrue(i.connected())
        self.assertIsNotNone(i.write_socket)
        self.assertIsNotNone(i.read_socket)
        self.assertEqual(i.read_socket, i.write_socket)
        i.disconnect()
        self.assertFalse(i.connected())
        self.assertIsNone(i.write_socket)
        self.assertIsNone(i.read_socket)

    @patch("socket.socket")
    def test_stops_the_read_thread_if_there_is_an_ioerror(self, mock_socket):
        sock = mock_socket.return_value
        sock.recvfrom.side_effect = socket.error(socket.EWOULDBLOCK)
        i = UdpInterface("localhost", "None", "8889")
        i.connect()
        thread = threading.Thread(target=i.read)
        thread.start()
        time.sleep(0.1)
        self.assertFalse(thread.is_alive())

    def test_counts_the_packets_received(self):
        write = UdpWriteSocket("127.0.0.1", 8889)
        i = UdpInterface("127.0.0.1", "None", "8889")
        i.connect()
        self.assertEqual(i.read_count, 0)
        self.assertEqual(i.bytes_read, 0)
        self.packet = None

        def do_read():
            self.packet = i.read()

        t = threading.Thread(target=do_read)
        t.start()
        write.write(b"\x00\x01\x02\x03")
        t.join()
        self.assertEqual(i.read_count, 1)
        self.assertEqual(i.bytes_read, 4)
        self.assertEqual(self.packet.buffer, b"\x00\x01\x02\x03")
        t = threading.Thread(target=do_read)
        t.start()
        write.write(b"\x04\x05\x06\x07")
        t.join()
        self.assertEqual(i.read_count, 2)
        self.assertEqual(i.bytes_read, 8)
        self.assertEqual(self.packet.buffer, b"\x04\x05\x06\x07")
        i.disconnect()
        close_socket(write)

    @patch.object(BucketUtilities, "move_log_file_to_bucket_thread")
    def test_logs_the_raw_data(self, move_log_file):
        move_log_file.return_value = None

        write = UdpWriteSocket("127.0.0.1", 8889)
        i = UdpInterface("127.0.0.1", "None", "8889")
        i.connect()
        i.start_raw_logging()
        self.assertTrue(i.stream_log_pair.read_log.logging_enabled)
        t = threading.Thread(target=i.read)
        t.start()
        write.write(b"\x00\x01\x02\x03")
        t.join()
        filename = i.stream_log_pair.read_log.filename
        i.stop_raw_logging()
        self.assertFalse(i.stream_log_pair.read_log.logging_enabled)
        data = None
        with open(filename, "rb") as file:
            data = file.read()
        self.assertEqual(data, b"\x00\x01\x02\x03")
        i.disconnect()
        close_socket(write)
        i.stream_log_pair.shutdown()
        time.sleep(0.01)

    def test_write_complains_if_write_dest_not_given(self):
        i = UdpInterface("localhost", "None", "8889")
        with self.assertRaisesRegex(RuntimeError, "not connected for write"):
            i.write(Packet("", ""))
        with self.assertRaisesRegex(RuntimeError, "not connected for write"):
            i.write_raw(Packet("", ""))

    def test_write_complains_if_the_server_is_not_connected(self):
        i = UdpInterface("localhost", "8888", "None")
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.write(Packet("", ""))
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.write_raw(Packet("", ""))

    def test_write_counts_the_packets_and_bytes_written(self):
        read = UdpReadSocket(8888, "localhost")
        i = UdpInterface("localhost", "8888", "None")
        i.connect()
        self.assertEqual(i.write_count, 0)
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        i.write(pkt)
        data = read.read()
        self.assertEqual(i.write_count, 1)
        self.assertEqual(i.bytes_written, 4)
        self.assertEqual(data, b"\x00\x01\x02\x03")

        i.write_raw(b"\x04\x05\x06\x07")
        data = read.read()
        self.assertEqual(i.write_count, 1)  # No change
        self.assertEqual(i.bytes_written, 8)
        self.assertEqual(data, b"\x04\x05\x06\x07")

        i.disconnect()
        close_socket(read)

    @patch.object(BucketUtilities, "move_log_file_to_bucket_thread")
    def test_write_logs_the_raw_data(self, move_log_file):
        move_log_file.return_value = None
        read = UdpReadSocket(8888, "localhost")
        i = UdpInterface("localhost", "8888", "None")
        i.connect()
        i.start_raw_logging()
        self.assertTrue(i.stream_log_pair.write_log.logging_enabled)
        pkt = Packet("tgt", "pkt")
        pkt.buffer = b"\x00\x01\x02\x03"
        i.write(pkt)
        i.write_raw(b"\x04\x05\x06\x07")
        _ = read.read()
        filename = i.stream_log_pair.write_log.filename
        i.stop_raw_logging()
        self.assertFalse(i.stream_log_pair.write_log.logging_enabled)
        data = None
        with open(filename, "rb") as file:
            data = file.read()
        self.assertEqual(data, b"\x00\x01\x02\x03\x04\x05\x06\x07")
        i.disconnect()
        close_socket(read)
        i.stream_log_pair.shutdown()
        time.sleep(0.01)
