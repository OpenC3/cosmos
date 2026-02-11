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
Integration tests for handle_ingress_error value casting.

Since create_table proactively reconciles column types on startup, IngressErrors
should be rare in normal operation. When they do occur, handle_ingress_error casts
the value to fit the existing column type rather than altering the schema.

These tests bypass create_table's proactive ALTER by writing mismatched values
directly to a table, triggering IngressError, and verifying that
handle_ingress_error correctly casts the value and retries.

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: poetry run pytest python/test_handle_ingress_error.py -v
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
from questdb.ingress import IngressError


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


def _write_with_error_handling(client, table_name, columns, ts):
    """Write a row, delegating to handle_ingress_error on IngressError.

    Returns:
        Tuple of (success, was_handled) where was_handled indicates
        handle_ingress_error was invoked.
    """
    try:
        client.write_row(table_name, columns, ts)
        client.flush()
        return True, False
    except IngressError as error:
        result = client.handle_ingress_error(error, table_name, columns, ts)
        if result:
            client.flush()
        return result, True


@requires_questdb
class TestCastFloatToIntColumn:
    """Writing a float value to a LONG column: handle_ingress_error casts to int."""

    def test_float_cast_to_int(self, questdb_client, clean_table, wait_for_data):
        target = "CAST"
        packet = "FLOAT_TO_INT"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        # Create table as INT 32 (LONG column)
        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"

        # Write a float value directly — ILP rejects float -> LONG
        columns = {"VALUE": 3.14, "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        assert was_handled is True, "Float -> LONG should trigger IngressError"
        wait_for_data(questdb_client, table_name, 1)

        # Column type must NOT have changed
        assert _get_column_type(questdb_client, table_name) == "LONG"

        # Value should have been cast: int(3.14) = 3
        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] == 3

    def test_negative_float_cast_to_int(
        self, questdb_client, clean_table, wait_for_data
    ):
        target = "CAST"
        packet = "NEG_FLOAT_TO_INT"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )

        columns = {"VALUE": -7.9, "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        assert was_handled is True
        wait_for_data(questdb_client, table_name, 1)

        assert _get_column_type(questdb_client, table_name) == "LONG"

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] == -7  # int(-7.9) = -7


@requires_questdb
class TestCastStringToIntColumn:
    """Writing a string value to a LONG column: handle_ingress_error casts numeric strings to int."""

    def test_numeric_string_cast_to_int(
        self, questdb_client, clean_table, wait_for_data
    ):
        target = "CAST"
        packet = "NUMSTR_TO_INT"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"

        # Write a numeric string to a LONG column
        columns = {"VALUE": "42", "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        assert was_handled is True, "String -> LONG should trigger IngressError"
        wait_for_data(questdb_client, table_name, 1)

        assert _get_column_type(questdb_client, table_name) == "LONG"

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] == 42

    def test_nonnumeric_string_becomes_null(
        self, questdb_client, clean_table, wait_for_data
    ):
        """Non-numeric string can't be cast to int, stored as NULL."""
        target = "CAST"
        packet = "BADSTR_TO_INT"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )

        # Write a non-numeric string — can't cast to int
        columns = {"VALUE": "hello", "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        assert was_handled is True
        wait_for_data(questdb_client, table_name, 1)

        assert _get_column_type(questdb_client, table_name) == "LONG"

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] is None  # "hello" can't cast to int → NULL


@requires_questdb
class TestCastStringToFloatColumn:
    """Writing a string value to a DOUBLE column: handle_ingress_error casts numeric strings to float."""

    def test_numeric_string_cast_to_float(
        self, questdb_client, clean_table, wait_for_data
    ):
        target = "CAST"
        packet = "NUMSTR_TO_FLOAT"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(
            target, packet, _make_packet_def("FLOAT", bit_size=64)
        )
        assert _get_column_type(questdb_client, table_name) == "DOUBLE"

        columns = {"VALUE": "3.14", "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        assert was_handled is True, "String -> DOUBLE should trigger IngressError"
        wait_for_data(questdb_client, table_name, 1)

        assert _get_column_type(questdb_client, table_name) == "DOUBLE"

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert abs(rows[0] - 3.14) < 1e-10

    def test_nonnumeric_string_becomes_null_in_float_column(
        self, questdb_client, clean_table, wait_for_data
    ):
        target = "CAST"
        packet = "BADSTR_TO_FLOAT"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(
            target, packet, _make_packet_def("FLOAT", bit_size=64)
        )

        columns = {"VALUE": "not_a_number", "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        assert was_handled is True
        wait_for_data(questdb_client, table_name, 1)

        assert _get_column_type(questdb_client, table_name) == "DOUBLE"

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] is None


@requires_questdb
class TestCastToStringColumn:
    """Writing non-string values to a VARCHAR column: handle_ingress_error casts to str."""

    def test_int_cast_to_string(self, questdb_client, clean_table, wait_for_data):
        target = "CAST"
        packet = "INT_TO_STRING"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(target, packet, _make_packet_def("STRING"))
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        # Write an int value to a VARCHAR column
        columns = {"VALUE": 42, "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        # ILP may or may not auto-cast int to string — either path is acceptable
        wait_for_data(questdb_client, table_name, 1)

        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] == "42" or rows[0] == 42  # str("42") if cast, or 42 if auto-cast

    def test_float_cast_to_string(self, questdb_client, clean_table, wait_for_data):
        target = "CAST"
        packet = "FLOAT_TO_STRING"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(target, packet, _make_packet_def("STRING"))
        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        columns = {"VALUE": 3.14, "RECEIVED_COUNT": 0}
        success, was_handled = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        wait_for_data(questdb_client, table_name, 1)

        assert _get_column_type(questdb_client, table_name) == "VARCHAR"

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT "VALUE" FROM "{table_name}"')
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 1
        assert rows[0] == "3.14" or abs(float(rows[0]) - 3.14) < 1e-10


@requires_questdb
class TestColumnTypeUnchanged:
    """Verify that handle_ingress_error never alters column types."""

    def test_column_type_preserved_after_multiple_casts(
        self, questdb_client, clean_table, wait_for_data
    ):
        """Write multiple mismatched values — column type must stay LONG throughout."""
        target = "CAST"
        packet = "TYPE_PRESERVED"
        table_name = clean_table(f"TLM__{target}__{packet}")
        base_ts = int(time.time() * 1e9)

        questdb_client.create_table(
            target, packet, _make_packet_def("INT", bit_size=32)
        )
        assert _get_column_type(questdb_client, table_name) == "LONG"

        # Write a float — should be cast to int
        columns = {"VALUE": 1.5, "RECEIVED_COUNT": 0}
        success, _ = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts
        )
        assert success is True
        wait_for_data(questdb_client, table_name, 1)
        assert _get_column_type(questdb_client, table_name) == "LONG"

        # Write a numeric string — should be cast to int
        columns = {"VALUE": "99", "RECEIVED_COUNT": 0}
        success, _ = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts + 1_000_000_000
        )
        assert success is True
        wait_for_data(questdb_client, table_name, 2)
        assert _get_column_type(questdb_client, table_name) == "LONG"

        # Write a non-numeric string — should become NULL
        columns = {"VALUE": "abc", "RECEIVED_COUNT": 0}
        success, _ = _write_with_error_handling(
            questdb_client, table_name, columns, base_ts + 2_000_000_000
        )
        assert success is True
        wait_for_data(questdb_client, table_name, 3)
        assert _get_column_type(questdb_client, table_name) == "LONG"

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f'SELECT "VALUE" FROM "{table_name}" ORDER BY PACKET_TIMESECONDS'
            )
            rows = [r[0] for r in cur.fetchall()]
        assert len(rows) == 3
        assert rows[0] == 1  # int(1.5) = 1
        assert rows[1] == 99  # int("99") = 99
        assert rows[2] is None  # "abc" can't cast → NULL


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
