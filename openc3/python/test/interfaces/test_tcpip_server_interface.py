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
import socket
import threading
import unittest
from openc3.interfaces.tcpip_server_interface import TcpipServerInterface
from openc3.packets.packet import Packet
from test.test_helper import mock_redis


class TestTcpipServerInterface(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_initializes_the_instance_variables(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        self.assertEqual(i.name, "TcpipServerInterface")

    def test_is_not_writeable_if_no_write_port_given(self):
        i = TcpipServerInterface("None", "8889", "None", "5", "burst")
        self.assertFalse(i.write_allowed)
        self.assertFalse(i.write_raw_allowed)
        self.assertTrue(i.read_allowed)
        i._connected = True
        with self.assertRaisesRegex(RuntimeError, "Interface not writeable"):
            i.write(Packet("", ""))

    def test_is_not_readable_if_no_read_port_given(self):
        i = TcpipServerInterface("8888", "None", "5", "None", "burst")
        self.assertTrue(i.write_allowed)
        self.assertTrue(i.write_raw_allowed)
        self.assertFalse(i.read_allowed)
        i._connected = True
        with self.assertRaisesRegex(RuntimeError, "Interface not readable"):
            i.read()

    def test_connection_string(self):
        i = TcpipServerInterface("8889", "8889", "None", "5", "burst")
        self.assertEqual(i.connection_string(), "listening on 0.0.0.0:8889 (R/W)")

        i = TcpipServerInterface("8889", "8890", "None", "5", "burst")
        self.assertEqual(
            i.connection_string(),
            "listening on 0.0.0.0:8889 (write) 0.0.0.0:8890 (read)",
        )

        i = TcpipServerInterface("8889", "None", "None", "5", "burst")
        self.assertEqual(i.connection_string(), "listening on 0.0.0.0:8889 (write)")

        i = TcpipServerInterface("None", "8889", "None", "5", "burst")
        self.assertEqual(i.connection_string(), "listening on 0.0.0.0:8889 (read)")

    def test_read_raises_if_not_connected(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i._connected = False
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.read()

    def test_read_counts_the_packets_received(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i._connected = True
        i.read_queue.put(Packet(None, None))
        i.read_queue.put(Packet(None, None))

        self.assertEqual(i.read_count, 0)
        i.read()
        self.assertEqual(i.read_count, 1)
        i.read()
        self.assertEqual(i.read_count, 2)

    def test_read_does_not_count_none_packets(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i._connected = True
        i.read_queue.put(None)
        i.read_queue.put(None)

        self.assertEqual(i.read_count, 0)
        i.read()
        self.assertEqual(i.read_count, 0)
        i.read()
        self.assertEqual(i.read_count, 0)

    def test_write_complains_if_the_server_is_not_connected(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i._connected = False
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.write(Packet("", ""))

    def test_counts_the_packets_written(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i._connected = True
        self.assertEqual(i.write_count, 0)
        i.write(Packet("", ""))
        self.assertEqual(i.write_count, 1)
        i.write(Packet("", ""))
        self.assertEqual(i.write_count, 2)

    def test_write_raw_complains_if_the_server_is_not_connected(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i._connected = False
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.write_raw(Packet("", ""))

    def test_sets_the_listen_address_for_the_tcpip_server(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.set_option("LISTEN_ADDRESS", ["127.0.0.1"])
        self.assertEqual(i.listen_address, "127.0.0.1")

    def test_server_read_only(self):
        i = TcpipServerInterface(None, "8889", None, "5", "burst")
        i.connect()

        # Create a TCP/IP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # Connect the socket to the port where the server is listening
        server_address = ("localhost", 8889)
        sock.connect(server_address)
        buffer = b"\x00\x01\x02\x03"
        sock.sendall(buffer)
        time.sleep(0.01)  # Allow the data to be processed (thread switch)
        self.assertEqual(i.read_queue_size(), 1)
        self.assertEqual(i.write_queue_size(), 0)
        packet = i.read()
        self.assertEqual(packet.buffer, buffer)
        self.assertEqual(i.num_clients(), 1)
        sock.close()
        i.disconnect()

    def test_server_write_only(self):
        i = TcpipServerInterface("8888", None, "5", None, "burst")
        i.connect()

        def send():
            time.sleep(0.01)
            pkt = Packet("TGT", "PKT")
            pkt.buffer = b"\x00\x01"
            i.write(pkt)
            time.sleep(0.2)
            i.write_raw(b"\x02\x03\x04\x05")

        # Create a TCP/IP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # Connect the socket to the port where the server is listening
        server_address = ("localhost", 8888)
        sock.connect(server_address)

        thread = threading.Thread(target=send)
        thread.start()

        time.sleep(0.1)  # Allow the data to be processed (thread switch)
        data = sock.recv(4096)
        self.assertEqual(data, b"\x00\x01")
        data = sock.recv(4096)
        self.assertEqual(data, b"\x02\x03\x04\x05")
        self.assertEqual(i.num_clients(), 1)
        sock.close()
        i.disconnect()

    def test_read_and_write(self):
        i = TcpipServerInterface("8888", "8888", "5", "5", "burst")
        i.connect()

        def send():
            time.sleep(0.01)
            pkt = Packet("TGT", "PKT")
            pkt.buffer = b"\x00\x01"
            i.write(pkt)

        thread = threading.Thread(target=send)
        thread.start()

        # Create a TCP/IP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # Connect the socket to the port where the server is listening
        server_address = ("localhost", 8888)
        sock.connect(server_address)
        time.sleep(0.02)  # Allow the data to be processed (thread switch)
        write_buffer = b"\x06\x07\x08\x09"
        sock.sendall(write_buffer)
        time.sleep(0.01)
        self.assertEqual(i.read_queue_size(), 1)
        self.assertEqual(i.write_queue_size(), 1)
        data = sock.recv(4096)
        self.assertEqual(data, b"\x00\x01")
        packet = i.read()
        self.assertEqual(packet.buffer, write_buffer)
        self.assertEqual(i.num_clients(), 1)
        sock.close()
        i.disconnect()

    def test_multiple_connections(self):
        i = TcpipServerInterface("8888", None, "5", None, "burst")
        i.connect()

        def send():
            time.sleep(0.01)
            i.write_raw(b"\x02\x03\x04\x05")

        # Create a TCP/IP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # Connect the socket to the port where the server is listening
        server_address = ("localhost", 8888)
        sock.connect(server_address)

        # Create a TCP/IP socket
        sock2 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock2.connect(server_address)

        thread = threading.Thread(target=send)
        thread.start()
        time.sleep(0.11)  # Allow the data to be sent
        data = sock.recv(4096)
        self.assertEqual(data, b"\x02\x03\x04\x05")
        data = sock2.recv(4096)
        self.assertEqual(data, b"\x02\x03\x04\x05")
        self.assertEqual(i.num_clients(), 2)

        # Close the first connection
        sock.shutdown(socket.SHUT_RDWR)
        sock.close()

        thread = threading.Thread(target=send)
        thread.start()
        time.sleep(0.11)  # Allow the data to be sent
        data = sock2.recv(4096)
        self.assertEqual(data, b"\x02\x03\x04\x05")
        self.assertEqual(i.num_clients(), 1)

        # Close the second connection
        sock2.shutdown(socket.SHUT_RDWR)
        sock2.close()

        thread = threading.Thread(target=send)
        thread.start()
        time.sleep(0.11)
        self.assertEqual(i.num_clients(), 0)
        i.disconnect()
