# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import Mock

from openc3.accessors.http_accessor import HttpAccessor


class TestHttpAccessor(unittest.TestCase):
    def setUp(self):
        self.packet = Mock()
        self.packet.extra = None
        self.accessor = HttpAccessor(self.packet)

    def _item(self, name, key=None):
        item = Mock()
        item.name = name
        item.key = key if key is not None else name
        return item

    def test_read_header_returns_none_when_header_missing(self):
        # Server responded without the requested header (e.g. no Content-Type)
        self.packet.extra = {"HTTP_HEADERS": {"other-header": "value"}}
        item = self._item("HTTP_HEADER_CONTENT-TYPE")
        self.assertIsNone(self.accessor.read_item(item, b""))

    def test_read_header_returns_value_when_present(self):
        self.packet.extra = {"HTTP_HEADERS": {"content-type": "application/json"}}
        item = self._item("HTTP_HEADER_CONTENT-TYPE")
        self.assertEqual(self.accessor.read_item(item, b""), "application/json")

    def test_read_query_returns_none_when_query_missing(self):
        self.packet.extra = {"HTTP_QUERIES": {"other": "value"}}
        item = self._item("HTTP_QUERY_FOO")
        self.assertIsNone(self.accessor.read_item(item, b""))

    def test_read_query_returns_value_when_present(self):
        self.packet.extra = {"HTTP_QUERIES": {"foo": "bar"}}
        item = self._item("HTTP_QUERY_FOO")
        self.assertEqual(self.accessor.read_item(item, b""), "bar")


if __name__ == "__main__":
    unittest.main()
