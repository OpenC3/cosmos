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

import base64
import json
import os
import sys
import time
import pytest
from datetime import datetime, timezone
from unittest.mock import patch

# Add openc3 python path for imports
# Path: openc3/test/integration/tsdb/python -> openc3/python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "python"))

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
    # Truncate to microseconds (QuestDB stores microsecond precision)
    ts_us = ts_ns // 1000  # nanoseconds to microseconds
    ts_s = ts_us / 1_000_000  # microseconds to seconds as float
    return datetime.fromtimestamp(ts_s, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def is_questdb_available():
    """Check if QuestDB is available for testing."""
    try:
        import psycopg

        conn = psycopg.connect(
            host=os.environ.get("OPENC3_TSDB_HOSTNAME", "127.0.0.1"),
            port=int(os.environ.get("OPENC3_TSDB_QUERY_PORT", "8812")),
            user=os.environ.get("OPENC3_TSDB_USERNAME", "admin"),
            password=os.environ.get("OPENC3_TSDB_PASSWORD", "admin"),
            dbname="qdb",
            autocommit=True,
            connect_timeout=2,
        )
        conn.close()
        return True
    except Exception:
        return False


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


def create_packet_def(items):
    """Create a packet definition dict for use with create_table."""
    return {"items": items}


def create_item(name, data_type, bit_size=None, array_size=None, states=None, read_conversion=None):
    """Create an item definition for a packet."""
    item = {"name": name, "data_type": data_type}
    if bit_size is not None:
        item["bit_size"] = bit_size
    if array_size is not None:
        item["array_size"] = array_size
    if states is not None:
        item["states"] = states
    if read_conversion is not None:
        item["read_conversion"] = read_conversion
    return item


@requires_questdb
class TestIntSignedRoundtrip:
    """Tests for INT (signed integer) type round-trip through QuestDB."""

    def test_int3_bitfield_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """INT 3-bit bitfield (-4 to 3) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "INT3"
        clean_table(f"{target_name}__{packet_name}")

        # Create table using questdb_client.create_table
        packet_def = create_packet_def([create_item("VALUE", "INT", bit_size=3)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        # Insert test values using process_json_data and write_row
        test_values = [-4, -2, -1, 0, 1, 2, 3]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        # Read back using tsdb_lookup
        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected, f"Value mismatch at index {i}: expected {expected}, got {result[i][0][0]}"

    def test_int8_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """INT 8-bit (-128 to 127) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "INT8"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "INT", bit_size=8)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [-128, -64, -1, 0, 1, 64, 127]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_int13_bitfield_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """INT 13-bit bitfield (-4096 to 4095) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "INT13"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "INT", bit_size=13)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [-4096, -2048, -1, 0, 1, 2048, 4095]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_int16_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """INT 16-bit (-32768 to 32767) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "INT16"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "INT", bit_size=16)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [-32768, -16384, -1, 0, 1, 16384, 32767]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_int32_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """INT 32-bit round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "INT32"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "INT", bit_size=32)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        # Avoid QuestDB NULL sentinel (Integer.MIN_VALUE)
        test_values = [-2147483647, -1073741824, -1, 0, 1, 1073741824, 2147483647]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_int64_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """INT 64-bit round-trips correctly using DECIMAL column."""
        target_name, packet_name = "ROUNDTRIP", "INT64"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "INT", bit_size=64)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        # Avoid QuestDB NULL sentinel (Long.MIN_VALUE)
        test_values = [-9223372036854775807, -4611686018427387904, -1, 0, 1, 4611686018427387904, 9223372036854775807]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected


@requires_questdb
class TestUintUnsignedRoundtrip:
    """Tests for UINT (unsigned integer) type round-trip through QuestDB."""

    def test_uint3_bitfield_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """UINT 3-bit bitfield (0 to 7) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "UINT3"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "UINT", bit_size=3)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [0, 1, 2, 3, 4, 5, 6, 7]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_uint8_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """UINT 8-bit (0 to 255) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "UINT8"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "UINT", bit_size=8)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [0, 1, 64, 127, 128, 192, 255]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_uint13_bitfield_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """UINT 13-bit bitfield (0 to 8191) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "UINT13"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "UINT", bit_size=13)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [0, 1, 1024, 4096, 6144, 8190, 8191]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_uint16_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """UINT 16-bit (0 to 65535) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "UINT16"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "UINT", bit_size=16)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [0, 1, 16384, 32767, 32768, 49152, 65535]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_uint32_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """UINT 32-bit (0 to 4294967295) round-trips correctly using long column."""
        target_name, packet_name = "ROUNDTRIP", "UINT32"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "UINT", bit_size=32)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [0, 1, 1073741824, 2147483647, 2147483648, 3221225472, 4294967295]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_uint64_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """UINT 64-bit values that fit in signed long round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "UINT64"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "UINT", bit_size=64)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        # Values that fit in signed long (0 to 2^63-1)
        test_values = [0, 1, 4611686018427387904, 9223372036854775807]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected


@requires_questdb
class TestFloatRoundtrip:
    """Tests for FLOAT type round-trip through QuestDB."""

    def test_float32_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """FLOAT 32-bit (single precision) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "FLOAT32"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "FLOAT", bit_size=32)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [-3.4028235e38, -1.0, 0.0, 1.0, 3.4028235e38]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": float(val)}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            actual = result[i][0][0]
            if expected == 0.0:
                assert actual == 0.0
            else:
                assert abs(expected - actual) < abs(expected) * 1e-6

    def test_float64_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """FLOAT 64-bit (double precision) round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "FLOAT64"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "FLOAT", bit_size=64)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [-1.7976931348623157e308, -1.0, 0.0, 1.0, 1.7976931348623157e308]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            actual = result[i][0][0]
            if expected == 0.0:
                assert actual == 0.0
            else:
                assert abs(expected - actual) < abs(expected) * 1e-14


@requires_questdb
class TestStringRoundtrip:
    """Tests for STRING type round-trip through QuestDB."""

    def test_string_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """STRING values round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "STRING"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "STRING")])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = ["", "hello", "Hello World!", "CONNECTED", "0x1234ABCD", "with\nnewline", "unicode: éèêë"]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected


@requires_questdb
class TestBlockRoundtrip:
    """Tests for BLOCK (binary) type round-trip through QuestDB."""

    def test_block_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """BLOCK binary data stored as base64 round-trips correctly."""
        target_name, packet_name = "ROUNDTRIP", "BLOCK"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "BLOCK")])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_binaries = [
            b"",
            b"\x00",
            b"\x00\x01\x02\x03",
            b"\xff\xfe\xfd",
            bytes(range(256)),
            b"ASCII text as bytes",
        ]

        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_binaries):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_binaries))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_binaries) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_binaries)
        for i, expected in enumerate(test_binaries):
            assert result[i][0][0] == expected


@requires_questdb
class TestDerivedRoundtrip:
    """Tests for DERIVED type round-trip through QuestDB."""

    def test_derived_int_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """DERIVED integer values round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "DERIVED_INT"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "DERIVED")])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [42, -100, 0, 999999]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_derived_float_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """DERIVED float values round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "DERIVED_FLOAT"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "DERIVED")])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = [3.14159, -2.71828, 0.0, 1e10]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected

    def test_derived_string_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """DERIVED string values round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "DERIVED_STR"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "DERIVED")])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_values = ["hello", "world", "CONNECTED"]
        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, val in enumerate(test_values):
            columns = questdb_client.process_json_data({"VALUE": val}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_values))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_values) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_values)
        for i, expected in enumerate(test_values):
            assert result[i][0][0] == expected


@requires_questdb
class TestArrayRoundtrip:
    """Tests for ARRAY type round-trip through QuestDB."""

    def test_array_numeric_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """Numeric arrays (JSON-encoded) round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "ARRAY_NUM"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "FLOAT", array_size=10)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_arrays = [
            [1.0, 2.0, 3.0, 4.0, 5.0],
            [-1.5, 0.0, 1.5],
            [1e10, 1e-10, 0.0],
            [100, 200, 300],
        ]

        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, arr in enumerate(test_arrays):
            columns = questdb_client.process_json_data({"VALUE": arr}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_arrays))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_arrays) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_arrays)
        for i, expected in enumerate(test_arrays):
            assert result[i][0][0] == expected

    def test_array_string_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """String arrays (JSON-encoded) round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "ARRAY_STR"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "STRING", array_size=10)])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_arrays = [
            ["a", "b", "c"],
            ["CONNECTED", "DISCONNECTED", "UNKNOWN"],
            ["hello", "world"],
        ]

        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, arr in enumerate(test_arrays):
            columns = questdb_client.process_json_data({"VALUE": arr}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_arrays))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_arrays) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_arrays)
        for i, expected in enumerate(test_arrays):
            assert result[i][0][0] == expected


@requires_questdb
class TestObjectRoundtrip:
    """Tests for OBJECT type round-trip through QuestDB."""

    def test_object_simple_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """Simple OBJECT values (JSON-encoded) round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "OBJ_SIMPLE"
        clean_table(f"{target_name}__{packet_name}")

        # Objects are stored as DERIVED (JSON-encoded)
        packet_def = create_packet_def([create_item("VALUE", "DERIVED")])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_objects = [
            {},
            {"key": "value"},
            {"name": "test", "count": 42},
            {"nested": {"inner": "value"}},
        ]

        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, obj in enumerate(test_objects):
            columns = questdb_client.process_json_data({"VALUE": obj}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_objects))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_objects) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_objects)
        for i, expected in enumerate(test_objects):
            actual = result[i][0][0]
            if isinstance(actual, str):
                actual = json.loads(actual)
            assert actual == expected

    def test_object_complex_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """Complex OBJECT values with mixed types round-trip correctly."""
        target_name, packet_name = "ROUNDTRIP", "OBJ_COMPLEX"
        clean_table(f"{target_name}__{packet_name}")

        packet_def = create_packet_def([create_item("VALUE", "DERIVED")])
        table_name = questdb_client.create_table(target_name, packet_name, packet_def)

        test_objects = [
            {"int": 42, "float": 3.14, "string": "hello", "bool": True, "null": None},
            {"array": [1, 2, 3], "nested": {"a": 1, "b": 2}},
            {"mixed_array": [1, "two", 3.0, True]},
        ]

        ts = int(time.time() * 1e9)
        ts_iso = ts_to_iso(ts)

        for i, obj in enumerate(test_objects):
            columns = questdb_client.process_json_data({"VALUE": obj}, table_name)
            columns["RECEIVED_COUNT"] = i
            questdb_client.write_row(table_name, columns, ts + i * 1000000000)
        questdb_client.flush()
        wait_for_data(questdb_client, table_name, len(test_objects))

        items = [(target_name, packet_name, "VALUE", "RAW", False)]

        with patch("openc3.models.cvt_model.TargetModel") as mock_target:
            mock_target.packet.return_value = packet_def
            end_ts = ts_to_iso(ts + len(test_objects) * 1000000000)
            result = CvtModel.tsdb_lookup(items, start_time=ts_iso, end_time=end_ts)

        assert len(result) == len(test_objects)
        for i, expected in enumerate(test_objects):
            actual = result[i][0][0]
            if isinstance(actual, str):
                actual = json.loads(actual)
            assert actual == expected


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
