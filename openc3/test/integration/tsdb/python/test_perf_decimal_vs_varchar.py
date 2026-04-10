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
Performance comparison: LONG vs VARCHAR for integer storage in QuestDB.

LONG is QuestDB's native signed 64-bit integer (8 bytes).  VARCHAR stores
integer values as strings and is used for ≥64-bit integers to avoid the
LONG NULL sentinel (0x8000000000000000).

This suite benchmarks both storage strategies so we can quantify the cost
of using VARCHAR for large integers:

  - LONG    — native signed 64-bit, fastest, used for <64-bit integers
  - VARCHAR — string storage, used for ≥64-bit integers, needs int(str) on read

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


@requires_questdb
class TestPerfLongVsVarchar:
    """Compare insert and query performance of LONG vs VARCHAR."""

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
        """SELECT all VALUE rows inside the time window, decode each value
        through ``QuestDBClient.decode_value`` (the real read path), and
        return (elapsed_seconds, row_count)."""
        # Convert ns timestamps to ISO-8601 strings for QuestDB WHERE clause
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
        # Decode every value through the real production path:
        #   LONG column    -> int (psycopg returns Python int directly)
        #   VARCHAR column -> str -> int(str)
        decoded = [
            QuestDBClient.decode_value(row[0], data_type=data_type) for row in rows
        ]
        elapsed = time.perf_counter() - start
        # Sanity-check that decode actually produced integers
        assert all(isinstance(v, int) for v in decoded)
        return elapsed, len(decoded)

    # ---- LONG (native signed 64-bit) ----

    def test_insert_long(self, questdb_client, clean_table):
        """INT 32-bit maps to LONG — native ILP integer path, no string conversion."""
        table_name = clean_table("DEFAULT__TLM__PERF__LONG_INSERT")
        questdb_client.create_table(
            "PERF", "LONG_INSERT", _make_packet_def("INT", bit_size=32)
        )
        elapsed, _ = self._insert_rows(
            questdb_client, table_name, ROW_COUNT,
            value_fn=lambda i: 9_223_372_036_854_775_807 - i,
        )
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)
        rate = ROW_COUNT / elapsed
        print(
            f"\n  LONG insert: {ROW_COUNT} rows in {elapsed:.3f}s "
            f"({rate:,.0f} rows/s)"
        )

    def test_query_long(self, questdb_client, clean_table, wait_for_data):
        """Query LONG column and decode via decode_value (int pass-through)."""
        table_name = clean_table("DEFAULT__TLM__PERF__LONG_QUERY")
        questdb_client.create_table(
            "PERF", "LONG_QUERY", _make_packet_def("INT", bit_size=32)
        )
        _, base_ts = self._insert_rows(
            questdb_client, table_name, ROW_COUNT,
            value_fn=lambda i: 9_223_372_036_854_775_807 - i,
        )
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)

        elapsed, count = self._query_all(questdb_client, table_name, base_ts, "INT")
        rate = count / elapsed
        print(
            f"\n  LONG query+decode: {count} rows in {elapsed:.3f}s "
            f"({rate:,.0f} rows/s)"
        )
        assert count == ROW_COUNT

    # ---- VARCHAR (string storage for ≥64-bit integers) ----

    def test_insert_varchar(self, questdb_client, clean_table):
        """UINT 64-bit maps to VARCHAR — values sent as strings via ILP."""
        table_name = clean_table("DEFAULT__TLM__PERF__VARCHAR_INSERT")
        questdb_client.create_table(
            "PERF", "VARCHAR_INSERT", _make_packet_def("UINT", bit_size=64)
        )
        elapsed, _ = self._insert_rows(
            questdb_client, table_name, ROW_COUNT,
            value_fn=lambda i: 18_446_744_073_709_551_615 - i,
        )
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)
        rate = ROW_COUNT / elapsed
        print(
            f"\n  VARCHAR insert: {ROW_COUNT} rows in {elapsed:.3f}s "
            f"({rate:,.0f} rows/s)"
        )

    def test_query_varchar(self, questdb_client, clean_table, wait_for_data):
        """Query VARCHAR column and decode via decode_value (str -> int)."""
        table_name = clean_table("DEFAULT__TLM__PERF__VARCHAR_QUERY")
        questdb_client.create_table(
            "PERF", "VARCHAR_QUERY", _make_packet_def("UINT", bit_size=64)
        )
        _, base_ts = self._insert_rows(
            questdb_client, table_name, ROW_COUNT,
            value_fn=lambda i: 18_446_744_073_709_551_615 - i,
        )
        _wait_for_rows(questdb_client, table_name, ROW_COUNT)

        elapsed, count = self._query_all(questdb_client, table_name, base_ts, "UINT")
        rate = count / elapsed
        print(
            f"\n  VARCHAR query+decode: {count} rows in {elapsed:.3f}s "
            f"({rate:,.0f} rows/s)"
        )
        assert count == ROW_COUNT
