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
import socketserver
import threading
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.streams.tcpip_client_stream import TcpipClientStream


class TestTcpipClientStream(unittest.TestCase):
    def test_complains_if_the_host_is_bad(self):
        with self.assertRaisesRegex(
            RuntimeError,
            "Invalid hostname",
        ):
            TcpipClientStream("asdf", 8888, 8888, 10.0, None)

    def test_uses_the_same_socket_if_read_port_equals_write_port(self):
        class MyTCPHandler(socketserver.BaseRequestHandler):
            def handle(self):
                pass

        server = socketserver.TCPServer(("localhost", 8888), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        time.sleep(0.1)

        ss = TcpipClientStream("localhost", 8888, 8888, 10.0, None)
        ss.write_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        ss.connect()
        self.assertTrue(ss.connected)
        self.assertEqual(ss.read_socket, ss.write_socket)
        ss.disconnect()
        server.server_close()
        time.sleep(0.1)

    def test_creates_the_write_socket(self):
        class MyTCPHandler(socketserver.BaseRequestHandler):
            def handle(self):
                pass

        server = socketserver.TCPServer(("localhost", 8888), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        time.sleep(0.1)

        ss = TcpipClientStream("localhost", 8888, None, 10.0, None)
        ss.write_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        ss.connect()
        self.assertTrue(ss.connected)
        ss.disconnect()
        server.server_close()
        time.sleep(0.1)

    def test_creates_the_read_socket(self):
        class MyTCPHandler(socketserver.BaseRequestHandler):
            def handle(self):
                pass

        server = socketserver.TCPServer(("localhost", 8888), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        time.sleep(0.1)

        ss = TcpipClientStream("localhost", None, 8888, 10.0, None)
        ss.read_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        ss.connect()
        self.assertTrue(ss.connected)
        ss.disconnect()
        server.server_close()
        time.sleep(0.1)
