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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
QuestDB Integration Tests for COSMOS Data Type Mapping.

These tests verify that all COSMOS data types can be stored and retrieved
from QuestDB with proper type conversion and round-trip fidelity.

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: pytest tests/test_questdb_integration.py -v
    3. Stop QuestDB: docker compose -f docker-compose.test.yml down
"""

import base64
import json
import math
import time
import pytest
import numpy as np
from questdb.ingress import TimestampNanos

from conftest import requires_questdb


# =============================================================================
# COSMOS Data Type to QuestDB Type Mapping Reference
# =============================================================================
#
# COSMOS Type | Bit Size      | QuestDB Type | Notes
# ------------|---------------|--------------|------------------------------------
# INT         | 8             | int          | Signed byte fits in 32-bit int
# INT         | 16            | int          | Signed short fits in 32-bit int
# INT         | 32            | int          | Direct mapping (min value is NULL)
# INT         | 64            | long         | Direct mapping (min value is NULL)
# INT         | 3 (bitfield)  | int          | Small bitfields fit in int
# INT         | 13 (bitfield) | int          | Medium bitfields fit in int
# UINT        | 8             | int          | Unsigned byte fits in signed int
# UINT        | 16            | int          | Unsigned short fits in signed int
# UINT        | 32            | long         | 33 bits needed for full range
# UINT        | 64            | varchar      | Exceeds signed long range
# UINT        | 3 (bitfield)  | int          | Small bitfields (0-7) fit in int
# UINT        | 13 (bitfield) | int          | Medium bitfields (0-8191) fit in int
# FLOAT       | 32            | float        | IEEE 754 single precision
# FLOAT       | 64            | double       | IEEE 754 double precision
# STRING      | var           | varchar      | Variable-length text
# BLOCK       | var           | varchar      | Base64-encoded binary
# DERIVED     | var           | varchar      | JSON-serialized (unpredictable type)
# BOOL        | N/A           | boolean      | Native boolean type
# ARRAY       | var           | double[]     | Numeric arrays only; else JSON
# OBJECT      | var           | varchar      | JSON-serialized
# ANY         | var           | varchar      | JSON-serialized (type varies)
#
# IMPORTANT LIMITATIONS:
# - QuestDB does NOT support IEEE 754 special values (Infinity, -Infinity, NaN)
# - These values are stored as NULL when ingested
# - Integer MIN_VALUE is used as NULL sentinel (avoid storing min values)
#
# =============================================================================


@requires_questdb
class TestIntSignedTypes:
    """Tests for COSMOS INT (signed integer) type storage and retrieval."""

    def test_int8_standard(self, questdb_client, clean_table, wait_for_data):
        """INT 8-bit (-128 to 127) round-trips correctly."""
        table_name = clean_table("TEST__INT8_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Full range including edge cases
        test_values = [-128, -64, -1, 0, 1, 64, 127]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_int16_standard(self, questdb_client, clean_table, wait_for_data):
        """INT 16-bit (-32768 to 32767) round-trips correctly."""
        table_name = clean_table("TEST__INT16_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_values = [-32768, -16384, -1, 0, 1, 16384, 32767]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_int32_standard(self, questdb_client, clean_table, wait_for_data):
        """INT 32-bit round-trips correctly, avoiding QuestDB NULL sentinel."""
        table_name = clean_table("TEST__INT32_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Note: QuestDB uses Integer.MIN_VALUE (-2147483648) as NULL
        # So we test -2147483647 as the minimum safe value
        test_values = [-2147483647, -1073741824, -1, 0, 1, 1073741824, 2147483647]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_int64_standard(self, questdb_client, clean_table, wait_for_data):
        """INT 64-bit round-trips correctly in QuestDB long type."""
        table_name = clean_table("TEST__INT64_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE long
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Note: QuestDB uses Long.MIN_VALUE as NULL
        test_values = [-9223372036854775807, -4611686018427387904, -1, 0, 1, 4611686018427387904, 9223372036854775807]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_int3_bitfield(self, questdb_client, clean_table, wait_for_data):
        """INT 3-bit bitfield (-4 to 3) round-trips correctly."""
        table_name = clean_table("TEST__INT3_BITFIELD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # 3-bit signed: -4 to 3
        test_values = [-4, -2, -1, 0, 1, 2, 3]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_int13_bitfield(self, questdb_client, clean_table, wait_for_data):
        """INT 13-bit bitfield (-4096 to 4095) round-trips correctly."""
        table_name = clean_table("TEST__INT13_BITFIELD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # 13-bit signed: -4096 to 4095
        test_values = [-4096, -2048, -1, 0, 1, 2048, 4095]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values


@requires_questdb
class TestUintUnsignedTypes:
    """Tests for COSMOS UINT (unsigned integer) type storage and retrieval."""

    def test_uint8_standard(self, questdb_client, clean_table, wait_for_data):
        """UINT 8-bit (0 to 255) stored as int round-trips correctly."""
        table_name = clean_table("TEST__UINT8_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_values = [0, 1, 64, 127, 128, 192, 255]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_uint16_standard(self, questdb_client, clean_table, wait_for_data):
        """UINT 16-bit (0 to 65535) stored as int round-trips correctly."""
        table_name = clean_table("TEST__UINT16_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_values = [0, 1, 16384, 32767, 32768, 49152, 65535]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_uint32_standard(self, questdb_client, clean_table, wait_for_data):
        """UINT 32-bit (0 to 4294967295) stored as long round-trips correctly."""
        table_name = clean_table("TEST__UINT32_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE long
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_values = [0, 1, 1073741824, 2147483647, 2147483648, 3221225472, 4294967295]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_uint64_standard_as_string(self, questdb_client, clean_table, wait_for_data):
        """UINT 64-bit values exceeding long range stored as varchar."""
        table_name = clean_table("TEST__UINT64_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Full UINT64 range - stored as strings to preserve precision
        test_values = [
            "0",
            "1",
            "4611686018427387904",
            "9223372036854775807",  # Max signed long
            "9223372036854775808",  # One past max signed long
            "13835058055282163712",
            "18446744073709551615",  # Max UINT64
        ]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_uint64_that_fits_in_long(self, questdb_client, clean_table, wait_for_data):
        """UINT 64-bit values that fit in signed long can use long type."""
        table_name = clean_table("TEST__UINT64_FITS_LONG")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE long
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Values that fit in signed long (0 to 2^63-1)
        test_values = [0, 1, 4611686018427387904, 9223372036854775807]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_uint3_bitfield(self, questdb_client, clean_table, wait_for_data):
        """UINT 3-bit bitfield (0 to 7) round-trips correctly."""
        table_name = clean_table("TEST__UINT3_BITFIELD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # 3-bit unsigned: 0 to 7
        test_values = [0, 1, 2, 3, 4, 5, 6, 7]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_uint13_bitfield(self, questdb_client, clean_table, wait_for_data):
        """UINT 13-bit bitfield (0 to 8191) round-trips correctly."""
        table_name = clean_table("TEST__UINT13_BITFIELD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE int
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # 13-bit unsigned: 0 to 8191
        test_values = [0, 1, 1024, 4096, 6144, 8190, 8191]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values


@requires_questdb
class TestFloatTypes:
    """Tests for COSMOS FLOAT type storage and retrieval."""

    def test_float32_standard(self, questdb_client, clean_table, wait_for_data):
        """FLOAT 32-bit (single precision) round-trips correctly."""
        table_name = clean_table("TEST__FLOAT32_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE float
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Float32 edge cases and typical values
        test_values = [
            -3.4028235e38,  # Near min
            -1.0,
            -1.17549435e-38,  # Near negative min normal
            0.0,
            1.17549435e-38,  # Near positive min normal
            1.0,
            3.4028235e38,  # Near max
        ]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": float(val)}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        # Compare with tolerance for float32 precision (~7 decimal digits)
        for expected, actual in zip(test_values, results):
            if expected == 0.0:
                assert actual == 0.0
            else:
                assert abs(expected - actual) < abs(expected) * 1e-6

    def test_float64_standard(self, questdb_client, clean_table, wait_for_data):
        """FLOAT 64-bit (double precision) round-trips correctly."""
        table_name = clean_table("TEST__FLOAT64_STANDARD")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE double
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Float64 edge cases and typical values
        test_values = [
            -1.7976931348623157e308,  # Near min
            -1.0,
            -2.2250738585072014e-308,  # Near negative min normal
            0.0,
            2.2250738585072014e-308,  # Near positive min normal
            1.0,
            1.7976931348623157e308,  # Near max
        ]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        # Compare with tolerance for float64 precision (~15 decimal digits)
        for expected, actual in zip(test_values, results):
            if expected == 0.0:
                assert actual == 0.0
            else:
                assert abs(expected - actual) < abs(expected) * 1e-14

    def test_float_special_infinity_becomes_null(self, questdb_client, clean_table, wait_for_data):
        """Float infinity values become NULL in QuestDB (documented limitation)."""
        table_name = clean_table("TEST__FLOAT_INFINITY")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE double
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        ts = int(time.time() * 1e9)

        # Note: QuestDB does NOT support IEEE 754 infinity values
        # They get stored as NULL instead
        test_values = [float("inf"), float("-inf")]

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        # QuestDB limitation: Infinity values become NULL
        # This is important to document for COSMOS data migration
        assert results[0] is None, "QuestDB stores +Infinity as NULL"
        assert results[1] is None, "QuestDB stores -Infinity as NULL"

    def test_float_special_nan_becomes_null(self, questdb_client, clean_table, wait_for_data):
        """Float NaN values become NULL in QuestDB (documented limitation)."""
        table_name = clean_table("TEST__FLOAT_NAN")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE double
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        ts = int(time.time() * 1e9)

        # Note: QuestDB represents NULL internally as NaN for doubles
        # So storing NaN results in NULL on retrieval
        questdb_client.ingest.row(table_name, columns={"VALUE": float("nan")}, at=TimestampNanos(ts))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, 1)

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}"')
            result = cur.fetchone()[0]

        # QuestDB limitation: NaN values become NULL
        assert result is None, "QuestDB stores NaN as NULL"


@requires_questdb
class TestStringType:
    """Tests for COSMOS STRING type storage and retrieval."""

    def test_string_basic(self, questdb_client, clean_table, wait_for_data):
        """STRING basic values round-trip correctly."""
        table_name = clean_table("TEST__STRING_BASIC")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_values = [
            "",  # Empty string
            "hello",
            "Hello World!",
            "CONNECTED",  # Typical state value
            "0x1234ABCD",  # Hex string
        ]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values

    def test_string_special_chars(self, questdb_client, clean_table, wait_for_data):
        """STRING with special characters round-trips correctly."""
        table_name = clean_table("TEST__STRING_SPECIAL")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_values = [
            "with\nnewline",
            "with\ttab",
            'with "quotes"',
            "with 'apostrophe'",
            "unicode: \u00e9\u00e8\u00ea\u00eb",  # French accents
            "emoji: test",  # Keep simple for compatibility
        ]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values


@requires_questdb
class TestBlockType:
    """Tests for COSMOS BLOCK (binary) type storage and retrieval."""

    def test_block_binary_data(self, questdb_client, clean_table, wait_for_data):
        """BLOCK binary data stored as base64 round-trips correctly."""
        table_name = clean_table("TEST__BLOCK_BINARY")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Various binary test data
        test_binaries = [
            b"",  # Empty
            b"\x00",  # Single null byte
            b"\x00\x01\x02\x03",  # Sequence
            b"\xff\xfe\xfd",  # High bytes
            bytes(range(256)),  # All byte values
            b"ASCII text as bytes",  # Text as binary
        ]

        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_binaries):
            encoded = base64.b64encode(val).decode("ascii")
            questdb_client.ingest.row(table_name, columns={"VALUE": encoded}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_binaries))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [base64.b64decode(row[0]) for row in cur.fetchall()]

        assert results == test_binaries


@requires_questdb
class TestBoolType:
    """Tests for COSMOS BOOL type storage and retrieval."""

    def test_bool_native(self, questdb_client, clean_table, wait_for_data):
        """BOOL values stored as native boolean round-trip correctly."""
        table_name = clean_table("TEST__BOOL_NATIVE")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE boolean
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_values = [True, False, True, False]
        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": val}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [row[0] for row in cur.fetchall()]

        assert results == test_values


@requires_questdb
class TestArrayType:
    """Tests for COSMOS ARRAY type storage and retrieval."""

    def test_array_numeric_double(self, questdb_client, clean_table, wait_for_data):
        """Numeric arrays stored as double[] round-trip correctly."""
        table_name = clean_table("TEST__ARRAY_NUMERIC")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE double[]
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_arrays = [
            np.array([1.0, 2.0, 3.0, 4.0, 5.0], dtype=np.float64),
            np.array([-1.5, 0.0, 1.5], dtype=np.float64),
            np.array([1e10, 1e-10, 0.0], dtype=np.float64),
            np.array([100, 200, 300], dtype=np.float64),  # Integers stored as doubles
        ]

        ts = int(time.time() * 1e9)

        for i, arr in enumerate(test_arrays):
            questdb_client.ingest.row(table_name, columns={"VALUE": arr}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_arrays))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [np.array(row[0]) for row in cur.fetchall()]

        for expected, actual in zip(test_arrays, results):
            np.testing.assert_array_almost_equal(expected, actual)

    def test_array_integer_items(self, questdb_client, clean_table, wait_for_data):
        """Integer array items converted to double[] round-trip correctly."""
        table_name = clean_table("TEST__ARRAY_INT_ITEMS")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE double[]
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Integer arrays that need to be converted to double
        test_arrays = [
            [0, 1, 2, 3, 4],
            [-128, 0, 127],  # INT8 range
            [0, 255],  # UINT8 range
            [-32768, 32767],  # INT16 range
        ]

        ts = int(time.time() * 1e9)

        for i, arr in enumerate(test_arrays):
            np_arr = np.array(arr, dtype=np.float64)
            questdb_client.ingest.row(table_name, columns={"VALUE": np_arr}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_arrays))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [list(row[0]) for row in cur.fetchall()]

        for expected, actual in zip(test_arrays, results):
            assert [float(x) for x in expected] == actual

    def test_array_string_as_json(self, questdb_client, clean_table, wait_for_data):
        """String arrays stored as JSON varchar round-trip correctly."""
        table_name = clean_table("TEST__ARRAY_STRING")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_arrays = [
            ["a", "b", "c"],
            ["CONNECTED", "DISCONNECTED", "UNKNOWN"],
            ["hello", "world"],
        ]

        ts = int(time.time() * 1e9)

        for i, arr in enumerate(test_arrays):
            questdb_client.ingest.row(table_name, columns={"VALUE": json.dumps(arr)}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_arrays))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [json.loads(row[0]) for row in cur.fetchall()]

        assert results == test_arrays

    def test_array_bool_as_json(self, questdb_client, clean_table, wait_for_data):
        """Boolean arrays stored as JSON varchar round-trip correctly."""
        table_name = clean_table("TEST__ARRAY_BOOL")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_arrays = [
            [True, False, True],
            [False, False, False],
            [True, True],
        ]

        ts = int(time.time() * 1e9)

        for i, arr in enumerate(test_arrays):
            questdb_client.ingest.row(table_name, columns={"VALUE": json.dumps(arr)}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_arrays))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [json.loads(row[0]) for row in cur.fetchall()]

        assert results == test_arrays


@requires_questdb
class TestObjectType:
    """Tests for COSMOS OBJECT type storage and retrieval."""

    def test_object_simple(self, questdb_client, clean_table, wait_for_data):
        """Simple OBJECT values stored as JSON round-trip correctly."""
        table_name = clean_table("TEST__OBJECT_SIMPLE")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_objects = [
            {},  # Empty object
            {"key": "value"},
            {"name": "test", "count": 42},
            {"nested": {"inner": "value"}},
        ]

        ts = int(time.time() * 1e9)

        for i, obj in enumerate(test_objects):
            questdb_client.ingest.row(table_name, columns={"VALUE": json.dumps(obj)}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_objects))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [json.loads(row[0]) for row in cur.fetchall()]

        assert results == test_objects

    def test_object_complex(self, questdb_client, clean_table, wait_for_data):
        """Complex OBJECT values with mixed types round-trip correctly."""
        table_name = clean_table("TEST__OBJECT_COMPLEX")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        test_objects = [
            {"int": 42, "float": 3.14, "string": "hello", "bool": True, "null": None},
            {"array": [1, 2, 3], "nested": {"a": 1, "b": 2}},
            {"mixed_array": [1, "two", 3.0, True]},
        ]

        ts = int(time.time() * 1e9)

        for i, obj in enumerate(test_objects):
            questdb_client.ingest.row(table_name, columns={"VALUE": json.dumps(obj)}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_objects))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [json.loads(row[0]) for row in cur.fetchall()]

        assert results == test_objects


@requires_questdb
class TestAnyType:
    """Tests for COSMOS ANY type storage and retrieval."""

    def test_any_various_types(self, questdb_client, clean_table, wait_for_data):
        """ANY type with various value types stored as JSON round-trip correctly."""
        table_name = clean_table("TEST__ANY_VARIOUS")

        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    VALUE varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # ANY can be any type
        test_values = [
            123,  # Integer
            45.67,  # Float
            "string value",  # String
            True,  # Boolean
            None,  # Null
            [1, 2, 3],  # Array
            {"key": "value"},  # Object
        ]

        ts = int(time.time() * 1e9)

        for i, val in enumerate(test_values):
            questdb_client.ingest.row(table_name, columns={"VALUE": json.dumps(val)}, at=TimestampNanos(ts + i * 1000))
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, len(test_values))

        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT VALUE FROM "{table_name}" ORDER BY timestamp')
            results = [json.loads(row[0]) for row in cur.fetchall()]

        assert results == test_values


@requires_questdb
class TestQuestDBClientConversion:
    """Tests for QuestDBClient.convert_value() function."""

    def test_convert_large_int_clamps(self, questdb_client):
        """convert_value clamps integers exceeding long range."""
        # Value exceeding max signed long
        large_int = 2**63 + 1000
        converted, skip = questdb_client.convert_value(large_int, "test")
        assert not skip
        assert converted == 2**63 - 1

        # Value below min signed long
        small_int = -(2**63) - 1000
        converted, skip = questdb_client.convert_value(small_int, "test")
        assert not skip
        assert converted == -(2**63) + 1

    def test_convert_bytes_to_base64(self, questdb_client):
        """convert_value encodes bytes as base64."""
        test_bytes = b"\x00\x01\x02\xff"
        converted, skip = questdb_client.convert_value(test_bytes, "test")
        assert not skip
        assert converted == base64.b64encode(test_bytes).decode("ascii")

    def test_convert_numeric_list_to_numpy_array(self, questdb_client):
        """convert_value converts numeric lists to numpy arrays."""
        test_list = [1.0, 2.0, 3.0]
        converted, skip = questdb_client.convert_value(test_list, "test")
        assert not skip
        assert isinstance(converted, np.ndarray)
        np.testing.assert_array_equal(converted, np.array(test_list, dtype=np.float64))

    def test_convert_empty_list_to_json(self, questdb_client):
        """convert_value converts empty lists to JSON."""
        test_list = []
        converted, skip = questdb_client.convert_value(test_list, "test")
        assert not skip
        assert converted == "[]"

    def test_convert_non_numeric_list_to_json(self, questdb_client):
        """convert_value converts non-numeric lists to JSON."""
        test_list = ["a", "b", "c"]
        converted, skip = questdb_client.convert_value(test_list, "test")
        assert not skip
        assert converted == json.dumps(test_list)

    def test_convert_dict_to_json(self, questdb_client):
        """convert_value converts dicts to JSON."""
        test_dict = {"key": "value", "num": 42}
        converted, skip = questdb_client.convert_value(test_dict, "test")
        assert not skip
        assert converted == json.dumps(test_dict)


@requires_questdb
class TestEndToEndPacketRoundTrip:
    """End-to-end tests simulating full COSMOS packet storage and retrieval."""

    def test_health_status_packet_roundtrip(self, questdb_client, clean_table, wait_for_data):
        """Full HEALTH_STATUS packet with all item types round-trips correctly."""
        table_name = clean_table("INST__HEALTH_STATUS")

        # Create table matching typical COSMOS packet structure
        with questdb_client.query.cursor() as cur:
            cur.execute(
                f"""
                CREATE TABLE "{table_name}" (
                    timestamp timestamp,
                    CCSDSVER int,
                    CCSDSTYPE int,
                    CCSDSSHF boolean,
                    CCSDSAPID int,
                    CCSDSSEQFLAGS int,
                    CCSDSSEQCNT int,
                    CCSDSLENGTH int,
                    TIMESECONDS long,
                    TIMEUS int,
                    COLLECTS int,
                    DURATION double,
                    COLLECT_TYPE varchar,
                    TEMP1 double,
                    TEMP1__C double,
                    TEMP1__F varchar,
                    TEMP2 double,
                    TEMP3 double,
                    TEMP4 double,
                    GROUND1STATUS int,
                    GROUND1STATUS__C varchar,
                    ARY double[],
                    ASCIICMD varchar,
                    BLOCKTEST varchar
                ) TIMESTAMP(timestamp) PARTITION BY DAY
            """
            )

        # Simulated JSON packet data from a decom log
        packet_data = {
            "CCSDSVER": 0,
            "CCSDSTYPE": 0,
            "CCSDSSHF": False,
            "CCSDSAPID": 1,
            "CCSDSSEQFLAGS": 3,
            "CCSDSSEQCNT": 1234,
            "CCSDSLENGTH": 200,
            "TIMESECONDS": 1703030405,
            "TIMEUS": 123456,
            "COLLECTS": 100,
            "DURATION": 10.5,
            "COLLECT_TYPE": "NORMAL",
            "TEMP1": 2500,  # Raw ADC counts
            "TEMP1__C": 25.0,  # Converted to Celsius
            "TEMP1__F": "25.00 C",  # Formatted with units
            "TEMP2": 2600,
            "TEMP3": 2700,
            "TEMP4": 2800,
            "GROUND1STATUS": 0,
            "GROUND1STATUS__C": "CONNECTED",  # State conversion
            "ARY": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0],
            "ASCIICMD": "TEST COMMAND",
            "BLOCKTEST": base64.b64encode(b"\x00\x01\x02\x03").decode("ascii"),
        }

        ts = int(time.time() * 1e9)

        # Process through questdb_client like migration would
        columns = questdb_client.process_json_data(packet_data, table_name)
        questdb_client.write_row(table_name, columns, ts)
        questdb_client.flush()

        wait_for_data(questdb_client, table_name, 1)

        # Read back and verify
        with questdb_client.query.cursor() as cur:
            cur.execute(f'SELECT * FROM "{table_name}"')
            row = cur.fetchone()
            column_names = [desc[0] for desc in cur.description]

        result = dict(zip(column_names, row))

        # Verify all scalar fields
        assert result["CCSDSVER"] == packet_data["CCSDSVER"]
        assert result["CCSDSTYPE"] == packet_data["CCSDSTYPE"]
        assert result["CCSDSSHF"] == packet_data["CCSDSSHF"]
        assert result["CCSDSAPID"] == packet_data["CCSDSAPID"]
        assert result["CCSDSSEQFLAGS"] == packet_data["CCSDSSEQFLAGS"]
        assert result["CCSDSSEQCNT"] == packet_data["CCSDSSEQCNT"]
        assert result["COLLECTS"] == packet_data["COLLECTS"]
        assert result["DURATION"] == packet_data["DURATION"]
        assert result["COLLECT_TYPE"] == packet_data["COLLECT_TYPE"]
        assert result["TEMP1"] == packet_data["TEMP1"]
        assert result["TEMP1__C"] == packet_data["TEMP1__C"]
        assert result["TEMP1__F"] == packet_data["TEMP1__F"]
        assert result["GROUND1STATUS__C"] == packet_data["GROUND1STATUS__C"]

        # Verify array field
        np.testing.assert_array_almost_equal(result["ARY"], packet_data["ARY"])

        # Verify string and block fields
        assert result["ASCIICMD"] == packet_data["ASCIICMD"]
        assert result["BLOCKTEST"] == packet_data["BLOCKTEST"]
