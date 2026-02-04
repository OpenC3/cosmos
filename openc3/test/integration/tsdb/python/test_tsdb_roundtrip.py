# Copyright 2026 OpenC3, Inc.
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

"""
End-to-end TSDB roundtrip tests using QuestDBClient for writes and CvtModel.tsdb_lookup for reads.

These tests verify that all COSMOS data types can be:
1. Written to QuestDB using QuestDBClient.create_table and write_row (as the real system does)
2. Read back using CvtModel.tsdb_lookup (as the real system does)
3. Round-trip with correct type conversion and value fidelity

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: poetry run pytest python/test_tsdb_roundtrip.py -v
    3. Stop QuestDB: docker compose -f docker-compose.test.yml down
"""

import json
import os
import sys
import time
import pytest
from datetime import datetime, timezone
from unittest.mock import patch

# Add openc3 python path for imports
# Path: openc3/test/integration/tsdb/python -> openc3/python
sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "python")
)

# Set environment variables for QuestDB connection (test defaults)
os.environ.setdefault("OPENC3_TSDB_HOSTNAME", "127.0.0.1")
os.environ.setdefault("OPENC3_TSDB_INGEST_PORT", "9000")
os.environ.setdefault("OPENC3_TSDB_QUERY_PORT", "8812")
os.environ.setdefault("OPENC3_TSDB_USERNAME", "admin")
os.environ.setdefault("OPENC3_TSDB_PASSWORD", "admin")
os.environ.setdefault("OPENC3_SCOPE", "DEFAULT")

from conftest import requires_questdb
from openc3.utilities.questdb_client import QuestDBClient
from openc3.models.cvt_model import CvtModel


def ts_to_iso(ts_ns: int) -> str:
    """Convert nanosecond timestamp to ISO string, truncating to microseconds to match QuestDB storage."""
    ts_us = ts_ns // 1000
    ts_s = ts_us / 1_000_000
    return datetime.fromtimestamp(ts_s, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%S.%fZ"
    )


@pytest.fixture
def questdb_client():
    """Fixture providing a connected QuestDB client."""
    client = QuestDBClient()
    client.connect_ingest()
    client.connect_query()
    yield client
    client.close()


@pytest.fixture
def clean_table(questdb_client):
    """Fixture factory for creating and cleaning up test tables."""
    created_tables = []

    def _clean_table(table_name):
        try:
            with questdb_client.query.cursor() as cur:
                cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
        except Exception:
            pass
        created_tables.append(table_name)
        return table_name

    yield _clean_table

    for table_name in created_tables:
        try:
            with questdb_client.query.cursor() as cur:
                cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
        except Exception:
            pass


@pytest.fixture
def wait_for_data():
    """Fixture to wait for data to be visible in QuestDB."""

    def _wait(questdb_client, table_name, expected_count, timeout=5.0):
        start = time.time()
        while time.time() - start < timeout:
            try:
                with questdb_client.query.cursor() as cur:
                    cur.execute(f'SELECT count() FROM "{table_name}"')
                    count = cur.fetchone()[0]
                    if count >= expected_count:
                        return count
            except Exception:
                pass
            time.sleep(0.1)
        return 0

    return _wait


@pytest.fixture
def run_roundtrip_test(questdb_client, clean_table, wait_for_data):
    """
    Fixture providing a helper function to run roundtrip tests.

    Args:
        packet_name: Name of the packet (target is always "ROUNDTRIP")
        data_type: COSMOS data type (INT, UINT, FLOAT, STRING, BLOCK, DERIVED)
        test_values: List of values to test
        bit_size: Optional bit size for numeric types
        array_size: Optional array size for array types
        comparator: Optional function(expected, actual, index) for custom comparison
    """

    def _run_test(
        packet_name,
        data_type,
        test_values,
        bit_size=None,
        array_size=None,
        comparator=None,
        read_conversion=None,
    ):
        target_name = "ROUNDTRIP"
        clean_table(f"{target_name}__{packet_name}")

        # Build item definition
        item = {"name": "VALUE", "data_type": data_type}
        if bit_size is not None:
            item["bit_size"] = bit_size
        if array_size is not None:
            item["array_size"] = array_size
        if read_conversion is not None:
            item["read_conversion"] = read_conversion

        packet_def = {"items": [item]}
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        # Insert test values
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1_000_000_000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        # Read back using tsdb_lookup
        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1_000_000_000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        # Verify results
        assert len(result) == len(
            test_values
        ), f"Expected {len(test_values)} results, got {len(result)}"
        for i, expected in enumerate(test_values):
            actual = result[i][0][0]
            if comparator:
                comparator(expected, actual, i)
            else:
                assert (
                    actual == expected
                ), f"Value mismatch at index {i}: expected {expected}, got {actual}"

    return _run_test


# Comparator functions for special types
def float32_comparator(expected, actual, i):
    if expected == 0.0:
        assert actual == 0.0, f"Expected 0.0 at index {i}, got {actual}"
    else:
        assert (
            abs(expected - actual) < abs(expected) * 1e-6
        ), f"Float mismatch at index {i}: expected {expected}, got {actual}"


def float64_comparator(expected, actual, i):
    if expected == 0.0:
        assert actual == 0.0, f"Expected 0.0 at index {i}, got {actual}"
    else:
        assert (
            abs(expected - actual) < abs(expected) * 1e-14
        ), f"Float mismatch at index {i}: expected {expected}, got {actual}"


def json_comparator(expected, actual, i):
    if isinstance(actual, str):
        actual = json.loads(actual)
    assert (
        actual == expected
    ), f"Object mismatch at index {i}: expected {expected}, got {actual}"


@requires_questdb
class TestIntSignedRoundtrip:
    """Tests for INT (signed integer) type round-trip through QuestDB."""

    def test_int3_bitfield_roundtrip(self, run_roundtrip_test):
        """INT 3-bit bitfield (-4 to 3) round-trips correctly."""
        run_roundtrip_test("INT3", "INT", [-4, -2, -1, 0, 1, 2, 3], bit_size=3)

    def test_int8_roundtrip(self, run_roundtrip_test):
        """INT 8-bit (-128 to 127) round-trips correctly."""
        run_roundtrip_test("INT8", "INT", [-128, -64, -1, 0, 1, 64, 127], bit_size=8)

    def test_int13_bitfield_roundtrip(self, run_roundtrip_test):
        """INT 13-bit bitfield (-4096 to 4095) round-trips correctly."""
        run_roundtrip_test(
            "INT13", "INT", [-4096, -2048, -1, 0, 1, 2048, 4095], bit_size=13
        )

    def test_int16_roundtrip(self, run_roundtrip_test):
        """INT 16-bit (-32768 to 32767) round-trips correctly."""
        run_roundtrip_test(
            "INT16", "INT", [-32768, -16384, -1, 0, 1, 16384, 32767], bit_size=16
        )

    def test_int32_roundtrip(self, run_roundtrip_test):
        """INT 32-bit round-trips correctly."""
        # Avoid QuestDB NULL sentinel (Integer.MIN_VALUE)
        run_roundtrip_test(
            "INT32",
            "INT",
            [-2147483647, -1073741824, -1, 0, 1, 1073741824, 2147483647],
            bit_size=32,
        )

    def test_int64_roundtrip(self, run_roundtrip_test):
        """INT 64-bit round-trips correctly using DECIMAL column."""
        # Avoid QuestDB NULL sentinel (Long.MIN_VALUE)
        run_roundtrip_test(
            "INT64",
            "INT",
            [
                -9223372036854775807,
                -4611686018427387904,
                -1,
                0,
                1,
                4611686018427387904,
                9223372036854775807,
            ],
            bit_size=64,
        )


@requires_questdb
class TestUintUnsignedRoundtrip:
    """Tests for UINT (unsigned integer) type round-trip through QuestDB."""

    def test_uint3_bitfield_roundtrip(self, run_roundtrip_test):
        """UINT 3-bit bitfield (0 to 7) round-trips correctly."""
        run_roundtrip_test("UINT3", "UINT", [0, 1, 2, 3, 4, 5, 6, 7], bit_size=3)

    def test_uint8_roundtrip(self, run_roundtrip_test):
        """UINT 8-bit (0 to 255) round-trips correctly."""
        run_roundtrip_test("UINT8", "UINT", [0, 1, 64, 127, 128, 192, 255], bit_size=8)

    def test_uint13_bitfield_roundtrip(self, run_roundtrip_test):
        """UINT 13-bit bitfield (0 to 8191) round-trips correctly."""
        run_roundtrip_test(
            "UINT13", "UINT", [0, 1, 1024, 4096, 6144, 8190, 8191], bit_size=13
        )

    def test_uint16_roundtrip(self, run_roundtrip_test):
        """UINT 16-bit (0 to 65535) round-trips correctly."""
        run_roundtrip_test(
            "UINT16", "UINT", [0, 1, 16384, 32767, 32768, 49152, 65535], bit_size=16
        )

    def test_uint32_roundtrip(self, run_roundtrip_test):
        """UINT 32-bit (0 to 4294967295) round-trips correctly using long column."""
        run_roundtrip_test(
            "UINT32",
            "UINT",
            [0, 1, 1073741824, 2147483647, 2147483648, 3221225472, 4294967295],
            bit_size=32,
        )

    def test_uint64_roundtrip(self, run_roundtrip_test):
        """UINT 64-bit values that fit in signed long round-trip correctly."""
        # Values that fit in signed long (0 to 2^63-1)
        run_roundtrip_test(
            "UINT64",
            "UINT",
            [0, 1, 4611686018427387904, 9223372036854775807],
            bit_size=64,
        )


@requires_questdb
class TestFloatRoundtrip:
    """Tests for FLOAT type round-trip through QuestDB."""

    def test_float32_roundtrip(self, run_roundtrip_test):
        """FLOAT 32-bit (single precision) round-trips correctly."""
        run_roundtrip_test(
            "FLOAT32",
            "FLOAT",
            [-3.4028235e38, -1.0, 0.0, 1.0, 3.4028235e38],
            bit_size=32,
            comparator=float32_comparator,
        )

    def test_float64_roundtrip(self, run_roundtrip_test):
        """FLOAT 64-bit (double precision) round-trips correctly."""
        run_roundtrip_test(
            "FLOAT64",
            "FLOAT",
            [-1.7976931348623157e308, -1.0, 0.0, 1.0, 1.7976931348623157e308],
            bit_size=64,
            comparator=float64_comparator,
        )


@requires_questdb
class TestStringRoundtrip:
    """Tests for STRING type round-trip through QuestDB."""

    def test_string_roundtrip(self, run_roundtrip_test):
        """STRING values round-trip correctly."""
        run_roundtrip_test(
            "STRING",
            "STRING",
            [
                "",
                "hello",
                "Hello World!",
                "CONNECTED",
                "0x1234ABCD",
                "with\nnewline",
                "unicode: éèêë",
            ],
        )


@requires_questdb
class TestBlockRoundtrip:
    """Tests for BLOCK (binary) type round-trip through QuestDB."""

    def test_block_roundtrip(self, run_roundtrip_test):
        """BLOCK binary data stored as base64 round-trips correctly."""
        run_roundtrip_test(
            "BLOCK",
            "BLOCK",
            [
                b"",
                b"\x00",
                b"\x00\x01\x02\x03",
                b"\xff\xfe\xfd",
                bytes(range(256)),
                b"ASCII text as bytes",
            ],
        )


@requires_questdb
class TestDerivedRoundtrip:
    """Tests for DERIVED type round-trip through QuestDB."""

    def test_derived_int_roundtrip(self, run_roundtrip_test):
        """DERIVED integer values round-trip correctly (JSON fallback)."""
        run_roundtrip_test("DERIVED_INT", "DERIVED", [42, -100, 0, 999999])

    def test_derived_float_roundtrip(self, run_roundtrip_test):
        """DERIVED float values round-trip correctly (JSON fallback)."""
        run_roundtrip_test("DERIVED_FLOAT", "DERIVED", [3.14159, -2.71828, 0.0, 1e10])

    def test_derived_string_roundtrip(self, run_roundtrip_test):
        """DERIVED string values round-trip correctly (JSON fallback)."""
        run_roundtrip_test("DERIVED_STR", "DERIVED", ["hello", "world", "CONNECTED"])


@requires_questdb
class TestDerivedTypedConversionRoundtrip:
    """Tests for DERIVED items with typed conversions (native QuestDB types)."""

    def test_derived_float32_conversion_roundtrip(self, run_roundtrip_test):
        """DERIVED with FLOAT 32-bit conversion uses native float column."""
        run_roundtrip_test(
            "DERIVED_FLOAT32_CONV",
            "DERIVED",
            [-3.4028235e38, -1.0, 0.0, 1.0, 3.4028235e38],
            read_conversion={"converted_type": "FLOAT", "converted_bit_size": 32},
            comparator=float32_comparator,
        )

    def test_derived_float64_conversion_roundtrip(self, run_roundtrip_test):
        """DERIVED with FLOAT 64-bit conversion uses native double column."""
        run_roundtrip_test(
            "DERIVED_FLOAT64_CONV",
            "DERIVED",
            [-1.7976931348623157e308, -1.0, 0.0, 1.0, 1.7976931348623157e308],
            read_conversion={"converted_type": "FLOAT", "converted_bit_size": 64},
            comparator=float64_comparator,
        )

    def test_derived_int16_conversion_roundtrip(self, run_roundtrip_test):
        """DERIVED with INT 16-bit conversion uses native int column."""
        run_roundtrip_test(
            "DERIVED_INT16_CONV",
            "DERIVED",
            [-32768, -1, 0, 1, 32767],
            read_conversion={"converted_type": "INT", "converted_bit_size": 16},
        )

    def test_derived_uint32_conversion_roundtrip(self, run_roundtrip_test):
        """DERIVED with UINT 32-bit conversion uses native long column."""
        run_roundtrip_test(
            "DERIVED_UINT32_CONV",
            "DERIVED",
            [0, 1, 2147483647, 2147483648, 4294967295],
            read_conversion={"converted_type": "UINT", "converted_bit_size": 32},
        )

    def test_derived_string_conversion_roundtrip(self, run_roundtrip_test):
        """DERIVED with STRING conversion uses native varchar column (no JSON)."""
        run_roundtrip_test(
            "DERIVED_STRING_CONV",
            "DERIVED",
            ["", "hello", "world", "with\nnewline"],
            read_conversion={"converted_type": "STRING", "converted_bit_size": 0},
        )

    def test_derived_array_conversion_roundtrip(self, run_roundtrip_test):
        """DERIVED with ARRAY conversion still uses JSON serialization."""
        run_roundtrip_test(
            "DERIVED_ARRAY_CONV",
            "DERIVED",
            [[1, 2, 3], [4.5, 5.5], ["a", "b"]],
            read_conversion={"converted_type": "ARRAY", "converted_bit_size": 0},
            comparator=json_comparator,
        )

    def test_derived_object_conversion_roundtrip(self, run_roundtrip_test):
        """DERIVED with OBJECT conversion still uses JSON serialization."""
        run_roundtrip_test(
            "DERIVED_OBJECT_CONV",
            "DERIVED",
            [{"key": "value"}, {"nested": {"a": 1}}, {}],
            read_conversion={"converted_type": "OBJECT", "converted_bit_size": 0},
            comparator=json_comparator,
        )


@requires_questdb
class TestArrayRoundtrip:
    """Tests for ARRAY type round-trip through QuestDB."""

    def test_array_numeric_roundtrip(self, run_roundtrip_test):
        """Numeric arrays (JSON-encoded) round-trip correctly."""
        run_roundtrip_test(
            "ARRAY_NUM",
            "FLOAT",
            [
                [1.0, 2.0, 3.0, 4.0, 5.0],
                [-1.5, 0.0, 1.5],
                [1e10, 1e-10, 0.0],
                [100, 200, 300],
            ],
            array_size=10,
        )

    def test_array_string_roundtrip(self, run_roundtrip_test):
        """String arrays (JSON-encoded) round-trip correctly."""
        run_roundtrip_test(
            "ARRAY_STR",
            "STRING",
            [
                ["a", "b", "c"],
                ["CONNECTED", "DISCONNECTED", "UNKNOWN"],
                ["hello", "world"],
            ],
            array_size=10,
        )


@requires_questdb
class TestObjectRoundtrip:
    """Tests for OBJECT type round-trip through QuestDB."""

    def test_object_simple_roundtrip(self, run_roundtrip_test):
        """Simple OBJECT values (JSON-encoded) round-trip correctly."""
        run_roundtrip_test(
            "OBJ_SIMPLE",
            "DERIVED",
            [
                {},
                {"key": "value"},
                {"name": "test", "count": 42},
                {"nested": {"inner": "value"}},
            ],
            comparator=json_comparator,
        )

    def test_object_complex_roundtrip(self, run_roundtrip_test):
        """Complex OBJECT values with mixed types round-trip correctly."""
        run_roundtrip_test(
            "OBJ_COMPLEX",
            "DERIVED",
            [
                {
                    "int": 42,
                    "float": 3.14,
                    "string": "hello",
                    "bool": True,
                    "null": None,
                },
                {"array": [1, 2, 3], "nested": {"a": 1, "b": 2}},
                {"mixed_array": [1, "two", 3.0, True]},
            ],
            comparator=json_comparator,
        )


@requires_questdb
class TestTimestampItemsRoundtrip:
    """Tests for calculated timestamp items (PACKET_TIMESECONDS, etc.)."""

    def run_timestamp_test(
        self, questdb_client, clean_table, wait_for_data, item_name, format_type
    ):
        """Helper to run timestamp item tests."""
        target_name = "ROUNDTRIP"
        packet_name = f"TS_{item_name}"
        clean_table(f"{target_name}__{packet_name}")

        # Build a simple packet definition
        packet_def = {"items": [{"name": "VALUE", "data_type": "INT", "bit_size": 32}]}
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        # Insert test values with known timestamps
        base_ts = int(time.time() * 1e9)
        test_values = [1, 2, 3]

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            # Each row is 1 second apart
            row_ts = base_ts + i * 1_000_000_000
            questdb_client.write_row(table_name, columns, row_ts, rx_timestamp_ns=row_ts)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        # Request the calculated timestamp item
        items = [(target_name, packet_name, item_name, "RAW", False)]
        start_time = ts_to_iso(base_ts)
        end_time = ts_to_iso(base_ts + len(test_values) * 1_000_000_000)

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            result = CvtModel.tsdb_lookup(items, start_time=start_time, end_time=end_time)

        assert len(result) == len(
            test_values
        ), f"Expected {len(test_values)} results, got {len(result)}"

        for i in range(len(test_values)):
            actual = result[i][0][0]
            # Each row is 1 second apart
            expected_ts_seconds = base_ts / 1e9 + i

            if format_type == "seconds":
                assert isinstance(
                    actual, float
                ), f"Expected float at index {i}, got {type(actual)}"
                assert (
                    abs(actual - expected_ts_seconds) < 0.001
                ), f"Timestamp seconds mismatch at index {i}: expected {expected_ts_seconds}, got {actual}"
            elif format_type == "formatted":
                assert isinstance(
                    actual, str
                ), f"Expected string at index {i}, got {type(actual)}"
                # Verify it's ISO 8601 format with Z timezone suffix
                import re
                assert re.match(
                    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$", actual
                ), f"Expected ISO 8601 format at index {i}, got {actual}"
                # Verify the formatted string can be parsed back to approximately the same time
                parsed = datetime.strptime(actual, "%Y-%m-%dT%H:%M:%S.%fZ")
                parsed_ts = parsed.replace(tzinfo=timezone.utc).timestamp()
                assert (
                    abs(parsed_ts - expected_ts_seconds) < 0.001
                ), f"Timestamp formatted mismatch at index {i}: expected {expected_ts_seconds}, got {actual}"

    def test_packet_timeseconds(
        self, questdb_client, clean_table, wait_for_data
    ):
        """PACKET_TIMESECONDS returns correct Unix timestamp in seconds."""
        self.run_timestamp_test(
            questdb_client, clean_table, wait_for_data, "PACKET_TIMESECONDS", "seconds"
        )

    def test_packet_timeformatted(
        self, questdb_client, clean_table, wait_for_data
    ):
        """PACKET_TIMEFORMATTED returns correct formatted timestamp string."""
        self.run_timestamp_test(
            questdb_client,
            clean_table,
            wait_for_data,
            "PACKET_TIMEFORMATTED",
            "formatted",
        )

    def test_received_timeseconds(
        self, questdb_client, clean_table, wait_for_data
    ):
        """RECEIVED_TIMESECONDS returns correct Unix timestamp in seconds."""
        self.run_timestamp_test(
            questdb_client,
            clean_table,
            wait_for_data,
            "RECEIVED_TIMESECONDS",
            "seconds",
        )

    def test_received_timeformatted(
        self, questdb_client, clean_table, wait_for_data
    ):
        """RECEIVED_TIMEFORMATTED returns correct formatted timestamp string."""
        self.run_timestamp_test(
            questdb_client,
            clean_table,
            wait_for_data,
            "RECEIVED_TIMEFORMATTED",
            "formatted",
        )

    def test_timestamp_items_with_regular_items(
        self, questdb_client, clean_table, wait_for_data
    ):
        """Timestamp items work correctly alongside regular items."""
        target_name = "ROUNDTRIP"
        packet_name = "TS_MIXED"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = {"items": [{"name": "VALUE", "data_type": "INT", "bit_size": 32}]}
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        base_ts = int(time.time() * 1e9)
        test_values = [100, 200]

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            row_ts = base_ts + i * 1_000_000_000
            questdb_client.write_row(table_name, columns, row_ts, rx_timestamp_ns=row_ts)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        # Request both regular item and timestamp items
        items = [
            (target_name, packet_name, "PACKET_TIMESECONDS", "RAW", False),
            (target_name, packet_name, "VALUE", "RAW", False),
            (target_name, packet_name, "PACKET_TIMEFORMATTED", "RAW", False),
        ]
        start_time = ts_to_iso(base_ts)
        end_time = ts_to_iso(base_ts + len(test_values) * 1_000_000_000)

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            result = CvtModel.tsdb_lookup(items, start_time=start_time, end_time=end_time)

        assert len(result) == 2

        # First row
        assert isinstance(result[0][0][0], float)  # PACKET_TIMESECONDS
        assert result[0][1][0] == 100  # VALUE
        assert isinstance(result[0][2][0], str)  # PACKET_TIMEFORMATTED

        # Second row
        assert isinstance(result[1][0][0], float)  # PACKET_TIMESECONDS
        assert result[1][1][0] == 200  # VALUE
        assert isinstance(result[1][2][0], str)  # PACKET_TIMEFORMATTED


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
