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
from unittest.mock import Mock, patch
from test.test_helper import mock_redis, setup_system
from openc3.interfaces.http_server_interface import HttpServerInterface


class TestHttpServerInterface(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_initializes_the_instance_variables(self):
        i = HttpServerInterface(8080)
        self.assertEqual(i.name, "HttpServerInterface")
        self.assertEqual(i.port, 8080)
        self.assertEqual(i.listen_address, "0.0.0.0")

    def test_default_port(self):
        i = HttpServerInterface()
        self.assertEqual(i.port, 80)

    def test_connection_string(self):
        i = HttpServerInterface(8080)
        self.assertEqual(i.connection_string(), "listening on 0.0.0.0:8080")

    def test_connection_string_with_custom_listen_address(self):
        i = HttpServerInterface(8080)
        i.set_option("LISTEN_ADDRESS", ["127.0.0.1"])
        self.assertEqual(i.connection_string(), "listening on 127.0.0.1:8080")

    def test_details(self):
        i = HttpServerInterface(8080)
        details = i.details()

        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check that it includes the expected keys specific to HttpServerInterface
        self.assertIn('listen_address', details)
        self.assertIn('port', details)
        self.assertIn('request_queue_length', details)

        # Verify the specific values are correct
        self.assertEqual(details['listen_address'], "0.0.0.0")
        self.assertEqual(details['port'], 8080)
        self.assertEqual(details['request_queue_length'], 0)  # No server started

    def test_details_with_custom_listen_address(self):
        i = HttpServerInterface(9090)
        i.set_option("LISTEN_ADDRESS", ["192.168.1.100"])
        details = i.details()

        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check values with custom settings
        self.assertEqual(details['listen_address'], "192.168.1.100")
        self.assertEqual(details['port'], 9090)
        self.assertEqual(details['request_queue_length'], 0)

    def test_details_default_port(self):
        i = HttpServerInterface()  # Default port 80
        details = i.details()

        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)

        # Check default port
        self.assertEqual(details['port'], 80)
        self.assertEqual(details['listen_address'], "0.0.0.0")


if __name__ == '__main__':
    unittest.main()