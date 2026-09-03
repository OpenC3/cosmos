# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import socket
import threading
import time
import unittest
from unittest.mock import patch

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

    def test_connection_string(self):
        i = UdpInterface("123.4.5.6", "8888", "8889", "8890", "456.7.8.9", "64", "5", "5", "1.2.3.4")
        self.assertEqual(
            i.connection_string(),
            "123.4.5.6:8888 (write dest port) 8890 (write src port) 1.2.3.4:8889 (read) 456.7.8.9 (interface addr) 1.2.3.4 (bind addr)",
        )

        i = UdpInterface("localhost", "None", "8889")
        self.assertEqual(i.connection_string(), "0.0.0.0:8889 (read)")

        i = UdpInterface("localhost", "8888", "None")
        self.assertEqual(i.connection_string(), "127.0.0.1:8888 (write dest port)")

        # None bind_address means all local addresses
        i = UdpInterface("localhost", "None", "8889", "None", "None", "64", "5", "5", "None")
        self.assertEqual(i.connection_string(), "0.0.0.0:8889 (read)")

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

    def test_shared_socket_receives_from_a_different_source_port(self):
        # Bind the receiving sockets first so the ports are known, then let the
        # sender pick an ephemeral source port
        destination = UdpReadSocket(0)
        self.addCleanup(close_socket, destination)
        dest_port = destination.getsockname()[1]
        shared_port = UdpReadSocket(0)
        read_port = shared_port.getsockname()[1]
        close_socket(shared_port)

        sender = UdpWriteSocket("127.0.0.1", read_port)
        self.addCleanup(close_socket, sender)
        i = UdpInterface("127.0.0.1", dest_port, read_port, read_port)
        self.addCleanup(i.disconnect)
        i.connect()

        sender.write(b"telemetry")
        self.assertEqual(i.read_socket.read(1.0), b"telemetry")
        i.write_socket.write(b"command")
        self.assertEqual(destination.read(1.0), b"command")
        self.assertEqual(i.write_socket.getsockname()[1], read_port)

    def test_clamps_a_ttl_below_one(self):
        i = UdpInterface("localhost", "8888", "None", "None", "None", "0")
        self.assertEqual(i.ttl, 1)

    def test_defaults_a_none_write_timeout_to_ten_seconds(self):
        i = UdpInterface("localhost", "8888", "None", "None", "None", "64", "None")
        self.assertEqual(i.write_timeout, 10.0)

    @patch("socket.socket")
    def test_does_not_join_the_multicast_group_it_writes_to_on_a_shared_socket(self, mock_socket):
        i = UdpInterface("224.0.1.1", 8889, 8889, 8889)
        self.addCleanup(i.disconnect)
        i.connect()
        # Joining the group we transmit to would loop our own commands back as telemetry
        membership = socket.inet_aton("224.0.1.1") + socket.inet_aton("0.0.0.0")
        for call in mock_socket.return_value.setsockopt.call_args_list:
            self.assertNotEqual(call.args, (socket.SOL_IP, socket.IP_ADD_MEMBERSHIP, membership))
        # Multicast writes are still set up
        mock_socket.return_value.setsockopt.assert_any_call(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 128)

    def test_creates_a_read_only_socket_with_an_unresolvable_hostname(self):
        i = UdpInterface("this-host-does-not-exist.invalid", None, 0)
        self.addCleanup(i.disconnect)
        i.connect()
        self.assertIsNotNone(i.read_socket)

    def test_creates_a_read_socket_for_port_zero(self):
        i = UdpInterface("127.0.0.1", None, 0)
        self.addCleanup(i.disconnect)
        i.connect()
        self.assertIsNotNone(i.read_socket)
        self.assertGreater(i.read_socket.getsockname()[1], 0)

    @patch("socket.socket")
    def test_stops_the_read_thread_if_there_is_an_ioerror(self, mock_socket):
        sock = mock_socket.return_value
        sock.recvfrom.side_effect = OSError(socket.EWOULDBLOCK)
        i = UdpInterface("localhost", "None", "8889")
        i.connect()
        thread = threading.Thread(target=i.read)
        thread.start()
        time.sleep(0.001)
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

    def test_details(self):
        i = UdpInterface(
            "192.168.1.100",
            "8888",
            "8889",
            "8890",
            "10.10.10.2",
            "128",
            "10.0",
            "15.0",
            "10.10.10.3",
        )
        details = i.details()

        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check that it includes the expected keys specific to UdpInterface
        self.assertIn("hostname", details)
        self.assertIn("write_dest_port", details)
        self.assertIn("read_port", details)
        self.assertIn("write_src_port", details)
        self.assertIn("interface_address", details)
        self.assertIn("ttl", details)
        self.assertIn("write_timeout", details)
        self.assertIn("read_timeout", details)
        self.assertIn("bind_address", details)

        # Verify the specific values are correct
        self.assertEqual(details["hostname"], "192.168.1.100")
        self.assertEqual(details["write_dest_port"], 8888)
        self.assertEqual(details["read_port"], 8889)
        self.assertEqual(details["write_src_port"], 8890)
        self.assertEqual(details["interface_address"], "10.10.10.2")
        self.assertEqual(details["ttl"], 128)
        self.assertEqual(details["write_timeout"], 10.0)
        self.assertEqual(details["read_timeout"], 15.0)
        self.assertEqual(details["bind_address"], "10.10.10.3")

    def test_details_with_none_values(self):
        i = UdpInterface("localhost", "None", "8889")
        details = i.details()

        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check None and default values are handled correctly
        self.assertEqual(details["hostname"], "127.0.0.1")  # localhost converted
        self.assertIsNone(details["write_dest_port"])
        self.assertEqual(details["read_port"], 8889)
        self.assertIsNone(details["write_src_port"])
        self.assertIsNone(details["interface_address"])
        self.assertEqual(details["ttl"], 128)  # default value
        self.assertEqual(details["write_timeout"], 10.0)  # default value
        self.assertIsNone(details["read_timeout"])
        self.assertEqual(details["bind_address"], "0.0.0.0")  # default value
