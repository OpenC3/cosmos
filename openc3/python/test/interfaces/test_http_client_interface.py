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
from openc3.interfaces.http_client_interface import HttpClientInterface


class TestHttpClientInterface(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_initializes_the_instance_variables(self):
        i = HttpClientInterface("api.example.com", 8080, "https", None, 30.0, 10.0, True)
        self.assertEqual(i.name, "HttpClientInterface")
        self.assertEqual(i.hostname, "api.example.com")
        self.assertEqual(i.port, 8080)
        self.assertEqual(i.protocol, "https")
        self.assertEqual(i.url, "https://api.example.com:8080")
        self.assertEqual(i.read_timeout, 30.0)
        self.assertEqual(i.connect_timeout, 10.0)
        self.assertTrue(i.include_request_in_response)

    def test_default_parameters(self):
        i = HttpClientInterface("example.com")
        self.assertEqual(i.hostname, "example.com")
        self.assertEqual(i.port, 80)
        self.assertEqual(i.protocol, "http")
        self.assertEqual(i.url, "http://example.com")
        self.assertIsNone(i.read_timeout)
        self.assertEqual(i.connect_timeout, 5)
        self.assertFalse(i.include_request_in_response)

    def test_url_generation_standard_ports(self):
        # HTTP on port 80 should not include port in URL
        i = HttpClientInterface("example.com", 80, "http")
        self.assertEqual(i.url, "http://example.com")
        
        # HTTPS on port 443 should not include port in URL
        i = HttpClientInterface("example.com", 443, "https")
        self.assertEqual(i.url, "https://example.com")

    def test_url_generation_custom_ports(self):
        # HTTP on non-80 port should include port
        i = HttpClientInterface("example.com", 8080, "http")
        self.assertEqual(i.url, "http://example.com:8080")
        
        # HTTPS on non-443 port should include port
        i = HttpClientInterface("example.com", 8443, "https")
        self.assertEqual(i.url, "https://example.com:8443")

    def test_connection_string(self):
        i = HttpClientInterface("api.example.com", 9000, "https")
        self.assertEqual(i.connection_string(), "https://api.example.com:9000")

    def test_details(self):
        i = HttpClientInterface("api.example.com", 8080, "https", None, 30.0, 10.0, True)
        details = i.details()
        
        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)
        
        # Check that it includes the expected keys specific to HttpClientInterface
        self.assertIn('url', details)
        self.assertIn('write_timeout', details)
        self.assertIn('read_timeout', details)
        self.assertIn('connect_timeout', details)
        self.assertIn('include_request_in_response', details)
        self.assertIn('request_queue_length', details)
        
        # Verify the specific values are correct
        self.assertEqual(details['url'], "https://api.example.com:8080")
        self.assertIsNone(details['write_timeout'])  # Python version doesn't use write_timeout
        self.assertEqual(details['read_timeout'], 30.0)
        self.assertEqual(details['connect_timeout'], 10.0)
        self.assertTrue(details['include_request_in_response'])
        self.assertEqual(details['request_queue_length'], 0)  # Empty queue

    def test_details_with_defaults(self):
        i = HttpClientInterface("localhost")
        details = i.details()
        
        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)
        
        # Check default values
        self.assertEqual(details['url'], "http://localhost")
        self.assertIsNone(details['write_timeout'])
        self.assertIsNone(details['read_timeout'])
        self.assertEqual(details['connect_timeout'], 5)
        self.assertFalse(details['include_request_in_response'])
        self.assertEqual(details['request_queue_length'], 0)

    def test_details_with_none_timeouts(self):
        i = HttpClientInterface("example.com", 80, "http", None, "None", "None", False)
        details = i.details()
        
        # Verify it returns a dictionary
        self.assertIsInstance(details, dict)
        
        # Check None values are preserved
        self.assertEqual(details['url'], "http://example.com")
        self.assertIsNone(details['write_timeout'])
        self.assertIsNone(details['read_timeout'])
        self.assertIsNone(details['connect_timeout'])
        self.assertFalse(details['include_request_in_response'])

    def test_details_with_queue_items(self):
        i = HttpClientInterface("example.com")
        # Add some items to the queue to test queue length reporting
        i.response_queue.put("item1")
        i.response_queue.put("item2")
        i.response_queue.put("item3")
        
        details = i.details()
        
        # Verify queue length is reported correctly
        self.assertEqual(details['request_queue_length'], 3)


if __name__ == '__main__':
    unittest.main()