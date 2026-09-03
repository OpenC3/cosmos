# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import errno
import socket
import socketserver
import threading
import time
import unittest
from unittest.mock import Mock, patch

from openc3.streams.tcpip_socket_stream import TcpipSocketStream
from openc3.top_level import close_socket
from test.test_helper import capture_io, mock_redis


class ReusableTCPServer(socketserver.TCPServer):
    # Avoid "Address already in use" when a previous test left the port in TIME_WAIT
    allow_reuse_address = True


class TestTcpipSocketStream(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_is_not_be_connected_when_initialized(self):
        ss = TcpipSocketStream(None, None, 10.0, None)
        self.assertFalse(ss.connected())

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
                time.sleep(0.1)
                self.request.send(b"test")
                self.request.close()

        server = ReusableTCPServer(("localhost", 20000), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        rs = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        rs.connect(("localhost", 20000))
        ss = TcpipSocketStream(None, rs, 10.0, None)
        self.assertEqual(ss.read(), b"test")
        close_socket(rs)
        ss.disconnect()
        server.server_close()
        time.sleep(0.1)

    def test_handles_socket_read_timeouts(self):
        # Regression test for read_timeout being ignored on a socket which stays
        # open but stops sending data. select returns ([], [], []) on timeout.
        read = Mock()
        error = OSError()
        error.errno = errno.EWOULDBLOCK
        read.recv.side_effect = error
        ss = TcpipSocketStream(None, read, 10.0, 0.1)
        ss.connect()
        with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
            mock_select.return_value = ([], [], [])
            with self.assertRaisesRegex(TimeoutError, "Read Timeout"):
                ss.read()
        ss.disconnect()

    def test_retries_the_read_when_the_socket_becomes_readable(self):
        read = Mock()
        error = OSError()
        error.errno = errno.EWOULDBLOCK
        # Raise EWOULDBLOCK on the first recv, return data on the second
        read.recv.side_effect = [error, b"test"]
        ss = TcpipSocketStream(None, read, 10.0, 0.1)
        ss.connect()
        with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
            mock_select.return_value = ([read], [], [])
            self.assertEqual(ss.read(), b"test")
        self.assertEqual(read.recv.call_count, 2)
        ss.disconnect()

    def test_returns_empty_data_when_disconnected_while_reading(self):
        read = Mock()
        error = OSError()
        error.errno = errno.EWOULDBLOCK
        read.recv.side_effect = error
        ss = TcpipSocketStream(None, read, 10.0, None)
        ss.connect()
        with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
            mock_select.return_value = ([ss.pipe_reader], [], [])
            self.assertEqual(ss.read(), "")
        ss.disconnect()

    def test_returns_empty_data_when_select_sees_a_closed_socket(self):
        read = Mock()
        error = OSError()
        error.errno = errno.EWOULDBLOCK
        read.recv.side_effect = error
        ss = TcpipSocketStream(None, read, 10.0, None)
        ss.connect()
        for select_errno in (errno.EBADF, errno.ENOTSOCK):
            select_error = OSError()
            select_error.errno = select_errno
            with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
                mock_select.side_effect = select_error
                self.assertEqual(ss.read(), "")
        # Python sets fileno() to -1 once the socket is closed
        with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
            mock_select.side_effect = ValueError("file descriptor cannot be a negative integer (-1)")
            self.assertEqual(ss.read(), "")
        ss.disconnect()

    def test_reraises_unexpected_select_errors(self):
        # An unexpected system failure must not be hidden behind a clean EOF
        read = Mock()
        error = OSError()
        error.errno = errno.EWOULDBLOCK
        read.recv.side_effect = error
        ss = TcpipSocketStream(None, read, 10.0, None)
        ss.connect()
        select_error = OSError()
        select_error.errno = errno.ENOMEM
        with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
            mock_select.side_effect = select_error
            with self.assertRaises(OSError) as context:
                ss.read()
            self.assertEqual(context.exception.errno, errno.ENOMEM)
        ss.disconnect()

    def test_times_out_reading_from_a_silent_socket(self):
        class MyTCPHandler(socketserver.BaseRequestHandler):
            def handle(self):
                # Accept the connection and then send nothing, keeping it open
                time.sleep(0.5)

        server = ReusableTCPServer(("localhost", 20004), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        rs = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        rs.connect(("localhost", 20004))
        # Match how the interfaces create their sockets. MSG_DONTWAIT does not
        # exist on Windows so a blocking socket would sit in recv instead of
        # returning EWOULDBLOCK and reaching the select timeout.
        rs.setblocking(False)
        ss = TcpipSocketStream(None, rs, 10.0, 0.1)
        ss.connect()
        with self.assertRaisesRegex(TimeoutError, "Read Timeout"):
            ss.read()
        ss.disconnect()
        server.server_close()
        time.sleep(0.1)

    def test_handles_socket_connection_reset_exceptions(self):
        class MyTCPHandler(socketserver.BaseRequestHandler):
            def handle(self):
                time.sleep(0.2)
                self.request.close()

        server = ReusableTCPServer(("localhost", 20002), MyTCPHandler)
        threading.Thread(target=server.handle_request).start()
        rs = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0)
        rs.connect(("localhost", 20002))
        ss = TcpipSocketStream(None, rs, 10.0, 5.0)
        time.sleep(0.1)  # allow the server thread to accept
        # close the socket before trying to read from it
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

    def test_raises_immediately_on_non_eagain_socket_error_in_write(self):
        # Regression test for interface lock-up when write raises an errno
        # other than EAGAIN/EWOULDBLOCK (e.g. ECONNRESET, EPIPE).
        write = Mock()
        error = OSError()
        error.errno = errno.ECONNRESET
        write.send.side_effect = error
        ss = TcpipSocketStream(write, None, 10.0, None)
        ss.connect()
        with self.assertRaises(OSError):
            ss.write(b"test")
        ss.disconnect()

    def test_calls_write_from_the_driver(self):
        write = Mock()
        # Simulate only writing two bytes at a time
        write.send.side_effect = [2, 2]
        ss = TcpipSocketStream(write, None, 10.0, None)
        ss.connect()
        ss.write(b"test")
        self.assertEqual(write.send.call_count, 2)
        ss.disconnect()

    def test_handles_socket_blocking_exceptions(self):
        write = Mock()
        error = OSError()
        error.errno = errno.EWOULDBLOCK
        # Raise EWOULDBLOCK on first send, succeed on second
        write.send.side_effect = [error, 4]
        ss = TcpipSocketStream(write, None, 10.0, None)
        ss.connect()
        with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
            mock_select.return_value = ([], [write], [])
            ss.write(b"test")
        ss.disconnect()

    def test_handles_socket_write_timeouts(self):
        write = Mock()
        error = OSError()
        error.errno = errno.EWOULDBLOCK
        write.send.side_effect = error
        ss = TcpipSocketStream(write, None, 10.0, None)
        ss.connect()
        with patch("openc3.streams.tcpip_socket_stream.select.select") as mock_select:
            mock_select.return_value = ([], [], [])
            with self.assertRaisesRegex(TimeoutError, "Write Timeout"):
                ss.write(b"test")
        ss.disconnect()

    def test_closes_the_write_socket(self):
        write = Mock()
        ss = TcpipSocketStream(write, None, 10.0, None)
        ss.connect()
        self.assertTrue(ss.connected())
        ss.disconnect()
        self.assertFalse(ss.connected())
        write.close.assert_called_once()

    def test_closes_the_read_socket(self):
        read = Mock()
        ss = TcpipSocketStream(None, read, 10.0, None)
        ss.connect()
        self.assertTrue(ss.connected())
        ss.disconnect()
        self.assertFalse(ss.connected())
        read.close.assert_called_once()

    def test_does_not_close_the_socket_twice(self):
        socket = Mock()
        ss = TcpipSocketStream(socket, socket, 10.0, None)
        ss.connect()
        self.assertTrue(ss.connected())
        ss.disconnect()
        self.assertFalse(ss.connected())
        ss.disconnect()
        self.assertFalse(ss.connected())
        socket.close.assert_called()
