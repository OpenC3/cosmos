# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import Mock
from openc3.accessors.accessor import Accessor


class TestAccessor(unittest.TestCase):
    def test_returns_none_for_none_values(self):
        item = Mock()
        item.data_type = "INT"
        self.assertIsNone(Accessor.convert_to_type(None, item))

    def test_converts_bool_values_from_strings(self):
        item = Mock()
        item.data_type = "BOOL"
        self.assertEqual(Accessor.convert_to_type("True", item), True)
        self.assertEqual(Accessor.convert_to_type("true", item), True)
        self.assertEqual(Accessor.convert_to_type("False", item), False)
        self.assertEqual(Accessor.convert_to_type("false", item), False)
        self.assertEqual(Accessor.convert_to_type(True, item), True)
        self.assertEqual(Accessor.convert_to_type(False, item), False)

    def test_converts_array_values_from_strings(self):
        item = Mock()
        item.data_type = "ARRAY"
        self.assertEqual(Accessor.convert_to_type("[1, 2, 3]", item), [1, 2, 3])
        self.assertEqual(
            Accessor.convert_to_type('["a", "b", "c"]', item), ["a", "b", "c"]
        )
        self.assertEqual(Accessor.convert_to_type([1, 2, 3], item), [1, 2, 3])

    def test_converts_object_values_from_strings(self):
        item = Mock()
        item.data_type = "OBJECT"
        self.assertEqual(
            Accessor.convert_to_type('{"key": "value"}', item), {"key": "value"}
        )
        self.assertEqual(Accessor.convert_to_type('{"num": 123}', item), {"num": 123})
        self.assertEqual(
            Accessor.convert_to_type({"key": "value"}, item), {"key": "value"}
        )

    def test_converts_any_values_from_strings(self):
        item = Mock()
        item.data_type = "ANY"
        self.assertEqual(Accessor.convert_to_type('"text"', item), "text")
        self.assertEqual(Accessor.convert_to_type("123", item), 123)
        self.assertEqual(Accessor.convert_to_type("[1, 2, 3]", item), [1, 2, 3])
        self.assertEqual(
            Accessor.convert_to_type('{"key": "value"}', item), {"key": "value"}
        )
        self.assertEqual(Accessor.convert_to_type("invalid json", item), "invalid json")
        self.assertEqual(Accessor.convert_to_type(123, item), 123)
        self.assertEqual(Accessor.convert_to_type([1, 2, 3], item), [1, 2, 3])

    def test_converts_string_values_with_array_size_from_strings(self):
        item = Mock()
        item.data_type = "STRING"
        item.array_size = 10
        self.assertEqual(Accessor.convert_to_type('["a", "b"]', item), ["a", "b"])

    def test_converts_string_values_without_array_size(self):
        item = Mock()
        item.data_type = "STRING"
        item.array_size = None
        self.assertEqual(Accessor.convert_to_type("test", item), "test")
        self.assertEqual(Accessor.convert_to_type('["a", "b"]', item), '["a", "b"]')

    def test_converts_block_values(self):
        item = Mock()
        item.data_type = "BLOCK"
        item.array_size = None
        self.assertEqual(Accessor.convert_to_type(b"\x01\x02\x03", item), b"\x01\x02\x03")
        self.assertEqual(Accessor.convert_to_type("test", item), bytearray(b"test"))

    def test_converts_int_values(self):
        item = Mock()
        item.data_type = "INT"
        item.array_size = None
        self.assertEqual(Accessor.convert_to_type(42, item), 42)
        self.assertEqual(Accessor.convert_to_type("42", item), 42)
        self.assertEqual(Accessor.convert_to_type(-10, item), -10)
        self.assertEqual(Accessor.convert_to_type("-10", item), -10)

    def test_converts_uint_values(self):
        item = Mock()
        item.data_type = "UINT"
        item.array_size = None
        self.assertEqual(Accessor.convert_to_type(42, item), 42)
        self.assertEqual(Accessor.convert_to_type("42", item), 42)
        self.assertEqual(Accessor.convert_to_type(0, item), 0)

    def test_converts_float_values(self):
        item = Mock()
        item.data_type = "FLOAT"
        item.array_size = None
        self.assertEqual(Accessor.convert_to_type(3.14, item), 3.14)
        self.assertEqual(Accessor.convert_to_type("3.14", item), 3.14)
        self.assertEqual(Accessor.convert_to_type(0.0, item), 0.0)
        self.assertEqual(Accessor.convert_to_type(42, item), 42.0)

    def test_converts_int_array_values(self):
        item = Mock()
        item.data_type = "INT"
        item.array_size = 12
        self.assertEqual(Accessor.convert_to_type("[1, 2, 3]", item), [1, 2, 3])
        self.assertEqual(Accessor.convert_to_type([1, 2, 3], item), [1, 2, 3])

    def test_converts_float_array_values(self):
        item = Mock()
        item.data_type = "FLOAT"
        item.array_size = 24
        self.assertEqual(
            Accessor.convert_to_type("[1.1, 2.2, 3.3]", item), [1.1, 2.2, 3.3]
        )
        self.assertEqual(Accessor.convert_to_type([1.1, 2.2, 3.3], item), [1.1, 2.2, 3.3])
