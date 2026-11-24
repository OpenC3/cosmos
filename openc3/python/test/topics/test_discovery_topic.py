# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest

from openc3.topics.discovery_topic import DiscoveryTopic


class TestDiscoveryTopic(unittest.TestCase):
    def test_parse_request(self):
        request = DiscoveryTopic.parse_request(
            {b"id": b"1", b"discovery": b'["openc3/discovery/serial_discovery.py"]', b"expires_at": b"12.5"}
        )
        self.assertEqual(
            request, {"id": "1", "discovery": ["openc3/discovery/serial_discovery.py"], "expires_at": 12.5}
        )

    def test_parse_scan_request(self):
        request = DiscoveryTopic.parse_request(
            {b"id": b"2", b"discovery": b"[]", b"scan": b'{"matchers": []}', b"expires_at": b"1"}
        )
        self.assertEqual(request, {"id": "2", "discovery": [], "scan": {"matchers": []}, "expires_at": 1.0})
