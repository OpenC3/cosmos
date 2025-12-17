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

import unittest
from openc3.interfaces.tcpip_client_interface import TcpipClientInterface


class TestTcpipClientInterface(unittest.TestCase):
    def test_is_not_writeable_if_no_write_port_given(self):
        i = TcpipClientInterface("localhost", "None", "8889", "None", "5", "burst")
        self.assertEqual(i.name, "TcpipClientInterface")
        self.assertFalse(i.write_allowed)
        self.assertFalse(i.write_raw_allowed)
        self.assertTrue(i.read_allowed)

    def test_is_not_readable_if_no_read_port_given(self):
        i = TcpipClientInterface("localhost", "8888", "None", "5", "None", "burst")
        self.assertEqual(i.name, "TcpipClientInterface")
        self.assertTrue(i.write_allowed)
        self.assertTrue(i.write_raw_allowed)
        self.assertFalse(i.read_allowed)

    def test_raises_a_timeout_when_unable_to_connect(self):
        i = TcpipClientInterface("localhost", "8888", "8889", "5", "5", "burst")
        self.assertFalse(i.connected())
        with self.assertRaises(
            ConnectionRefusedError,
        ):
            i.connect()
        # ResourceWarning: unclosed <socket.socket

    def test_initially_returns_false(self):
        i = TcpipClientInterface("localhost", "8888", "8889", "5", "5", "burst")
        self.assertFalse(i.connected())

    def test_connection_string(self):
        i = TcpipClientInterface("localhost", "8889", "8889", "5", "5", "burst")
        self.assertEqual(i.connection_string(), "localhost:8889 (R/W)")

        i = TcpipClientInterface("localhost", "8889", "8890", "None", "5", "burst")
        self.assertEqual(i.connection_string(), "localhost:8889 (write) localhost:8890 (read)")

        i = TcpipClientInterface("localhost", "8889", "None", "None", "5", "burst")
        self.assertEqual(i.connection_string(), "localhost:8889 (write)")

        i = TcpipClientInterface("localhost", "None", "8889", "None", "5", "burst")
        self.assertEqual(i.connection_string(), "localhost:8889 (read)")

    # @patch("socket.socket", return_value=Mock())
    # def test_returns_true_once_connect_succeeds(self, mock_socket):
    #     i = TcpipClientInterface("localhost", "8888", "8889", "5", "5", "burst")
    #     self.assertFalse(i.connected())
    #     i.connect()
    #     self.assertTrue(i.connected())
    #     i.disconnect()

    def test_details(self):
        i = TcpipClientInterface("192.168.1.100", "8888", "8889", "10.0", "15.0", "burst")
        details = i.details()

        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check that it includes the expected keys specific to TcpipClientInterface
        self.assertIn('hostname', details)
        self.assertIn('write_port', details)
        self.assertIn('read_port', details)
        self.assertIn('write_timeout', details)
        self.assertIn('read_timeout', details)

        # Verify the specific values are correct
        self.assertEqual(details['hostname'], "192.168.1.100")
        self.assertEqual(details['write_port'], 8888)
        self.assertEqual(details['read_port'], 8889)
        self.assertEqual(details['write_timeout'], 10.0)
        self.assertEqual(details['read_timeout'], 15.0)

    def test_details_with_none_ports(self):
        i = TcpipClientInterface("localhost", "None", "8889", "5", "None", "burst")
        details = i.details()

        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check None values are preserved
        self.assertEqual(details['hostname'], "localhost")
        self.assertIsNone(details['write_port'])
        self.assertEqual(details['read_port'], 8889)
        self.assertEqual(details['write_timeout'], 5.0)
        self.assertIsNone(details['read_timeout'])
