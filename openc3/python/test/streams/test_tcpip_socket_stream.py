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
from openc3.streams.tcpip_socket_stream import TcpipSocketStream
from openc3.top_level import close_socket


class TestTcpipSocketStream(unittest.TestCase):
    def test_is_not_be_connected_when_initialized(self):
        ss = TcpipSocketStream(None, None, 10.0, None)
        self.assertFalse(ss.connected)

    def test_warns_if_the_write_timeout_is_None(self):
        for stdout in capture_io():
            TcpipSocketStream(8888, 8888, None, None)
            self.assertIn(
                "Warning: To avoid interface lock, write_timeout can not be None. Setting to 10 seconds.",
                stdout.getvalue(),
            )

    def test_raises_an_error_if_no_read_socket_given(self):
        write_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        ss = TcpipSocketStream(write_socket, None, 10.0, None)
        ss.connect()
        with self.assertRaisesRegex(
            RuntimeError,
            "Attempt to read from write only stream",
        ):
            ss.read()
        ss.disconnect()

    def test_calls_read_nonblock_from_the_socket(self):
        class MyTCPHandler(socketserver.BaseRequestHandler):
            def handle(self):
                self.request.send(b"test")

        server = socketserver.TCPServer(("localhost", 2000), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        rs = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        rs.connect(("localhost", 2000))
        ss = TcpipSocketStream(None, rs, 10.0, None)
        self.assertEqual(ss.read(), b"test")
        close_socket(rs)
        ss.disconnect()
        server.server_close()
        time.sleep(0.1)

    #     def test_handles_socket_timeouts(self):
    #         server = TCPServer(2000) # Server bound to port 2000
    #         thread = Thread() do
    #           client = server.accept # Wait for a client to connect
    #           sleep 0.2
    #           client.close
    #         socket = TCPSocket('127.0.0.1', 2000)
    #         ss = TcpipSocketStream(None, socket, 10.0, 0.1)
    #         { ss.read }.to raise_error(Timeout='E'rror)
    #         thread.join
    #         sleep 0.2
    #         OpenC3.close_socket(socket)
    #         OpenC3.close_socket(server)
    #         ss.disconnect
    #         sleep 0.1

    def test_handles_socket_connection_reset_exceptions(self):
        class MyTCPHandler(socketserver.BaseRequestHandler):
            def handle(self):
                self.request.send(b"test")

        server = socketserver.TCPServer(("localhost", 2001), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        rs = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        rs.connect(("localhost", 2001))
        ss = TcpipSocketStream(None, rs, 10.0, None)
        close_socket(rs)
        self.assertEqual(ss.read(), "")
        server.server_close()
        ss.disconnect()
        time.sleep(0.1)

    def test_raises_an_error_if_no_write_port_given(self):
        read_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        ss = TcpipSocketStream(None, read_socket, 10.0, None)
        ss.connect()
        with self.assertRaisesRegex(
            RuntimeError,
            "Attempt to write to read only stream",
        ):
            ss.write(b"test")
        ss.disconnect()
        time.sleep(0.1)

    #     def test_calls_write_from_the_driver(self):
    #         write = double("write_socket")
    #         # Simulate only writing two bytes at a time
    #         expect(write).to receive(:write_nonblock).twice.and_return(2)
    #         ss = TcpipSocketStream(write, None, 10.0, None)
    #         ss.connect
    #         ss.write('test')
    #         ss.disconnect

    #     def test_handles_socket_blocking_exceptions(self):
    #         write = double("write_socket")
    #         allow(write).to receive(:write_nonblock) do
    #           match $index:
    #           case 1:
    #             $index += 1
    #             raise Errno='EWOULDBLOCK'
    #           case 2:
    #             4
    #         expect(IO).to receive(:fast_select).at_least(:once).and_return([])
    #         $index = 1
    #         ss = TcpipSocketStream(write, None, 10.0, None)
    #         ss.connect
    #         ss.write('test')
    #         ss.disconnect

    #     def test_handles_socket_timeouts(self):
    #         write = double("write_socket")
    #         allow(write).to receive(:write_nonblock).and_raise(Errno='EWOULDBLOCK')
    #         expect(IO).to receive(:fast_select).at_least(:once).and_return(None)
    #         ss = TcpipSocketStream(write, None, 10.0, None)
    #         ss.connect
    #         { ss.write('test') }.to raise_error(Timeout='E'rror)
    #         ss.disconnect

    def test_closes_the_write_socket(self):
        write = Mock()
        ss = TcpipSocketStream(write, None, 10.0, None)
        ss.connect()
        self.assertTrue(ss.connected)
        ss.disconnect()
        self.assertFalse(ss.connected)
        write.close.assert_called_once()

    def test_closes_the_read_socket(self):
        read = Mock()
        ss = TcpipSocketStream(None, read, 10.0, None)
        ss.connect()
        self.assertTrue(ss.connected)
        ss.disconnect()
        self.assertFalse(ss.connected)
        read.close.assert_called_once()

    def test_does_not_close_the_socket_twice(self):
        socket = Mock()
        ss = TcpipSocketStream(socket, socket, 10.0, None)
        ss.connect()
        self.assertTrue(ss.connected)
        ss.disconnect()
        self.assertFalse(ss.connected)
        ss.disconnect()
        self.assertFalse(ss.connected)
        socket.close.assert_called()
