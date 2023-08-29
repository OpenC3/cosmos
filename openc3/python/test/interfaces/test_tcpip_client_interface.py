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

import unittest
from unittest.mock import *
from test.test_helper import *
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

    # @patch("socket.socket", return_value=Mock())
    # def test_returns_true_once_connect_succeeds(self, mock_socket):
    #     i = TcpipClientInterface("localhost", "8888", "8889", "5", "5", "burst")
    #     self.assertFalse(i.connected())
    #     i.connect()
    #     self.assertTrue(i.connected())
    #     i.disconnect()
