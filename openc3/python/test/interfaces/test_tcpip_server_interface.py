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
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.interfaces.tcpip_server_interface import TcpipServerInterface
from openc3.packets.packet import Packet


class TestTcpipServerInterface(unittest.TestCase):
    def test_initializes_the_instance_variables(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        self.assertEqual(i.name, "TcpipServerInterface")

    def test_is_not_writeable_if_no_write_port_given(self):
        i = TcpipServerInterface("None", "8889", "None", "5", "burst")
        self.assertFalse(i.write_allowed)
        self.assertFalse(i.write_raw_allowed)
        self.assertTrue(i.read_allowed)
        i.connected = True
        with self.assertRaisesRegex(RuntimeError, "Interface not writeable"):
            i.write(Packet("", ""))

    def test_is_not_readable_if_no_read_port_given(self):
        i = TcpipServerInterface("8888", "None", "5", "None", "burst")
        self.assertTrue(i.write_allowed)
        self.assertTrue(i.write_raw_allowed)
        self.assertFalse(i.read_allowed)
        i.connected = True
        with self.assertRaisesRegex(RuntimeError, "Interface not readable"):
            i.read()

    def test_read_raises_if_not_connected(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.connected = False
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.read()

    def test_read_counts_the_packets_received(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.connected = True
        i.read_queue.put(Packet(None, None))
        i.read_queue.put(Packet(None, None))

        self.assertEqual(i.read_count, 0)
        i.read()
        self.assertEqual(i.read_count, 1)
        i.read()
        self.assertEqual(i.read_count, 2)
        i.read()
        self.assertEqual(i.read_count, 2)

    def test_read_does_not_count_none_packets(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.connected = True
        i.read_queue.put(None)
        i.read_queue.put(None)

        self.assertEqual(i.read_count, 0)
        i.read()
        self.assertEqual(i.read_count, 0)
        i.read()
        self.assertEqual(i.read_count, 0)

    def test_write_complains_if_the_server_is_not_connected(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.connected = False
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.write(Packet("", ""))

    def test_counts_the_packets_written(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.connected = True
        self.assertEqual(i.write_count, 0)
        i.write(Packet("", ""))
        self.assertEqual(i.write_count, 1)
        i.write(Packet("", ""))
        self.assertEqual(i.write_count, 2)

    def test_write_raw_complains_if_the_server_is_not_connected(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.connected = False
        with self.assertRaisesRegex(RuntimeError, "Interface not connected"):
            i.write_raw(Packet("", ""))

    def test_write_raw_counts_the_bytes_written(self):
        i = TcpipServerInterface("8888", "8889", "5", "5", "burst")
        i.connect()

        # Create a TCP/IP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # Connect the socket to the port where the server is listening
        server_address = ("localhost", 8889)
        sock.connect(server_address)
        buffer = b"\x00\x01\x02\x03"
        sock.sendall(buffer)
        time.sleep(0.01)  # Allow the data to be processed (thread switch)
        packet = i.read()
        self.assertEqual(packet.buffer, buffer)
        sock.close()
        i.disconnect()


# class SetOption(unittest.TestCase):
#     def test_sets_the_listen_address_for_the_tcpip_server(self):
#         i = TcpipServerInterface('8888', '8889', '5', '5', 'burst')
#         i.set_option('LISTEN_ADDRESS', ['127.0.0.1'])
#         self.assertEqual(i.instance_variable_get(:self.listen_address),  '127.0.0.1')
