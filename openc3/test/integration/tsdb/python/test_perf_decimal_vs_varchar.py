# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Performance comparison across all integer bit widths in QuestDB.

Benchmarks insert and query+decode throughput for each COSMOS integer
bit size to show the performance characteristics of the underlying
QuestDB column types:

  - 1-bit, 16-bit  → QuestDB INT  (4 bytes, native)
  - 32-bit          → QuestDB LONG (8 bytes, native)
  - 64-bit, 128-bit, 256-bit → QuestDB VARCHAR (string, decoded via int(str))

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: uv run pytest python/test_perf_decimal_vs_varchar.py -v -s
    3. Stop QuestDB: docker compose -f docker-compose.test.yml down
"""

import os
import sys
import time
import pytest

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

ROW_COUNT = 10_000


def _make_packet_def(data_type, bit_size=None):
    """Build a packet definition dict with a single VALUE item."""
    item = {"name": "VALUE", "data_type": data_type}
    if bit_size is not None:
        item["bit_size"] = bit_size
    return {"items": [item]}


def _get_column_type(client, table_name, column_name="VALUE"):
    """Query QuestDB for the current column type."""
    with client.query.cursor() as cur:
        cur.execute(f'SHOW COLUMNS FROM "{table_name}"')
        for row in cur.fetchall():
            if row[0] == column_name:
                return row[1]
    return None


def _wait_for_rows(client, table_name, expected, timeout=30.0):
    """Block until the table has at least *expected* rows."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            with client.query.cursor() as cur:
                cur.execute(f'SELECT count() FROM "{table_name}"')
                if cur.fetchone()[0] >= expected:
                    return
        except Exception:
            pass
        time.sleep(0.2)
    pytest.fail(f"Timed out waiting for {expected} rows in {table_name}")


# Each entry: (label, data_type, bit_size, max_value, cosmos_data_type)
# max_value is the largest value for this bit width (unsigned)
BIT_WIDTH_CONFIGS = [
    ("UINT_1BIT",   "UINT",  1,   1,                                         "UINT"),
    ("UINT_16BIT",  "UINT", 16,   65535,                                     "UINT"),
    ("UINT_32BIT",  "UINT", 32,   4294967295,                                "UINT"),
    ("UINT_64BIT",  "UINT", 64,   18446744073709551615,                      "UINT"),
    ("UINT_128BIT", "UINT", 128,  340282366920938463463374607431768211455,    "UINT"),
    ("UINT_256BIT", "UINT", 256,
     115792089237316195423570985008687907853269984665640564039457584007913129639935,
     "UINT"),
]


@requires_questdb
class TestPerfByBitWidth:
    """Benchmark insert and query+decode for each integer bit width."""

    def _insert_rows(self, client, table_name, row_count, value_fn):
        """Insert *row_count* rows using *value_fn(i)* to produce each value."""
        base_ts = int(time.time() * 1e9)
        start = time.perf_counter()
        for i in range(row_count):
            value = value_fn(i)
            columns = client.process_json_data({"VALUE": value}, table_name)
            columns["RECEIVED_COUNT"] = i
            client.write_row(table_name, columns, base_ts + i * 1_000_000)
        client.flush()
        elapsed = time.perf_counter() - start
        return elapsed, base_ts

    def _query_all(self, client, table_name, base_ts, data_type):
        """SELECT all VALUE rows, decode each through decode_value, return
        (elapsed_seconds, row_count)."""
        start_us = base_ts // 1_000
        end_us = start_us + ROW_COUNT * 1_000 + 1_000_000
        start_iso = time.strftime(
            "%Y-%m-%dT%H:%M:%S", time.gmtime(start_us / 1_000_000)
        )
        end_iso = time.strftime(
            "%Y-%m-%dT%H:%M:%S", time.gmtime(end_us / 1_000_000)
        )

        query = (
            f'SELECT "VALUE" FROM "{table_name}" '
            f"WHERE PACKET_TIMESECONDS >= '{start_iso}' "
            f"AND PACKET_TIMESECONDS <= '{end_iso}'"
        )
        start = time.perf_counter()
        with client.query.cursor() as cur:
            cur.execute(query)
            rows = cur.fetchall()
        decoded = [
            QuestDBClient.decode_value(row[0], data_type=data_type) for row in rows
        ]
        elapsed = time.perf_counter() - start
        assert all(isinstance(v, int) for v in decoded)
        return elapsed, len(decoded)

    @pytest.mark.parametrize(
        "label,data_type,bit_size,max_value,cosmos_type",
        BIT_WIDTH_CONFIGS,
        ids=[c[0] for c in BIT_WIDTH_CONFIGS],
    )
    def test_insert(self, questdb_client, clean_table, label, data_type, bit_size, max_value, cosmos_type):
        table_name = clean_table(f"DEFAULT__TLM__PERF__{label}_INSERT")
        questdb_client.create_table(
            "PERF", f"{label}_INSERT", _make_packet_def(data_type, bit_size=bit_size)
        )
        qdb_type = _get_column_type(questdb_client, table_name)

        elapsed, _ = self._insert_rows(
            questdb_client, table_name, ROW_COUNT,
            value_fn=lambda i: max_value - (i % (max_value + 1)),
        )
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)
        rate = ROW_COUNT / elapsed
        print(
            f"\n  {label} insert ({bit_size}-bit → QuestDB {qdb_type}): "
            f"{ROW_COUNT} rows in {elapsed:.3f}s ({rate:,.0f} rows/s)"
        )

    @pytest.mark.parametrize(
        "label,data_type,bit_size,max_value,cosmos_type",
        BIT_WIDTH_CONFIGS,
        ids=[c[0] for c in BIT_WIDTH_CONFIGS],
    )
    def test_query(self, questdb_client, clean_table, wait_for_data, label, data_type, bit_size, max_value, cosmos_type):
        table_name = clean_table(f"DEFAULT__TLM__PERF__{label}_QUERY")
        questdb_client.create_table(
            "PERF", f"{label}_QUERY", _make_packet_def(data_type, bit_size=bit_size)
        )
        qdb_type = _get_column_type(questdb_client, table_name)

        _, base_ts = self._insert_rows(
            questdb_client, table_name, ROW_COUNT,
            value_fn=lambda i: max_value - (i % (max_value + 1)),
        )
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)

        elapsed, count = self._query_all(questdb_client, table_name, base_ts, cosmos_type)
        rate = count / elapsed
        print(
            f"\n  {label} query+decode ({bit_size}-bit → QuestDB {qdb_type}): "
            f"{count} rows in {elapsed:.3f}s ({rate:,.0f} rows/s)"
        )
        assert count == ROW_COUNT


@requires_questdb
class TestPerfDecimalBaseline:
    """Benchmark DECIMAL(20,0) with 64-bit values for comparison.

    We no longer create DECIMAL columns, but this provides a baseline
    to compare against VARCHAR for the same 64-bit value range.
    The table is created via raw SQL to bypass the normal mapping.
    """

    def _create_decimal_table(self, client, table_name):
        """Create a table with a DECIMAL(20,0) VALUE column via raw SQL."""
        with client.query.cursor() as cur:
            cur.execute(
                f'CREATE TABLE IF NOT EXISTS "{table_name}" ('
                f"PACKET_TIMESECONDS timestamp_ns, "
                f"RECEIVED_TIMESECONDS timestamp_ns, "
                f"RECEIVED_COUNT long, "
                f'COSMOS_DATA_TAG symbol, '
                f'COSMOS_EXTRA varchar, '
                f'"VALUE" DECIMAL(20, 0)'
                f") TIMESTAMP(PACKET_TIMESECONDS) PARTITION BY DAY"
            )

    def _insert_rows(self, client, table_name, row_count, max_value):
        """Insert rows with string values (ILP auto-casts to DECIMAL)."""
        base_ts = int(time.time() * 1e9)
        start = time.perf_counter()
        for i in range(row_count):
            value = str(max_value - i)
            columns = {"VALUE": value, "RECEIVED_COUNT": i}
            client.write_row(table_name, columns, base_ts + i * 1_000_000)
        client.flush()
        elapsed = time.perf_counter() - start
        return elapsed, base_ts

    def _query_all(self, client, table_name, base_ts):
        """Query and decode all rows through decode_value (Decimal → int)."""
        start_us = base_ts // 1_000
        end_us = start_us + ROW_COUNT * 1_000 + 1_000_000
        start_iso = time.strftime(
            "%Y-%m-%dT%H:%M:%S", time.gmtime(start_us / 1_000_000)
        )
        end_iso = time.strftime(
            "%Y-%m-%dT%H:%M:%S", time.gmtime(end_us / 1_000_000)
        )
        query = (
            f'SELECT "VALUE" FROM "{table_name}" '
            f"WHERE PACKET_TIMESECONDS >= '{start_iso}' "
            f"AND PACKET_TIMESECONDS <= '{end_iso}'"
        )
        start = time.perf_counter()
        with client.query.cursor() as cur:
            cur.execute(query)
            rows = cur.fetchall()
        decoded = [
            QuestDBClient.decode_value(row[0], data_type="UINT") for row in rows
        ]
        elapsed = time.perf_counter() - start
        assert all(isinstance(v, int) for v in decoded)
        return elapsed, len(decoded)

    def test_insert_decimal(self, questdb_client, clean_table):
        table_name = clean_table("DEFAULT__TLM__PERF__DECIMAL64_INSERT")
        self._create_decimal_table(questdb_client, table_name)
        qdb_type = _get_column_type(questdb_client, table_name)
        max_value = 18_446_744_073_709_551_615  # 2^64 - 1

        elapsed, _ = self._insert_rows(questdb_client, table_name, ROW_COUNT, max_value)
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)
        rate = ROW_COUNT / elapsed
        print(
            f"\n  DECIMAL_64BIT insert (64-bit → QuestDB {qdb_type}): "
            f"{ROW_COUNT} rows in {elapsed:.3f}s ({rate:,.0f} rows/s)"
        )

    def test_query_decimal(self, questdb_client, clean_table):
        table_name = clean_table("DEFAULT__TLM__PERF__DECIMAL64_QUERY")
        self._create_decimal_table(questdb_client, table_name)
        qdb_type = _get_column_type(questdb_client, table_name)
        max_value = 18_446_744_073_709_551_615

        _, base_ts = self._insert_rows(questdb_client, table_name, ROW_COUNT, max_value)
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)

        elapsed, count = self._query_all(questdb_client, table_name, base_ts)
        rate = count / elapsed
        print(
            f"\n  DECIMAL_64BIT query+decode (64-bit → QuestDB {qdb_type}): "
            f"{count} rows in {elapsed:.3f}s ({rate:,.0f} rows/s)"
        )
        assert count == ROW_COUNT
