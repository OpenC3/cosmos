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

import struct
import select
import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.io.udp_sockets import *


class TestUdpWriteSocket(unittest.TestCase):
    def test_creates_a_socket(self):
        udp = UdpWriteSocket("127.0.0.1", 8888)
        self.assertEqual(udp.getpeername()[0], "127.0.0.1")
        self.assertEqual(udp.getpeername()[1], 8888)
        udp.close()
        udp = UdpWriteSocket("224.0.1.1", 8888, 7888, "127.0.0.1", 3)
        self.assertEqual(udp.getsockname()[1], 7888)
        self.assertEqual(udp.getsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL), 3)
        bytes = struct.pack(
            "<I", udp.getsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF)
        )
        self.assertEqual(socket.inet_ntoa(bytes), "127.0.0.1")
        udp.close()

    def test_writes_data(self):
        udp_read = UdpReadSocket(8888)
        udp_write = UdpWriteSocket("127.0.0.1", 8888)
        udp_write.write(b"\x01\x02", 2.0)
        self.assertEqual(udp_read.read(), b"\x01\x02")
        udp_read.close()
        udp_write.close()

    @patch.object(select, "select")
    @patch("socket.socket")
    def test_handles_timeouts(self, mock_socket, mock_select):
        sock = mock_socket.return_value
        sock.send.side_effect = socket.error(socket.EWOULDBLOCK)
        mock_select.return_value = ([], [], [])
        udp_write = UdpWriteSocket("127.0.0.1", 8888)
        with self.assertRaises(TimeoutError):
            udp_write.write(b"\x01\x02", 2.0)
        udp_write.close()

    def test_determines_if_a_host_is_multicast(self):
        self.assertFalse(UdpWriteSocket.multicast(None, 80))
        self.assertFalse(UdpWriteSocket.multicast("224.0.1.1", None))
        self.assertFalse(UdpWriteSocket.multicast("127.0.0.1", 80))
        self.assertTrue(UdpWriteSocket.multicast("224.0.1.1", 80))


class TestUdpReadSocket(unittest.TestCase):
    def test_creates_a_socket(self):
        udp = UdpReadSocket(8888)
        self.assertEqual(udp.getsockname()[0], "0.0.0.0")
        self.assertEqual(udp.getsockname()[1], 8888)
        udp.close()
        udp = UdpReadSocket(8888, "224.0.1.1")
        bytes = struct.pack(
            "<I", udp.getsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF)
        )
        self.assertEqual(socket.inet_ntoa(bytes), "0.0.0.0")
        udp.close()

    def test_reads_data(self):
        udp_read = UdpReadSocket(8888)
        udp_write = UdpWriteSocket("127.0.0.1", 8888)
        udp_write.write(b"\x01\x02", 2.0)
        self.assertEqual(udp_read.read(), b"\x01\x02")
        udp_read.close()
        udp_write.close()

    @patch.object(select, "select")
    @patch("socket.socket")
    def test_handles_timeouts(self, mock_socket, mock_select):
        sock = mock_socket.return_value
        sock.recvfrom.side_effect = socket.error(socket.EWOULDBLOCK)
        mock_select.return_value = ([], [], [])
        udp_read = UdpReadSocket(8889)
        with self.assertRaises(TimeoutError):
            udp_read.read(2.0)
        udp_read.close()


class TestUdpReadWriteSocket(unittest.TestCase):
    def test_creates_a_socket(self):
        udp = UdpReadWriteSocket(8888)
        self.assertEqual(udp.getsockname()[0], "0.0.0.0")
        self.assertEqual(udp.getsockname()[1], 8888)
        udp.close()
        udp = UdpReadWriteSocket(8888, "0.0.0.0", 1234, "224.0.1.1")
        self.assertEqual(udp.getpeername()[0], "224.0.1.1")
        self.assertEqual(udp.getpeername()[1], 1234)
        bytes = struct.pack(
            "<I", udp.getsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF)
        )
        self.assertEqual(udp.getsockname()[1], 8888)
        self.assertEqual(socket.inet_ntoa(bytes), "0.0.0.0")
        udp.close()

    def test_reads_data(self):
        udp_read = UdpReadWriteSocket(8888)
        udp_write = UdpWriteSocket("127.0.0.1", 8888)
        udp_write.write(b"\x01\x02", 2.0)
        self.assertEqual(udp_read.read(), b"\x01\x02")
        udp_read.close()
        udp_write.close()

    def test_writes_data(self):
        udp_read = UdpReadSocket(8888)
        udp_write = UdpReadWriteSocket(0, "0.0.0.0", 8888, "127.0.0.1")
        udp_write.write(b"\x01\x02", 2.0)
        self.assertEqual(udp_read.read(), b"\x01\x02")
        udp_read.close()
        udp_write.close()
