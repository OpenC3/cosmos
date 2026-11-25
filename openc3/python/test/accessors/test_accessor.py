# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import time
import unittest
from decimal import Decimal
from fractions import Fraction
from unittest.mock import Mock

import numpy as np

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
        self.assertEqual(Accessor.convert_to_type('["a", "b", "c"]', item), ["a", "b", "c"])
        self.assertEqual(Accessor.convert_to_type([1, 2, 3], item), [1, 2, 3])
        # json.loads can't parse this (single quotes, mixed types) but literal_eval can
        self.assertEqual(Accessor.convert_to_type("[2.2, '3', 4]", item), [2.2, "3", 4])

    def test_converts_object_values_from_strings(self):
        item = Mock()
        item.data_type = "OBJECT"
        self.assertEqual(Accessor.convert_to_type('{"key": "value"}', item), {"key": "value"})
        self.assertEqual(Accessor.convert_to_type('{"num": 123}', item), {"num": 123})
        self.assertEqual(Accessor.convert_to_type({"key": "value"}, item), {"key": "value"})

    def test_converts_any_values_from_strings(self):
        item = Mock()
        item.data_type = "ANY"
        self.assertEqual(Accessor.convert_to_type('"text"', item), "text")
        self.assertEqual(Accessor.convert_to_type("123", item), 123)
        self.assertEqual(Accessor.convert_to_type("[1, 2, 3]", item), [1, 2, 3])
        self.assertEqual(Accessor.convert_to_type('{"key": "value"}', item), {"key": "value"})
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

    def test_preserves_large_integer_values(self):
        item = Mock(array_size=None)
        cases = {
            "INT": [-(2**63), -(2**63) + 1, -(2**53 + 1), 2**53 + 1, 2**63 - 1],
            "UINT": [2**53 + 1, 2**63 - 1, 2**64 - 1],
        }
        for data_type, values in cases.items():
            item.data_type = data_type
            for value in values:
                spaced = f"  {value}\n"
                zero_padded = f"-000{-value}" if value < 0 else f"000{value}"
                inputs = (value, str(value), spaced, zero_padded, hex(value), Decimal(value), str(value).encode())
                for input_value in inputs:
                    with self.subTest(data_type=data_type, value=input_value):
                        self.assertEqual(Accessor.convert_to_type(input_value, item), value)

    def test_preserves_large_integer_array_values(self):
        item = Mock(array_size=192)
        cases = {"INT": [-(2**63) + 1, -(2**53 + 1), 2**63 - 1], "UINT": [2**53 + 1, 2**63 - 1, 2**64 - 1]}
        for data_type, values in cases.items():
            item.data_type = data_type
            strings = [str(value) for value in values]
            for input_values in (values, strings, str(values), str(strings)):
                with self.subTest(data_type=data_type, values=input_values):
                    self.assertEqual(Accessor.convert_to_type(input_values, item), values)

    def test_preserves_numpy_integer_values(self):
        cases = {
            "INT": [np.int64(-(2**63)), np.int64(-(2**53 + 1)), np.int64(2**63 - 1), np.int8(-5)],
            "UINT": [np.uint64(2**53 + 1), np.uint64(2**64 - 1), np.uint8(255)],
        }
        item = Mock()
        for data_type, values in cases.items():
            item.data_type = data_type
            for value in values:
                with self.subTest(data_type=data_type, value=value):
                    item.array_size = None
                    result = Accessor.convert_to_type(value, item)
                    self.assertEqual(result, int(value))
                    self.assertIs(type(result), int)
            with self.subTest(data_type=data_type, values=values):
                item.array_size = 64 * len(values)
                self.assertEqual(Accessor.convert_to_type(np.array(values), item), [int(v) for v in values])

    def test_truncates_non_integer_numbers(self):
        cases = [
            (3.7, 3),
            (-3.7, -3),
            (np.float64(3.7), 3),
            (np.float32(-3.7), -3),
            (Decimal("3.7"), 3),
            (Decimal("-3.7"), -3),
            (Decimal("18446744073709551615.9"), 2**64 - 1),
            (Fraction(7, 2), 3),
            (True, 1),
            (False, 0),
        ]
        item = Mock()
        for data_type in ("INT", "UINT"):
            item.data_type = data_type
            for value, expected in cases:
                with self.subTest(data_type=data_type, value=value):
                    item.array_size = None
                    result = Accessor.convert_to_type(value, item)
                    self.assertEqual(result, expected)
                    self.assertIs(type(result), int)
                    item.array_size = 64
                    self.assertEqual(Accessor.convert_to_type([value], item), [expected])

    def test_rejects_non_finite_numbers(self):
        item = Mock(data_type="INT", array_size=None)
        for value in (float("nan"), Decimal("NaN")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                Accessor.convert_to_type(value, item)
        for value in (float("inf"), float("-inf"), Decimal("Infinity")):
            with self.subTest(value=value), self.assertRaises(OverflowError):
                Accessor.convert_to_type(value, item)

    # These cases match convert_to_int in accessor.rb
    def test_parses_integer_strings(self):
        cases = [
            ("0", 0),
            ("-0", 0),
            ("+10", 10),
            (" -10\n", -10),
            ("1_000", 1000),
            ("0x10", 16),
            ("-0X1f", -31),
            ("0x1_F", 31),
            ("0b101", 5),
            ("0B1_0", 2),
            ("0o17", 15),
            ("010", 10),
            ("-010", -10),
            ("0_10", 10),
            ("08", 8),
            ("0089", 89),
            ("-007", -7),
            ("\n0042\t", 42),
            ("0x010", 16),
            ("00", 0),
            ("0d10", 10),
            ("0D09", 9),
            (b"0x10", 16),
            (bytearray(b"42"), 42),
        ]
        item = Mock()
        for data_type in ("INT", "UINT"):
            item.data_type = data_type
            for value, expected in cases:
                with self.subTest(data_type=data_type, value=value):
                    item.array_size = None
                    self.assertEqual(Accessor.convert_to_type(value, item), expected)
                    item.array_size = 64
                    self.assertEqual(Accessor.convert_to_type([value], item), [expected])

    def test_rejects_non_integer_strings(self):
        cases = [
            "3.7",
            "-3.7",
            "1.0",
            "1e3",
            "0o8",
            "00x10",
            "0b2",
            "0xg",
            "0x",
            "0x_10",
            "0__10",
            "1__000",
            "_1",
            "1_",
            "- 10",
            "--10",
            "1 0",
            "",
            "   ",
            "invalid",
            "\u00a010",
            "\u0661\u0662",
            "10\x00",
        ]
        item = Mock()
        for data_type in ("INT", "UINT"):
            item.data_type = data_type
            for value in cases:
                with self.subTest(data_type=data_type, value=value):
                    item.array_size = None
                    with self.assertRaises(ValueError):
                        Accessor.convert_to_type(value, item)
                    item.array_size = 64
                    with self.assertRaises(ValueError):
                        Accessor.convert_to_type([value], item)

    def test_parses_long_zero_runs_in_linear_time(self):
        # A leading-zero regex with backtracking took about 18 seconds here
        item = Mock(data_type="INT", array_size=None)
        start = time.perf_counter()
        for value in ("0" * 50_000 + "x", "0_" * 50_000 + "x"):
            with self.assertRaises(ValueError):
                Accessor.convert_to_type(value, item)
        self.assertLess(time.perf_counter() - start, 1.0)

    def test_converts_float_array_values(self):
        item = Mock()
        item.data_type = "FLOAT"
        item.array_size = 24
        self.assertEqual(Accessor.convert_to_type("[1.1, 2.2, 3.3]", item), [1.1, 2.2, 3.3])
        self.assertEqual(Accessor.convert_to_type([1.1, 2.2, 3.3], item), [1.1, 2.2, 3.3])
