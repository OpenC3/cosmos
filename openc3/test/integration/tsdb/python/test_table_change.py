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
Integration tests for proactive column type changes in create_table.

These tests verify that when a COSMOS user changes a packet item's data type
and re-installs a plugin, create_table detects the existing table's column
type mismatch and proactively issues ALTER TABLE ... ALTER COLUMN ... TYPE
to reconcile it. This avoids silent ILP auto-casting (e.g., large integers
losing precision when stored as doubles).

Each test:
1. Creates a table with type A and writes a value
2. Simulates a microservice restart with a new packet definition (type B)
3. Verifies that create_table proactively ALTERed the column
4. Writes a value with the new type and verifies correct storage/retrieval

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: poetry run pytest python/test_table_change.py -v
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


def _restart_and_create(client, target, packet, packet_def):
    """Simulate a microservice restart: reset metadata and call create_table."""
    client.json_columns = {}
    client.varchar_columns = {}
    client.float_bit_sizes = {}
    return client.create_table(target, packet, packet_def)


def _write_value(client, table_name, value, ts):
    """Write a single VALUE row via ILP."""
    columns = client.process_json_data({"VALUE": value}, table_name)
    columns["RECEIVED_COUNT"] = 0
    client.write_row(table_name, columns, ts)
    client.flush()


@requires_questdb
class TestIntToFloat:
    """INT 32 (LONG) -> FLOAT 64 (DOUBLE)."""

    def test_int_to_float(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "INT_TO_FLOAT"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Create as INT 32 (long), write an integer
        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"
        _write_value(questdb_client, table_name, 42, base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart with FLOAT 64 — create_table should ALTER LONG -> DOUBLE
        _restart_and_create(
            questdb_client, target, packet, _make_packet_def("FLOAT", bit_size=64)
        )
        assert _get_column_type(questdb_client, table_name) == "DOUBLE"

        _write_value(questdb_client, table_name, 3.14, base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        assert rows[0] == 42.0  # Original int widened to double
        assert abs(rows[1] - 3.14) < 1e-10


@requires_questdb
class TestIntToString:
    """INT 32 (LONG) -> STRING (VARCHAR)."""

    def test_int_to_string(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "INT_TO_STRING"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Create as INT 32 (long), write an integer
        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"
        _write_value(questdb_client, table_name, 42, base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart with STRING — create_table should ALTER LONG -> VARCHAR
        _restart_and_create(questdb_client, target, packet, _make_packet_def("STRING"))
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        _write_value(questdb_client, table_name, "hello", base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        assert rows[0] == "42"  # Original int converted to string representation
        assert rows[1] == "hello"


@requires_questdb
class TestFloatToString:
    """FLOAT 64 (DOUBLE) -> STRING (VARCHAR)."""

    def test_float_to_string(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "FLOAT_TO_STRING"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Create as FLOAT 64 (double), write a float
        questdb_client.create_table(
            target, packet, _make_packet_def("FLOAT", bit_size=64)
        )
        assert _get_column_type(questdb_client, table_name) == "DOUBLE"
        _write_value(questdb_client, table_name, 3.14, base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart with STRING — create_table should ALTER DOUBLE -> VARCHAR
        _restart_and_create(questdb_client, target, packet, _make_packet_def("STRING"))
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        _write_value(questdb_client, table_name, "world", base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        assert rows[0] == "3.14"  # Original double converted to string representation
        assert rows[1] == "world"


@requires_questdb
class TestFloatToInt:
    """FLOAT 64 (DOUBLE) -> INT 32 (LONG)."""

    def test_float_to_int(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "FLOAT_TO_INT"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Create as FLOAT 64 (double), write a float
        questdb_client.create_table(
            target, packet, _make_packet_def("FLOAT", bit_size=64)
        )
        assert _get_column_type(questdb_client, table_name) == "DOUBLE"
        _write_value(questdb_client, table_name, 3.14, base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart with INT 32 — create_table should ALTER DOUBLE -> LONG
        _restart_and_create(
            questdb_client, target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"

        _write_value(questdb_client, table_name, 100, base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        assert rows[0] == 3  # Original double truncated to long
        assert rows[1] == 100


@requires_questdb
class TestStringToInt:
    """STRING (VARCHAR) -> INT 32 (LONG)."""

    def test_string_to_int(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "STRING_TO_INT"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Create as STRING (varchar), write a numeric string
        questdb_client.create_table(target, packet, _make_packet_def("STRING"))
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"
        _write_value(questdb_client, table_name, "42", base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart with INT 32 — create_table should ALTER VARCHAR -> LONG
        _restart_and_create(
            questdb_client, target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"

        _write_value(questdb_client, table_name, 100, base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        assert rows[0] == 42  # Numeric string "42" survives as int
        assert rows[1] == 100


@requires_questdb
class TestStringToFloat:
    """STRING (VARCHAR) -> FLOAT 64 (DOUBLE)."""

    def test_string_to_float(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "STRING_TO_FLOAT"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Create as STRING (varchar), write a numeric string
        questdb_client.create_table(target, packet, _make_packet_def("STRING"))
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"
        _write_value(questdb_client, table_name, "3.14", base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart with FLOAT 64 — create_table should ALTER VARCHAR -> DOUBLE
        _restart_and_create(
            questdb_client, target, packet, _make_packet_def("FLOAT", bit_size=64)
        )
        assert _get_column_type(questdb_client, table_name) == "DOUBLE"

        _write_value(questdb_client, table_name, 2.718, base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        assert abs(rows[0] - 3.14) < 1e-10  # Numeric string "3.14" survives as double
        assert abs(rows[1] - 2.718) < 1e-10

@requires_questdb
class TestLargeUintUsesVarchar:
    """UINT > 64 bits should use VARCHAR instead of DECIMAL(20,0)."""

    def test_large_uint_stored_as_varchar(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "LARGE_UINT"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Create as UINT 88 — should use VARCHAR, not DECIMAL
        questdb_client.create_table(
            target, packet, _make_packet_def("UINT", bit_size=88)
        )
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        # Write a value that exceeds DECIMAL(20,0) capacity (27 digits)
        large_value = 2**88 - 1  # 309485009821345068724781055
        _write_value(questdb_client, table_name, large_value, base_ts)
        wait_for_data(questdb_client, table_name, 1)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] == str(large_value)


@requires_questdb
class TestLongToVarchar:
    """INT 32 (LONG) -> UINT 64 (VARCHAR).

    Verifies that upgrading a 32-bit integer column (LONG) to a 64-bit
    unsigned integer column (VARCHAR) works correctly via ALTER TABLE.
    """

    def test_long_to_varchar(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "LONG_TO_VARCHAR"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Create as INT 32 (long), write an integer
        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"
        _write_value(questdb_client, table_name, 42, base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart with UINT 64 — create_table should ALTER LONG -> VARCHAR
        _restart_and_create(
            questdb_client, target, packet, _make_packet_def("UINT", bit_size=64)
        )
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        large_64bit = 2**64 - 1  # 18446744073709551615
        _write_value(questdb_client, table_name, large_64bit, base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        assert rows[0] == "42"  # Original long converted to string representation
        assert rows[1] == str(large_64bit)


@requires_questdb
class TestLegacyDecimalMigratesToVarchar:
    """Legacy DECIMAL(20,0) columns migrate to VARCHAR on restart.

    We no longer create DECIMAL columns (≥64-bit integers use VARCHAR now),
    but legacy tables may still have them. QuestDB 9.3.5 fixed bug #6923,
    so create_table now ALTERs DECIMAL -> VARCHAR. This test verifies the
    migration and that previously-written values are preserved as strings.
    """

    def test_legacy_decimal_migrates_to_varchar(self, questdb_client, clean_table, wait_for_data):
        target = "TBLCHG"
        packet = "LEGACY_DECIMAL"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Phase A: Manually create a legacy table with DECIMAL(20,0) via SQL
        with questdb_client.query.cursor() as cur:
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
        assert _get_column_type(questdb_client, table_name) == "DECIMAL(20,0)"
        large_64bit = 2**64 - 1  # 18446744073709551615
        _write_value(questdb_client, table_name, large_64bit, base_ts)
        wait_for_data(questdb_client, table_name, 1)

        # Phase B: Restart — create_table should ALTER DECIMAL -> VARCHAR
        _restart_and_create(
            questdb_client, target, packet, _make_packet_def("UINT", bit_size=64)
        )
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        # New values ingest as strings against the VARCHAR column
        another_64bit = 2**63  # 9223372036854775808
        _write_value(questdb_client, table_name, another_64bit, base_ts + 1_000_000_000)
        wait_for_data(questdb_client, table_name, 2)

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 2
        # After ALTER TYPE, prior DECIMAL values come back as their string representation
        assert rows[0] == str(large_64bit)
        assert rows[1] == str(another_64bit)


@requires_questdb
class TestDecimalToVarcharBug:
    """Direct test of QuestDB ALTER DECIMAL -> VARCHAR.

    QuestDB bug https://github.com/questdb/questdb/issues/6923 was fixed in
    QuestDB 9.3.5. This test verifies the ALTER works so create_table can
    migrate legacy DECIMAL columns to VARCHAR.
    """

    def test_alter_decimal_to_varchar(self, questdb_client, clean_table):
        table_name = clean_table("DEFAULT__TLM__TBLCHG__DECIMAL_BUG")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'CREATE TABLE IF NOT EXISTS "{table_name}" ('
                f"PACKET_TIMESECONDS timestamp_ns, "
                f'"VALUE" DECIMAL(20, 0)'
                f") TIMESTAMP(PACKET_TIMESECONDS) PARTITION BY DAY"
            )
        assert _get_column_type(questdb_client, table_name) == "DECIMAL(20,0)"

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'ALTER TABLE "{table_name}" ALTER COLUMN "VALUE" TYPE varchar'
            )

        # QuestDB applies ALTER TYPE asynchronously; poll until visible
        deadline = time.time() + 5.0
        while time.time() < deadline:
            if _get_column_type(questdb_client, table_name) == "VARCHAR":
                break
            time.sleep(0.1)
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
