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
from test.test_helper import Mock
from openc3.accessors.form_accessor import FormAccessor


class TestFormAccessor(unittest.TestCase):
    def setUp(self):
        self.item = Mock()
        self.item.key = "test_key"
        self.buffer = b"test_key=test_value&another_key=another_value"

    def test_read_item_single_value(self):
        result = FormAccessor.read_item(self.item, self.buffer)
        self.assertEqual(result, b"test_value")

    def test_read_item_multiple_values(self):
        buffer = b"test_key=value1&test_key=value2"
        result = FormAccessor.read_item(self.item, buffer)
        self.assertEqual(result, [b"value1", b"value2"])
        buffer = b"test_key=value1&test_key=value2&test_key=value3"
        result = FormAccessor.read_item(self.item, buffer)
        self.assertEqual(result, [b"value1", b"value2", b"value3"])

    def test_write_item_single_value(self):
        value = b"new_value"
        buffer = bytearray(self.buffer)
        FormAccessor.write_item(self.item, value, buffer)
        self.assertIn(b"test_key=new_value", buffer)

    def test_write_item_multiple_values(self):
        value = [b"value1", b"value2"]
        buffer = bytearray(self.buffer)
        FormAccessor.write_item(self.item, value, buffer)
        self.assertIn(b"test_key=value1&test_key=value2", buffer)
        value = [b"value1", b"value2", b"value3"]
        buffer = bytearray(self.buffer)
        FormAccessor.write_item(self.item, value, buffer)
        self.assertIn(b"test_key=value1&test_key=value2&test_key=value3", buffer)

    def test_enforce_encoding(self):
        accessor = FormAccessor()
        self.assertIsNone(accessor.enforce_encoding())

    def test_enforce_length(self):
        accessor = FormAccessor()
        self.assertFalse(accessor.enforce_length())

    def test_enforce_short_buffer_allowed(self):
        accessor = FormAccessor()
        self.assertTrue(accessor.enforce_short_buffer_allowed())

    def test_enforce_derived_write_conversion(self):
        accessor = FormAccessor()
        self.assertTrue(accessor.enforce_derived_write_conversion(self.item))
