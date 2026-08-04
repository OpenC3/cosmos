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
Integration tests for retain time (TTL) reconciliation in create_table.

QuestDB only accepts TTL in CREATE TABLE, so a table created before
CMD_DECOM_RETAIN_TIME / TLM_DECOM_RETAIN_TIME was set (or set to a different
value) keeps its original TTL unless it is explicitly ALTERed. These tests
verify create_table issues ALTER TABLE ... SET TTL for existing tables.

They also pin down the QuestDB behaviors the implementation depends on:
- tables() reports TTL normalized to the largest evenly dividing unit
  (48 HOUR -> 2 DAY, 7 DAY -> 1 WEEK)
- TTL must be an integer multiple of the partition size (PARTITION BY DAY),
  so sub-day retain times are rounded up to 1 DAY
- TTL 0 removes the TTL

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: uv run pytest ../test/integration/tsdb/python/test_table_ttl.py -v
    3. Stop QuestDB: docker compose -f docker-compose.test.yml down
"""

import os
import sys
import time

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

PACKET_DEF = {"items": [{"name": "VALUE", "data_type": "INT", "bit_size": 32}]}


def _get_ttl(client, table_name):
    """Query QuestDB for the TTL currently reported for a table."""
    with client.query.cursor() as cur:
        cur.execute(
            "SELECT ttlValue, ttlUnit FROM tables() WHERE table_name = %s",
            (table_name,),
        )
        row = cur.fetchone()
    return (int(row[0]), str(row[1]).upper()) if row else None


def _wait_for_ttl(client, table_name, expected, timeout=5.0):
    """Poll tables() until the TTL matches. QuestDB applies ALTER asynchronously."""
    deadline = time.time() + timeout
    ttl = None
    while time.time() < deadline:
        ttl = _get_ttl(client, table_name)
        if ttl == expected:
            return ttl
        time.sleep(0.1)
    return ttl


@requires_questdb
class TestRetainTimeNormalization:
    """_normalize_retain_time matches how QuestDB reports TTL in tables()."""

    def test_normalizes_to_questdb_units(self, questdb_client):
        assert questdb_client._normalize_retain_time("30d") == (30, "DAY")
        assert questdb_client._normalize_retain_time("48h") == (2, "DAY")
        assert questdb_client._normalize_retain_time("24h") == (1, "DAY")
        assert questdb_client._normalize_retain_time("7d") == (1, "WEEK")
        assert questdb_client._normalize_retain_time("2w") == (2, "WEEK")
        assert questdb_client._normalize_retain_time("6M") == (6, "MONTH")
        assert questdb_client._normalize_retain_time("1y") == (1, "YEAR")

    def test_rounds_sub_partition_hours_up_to_one_day(self, questdb_client):
        # Tables are PARTITION BY DAY and QuestDB rejects a TTL that isn't an
        # integer multiple of the partition size
        assert questdb_client._normalize_retain_time("1h") == (1, "DAY")
        assert questdb_client._normalize_retain_time("6h") == (1, "DAY")
        assert questdb_client._normalize_retain_time("25h") == (1, "DAY")

    def test_returns_none_for_invalid(self, questdb_client):
        assert questdb_client._normalize_retain_time(None) is None
        assert questdb_client._normalize_retain_time("") is None
        assert questdb_client._normalize_retain_time("30") is None
        assert questdb_client._normalize_retain_time("30s") is None
        assert questdb_client._normalize_retain_time("thirty_days") is None
        assert questdb_client._normalize_retain_time("0d") is None


@requires_questdb
class TestCreateTableTtl:
    """TTL is applied on create and reconciled on subsequent create_table calls."""

    def test_sets_ttl_on_create(self, questdb_client, clean_table):
        target = "TBLTTL"
        packet = "ON_CREATE"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")

        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="30d")
        assert _get_ttl(questdb_client, table_name) == (30, "DAY")

    def test_sub_day_retain_time_does_not_fail_create(self, questdb_client, clean_table):
        # QuestDB rejects "TTL 1 HOUR" on a DAY partitioned table outright, which
        # previously failed the whole CREATE TABLE
        target = "TBLTTL"
        packet = "SUB_DAY"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")

        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="1h")
        assert _get_ttl(questdb_client, table_name) == (1, "DAY")

    def test_adds_ttl_to_existing_table(self, questdb_client, clean_table):
        target = "TBLTTL"
        packet = "ADDED"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")

        # Table created before any retain time was configured
        questdb_client.create_table(target, packet, PACKET_DEF)
        assert _get_ttl(questdb_client, table_name) == (0, "HOUR")

        # Restart with a retain time configured in plugin.txt
        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="7d")
        assert _wait_for_ttl(questdb_client, table_name, (1, "WEEK")) == (1, "WEEK")

    def test_changes_ttl_on_existing_table(self, questdb_client, clean_table):
        target = "TBLTTL"
        packet = "CHANGED"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")

        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="30d")
        assert _get_ttl(questdb_client, table_name) == (30, "DAY")

        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="2d")
        assert _wait_for_ttl(questdb_client, table_name, (2, "DAY")) == (2, "DAY")

    def test_removes_ttl_when_retain_time_cleared(self, questdb_client, clean_table):
        target = "TBLTTL"
        packet = "REMOVED"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")

        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="30d")
        assert _get_ttl(questdb_client, table_name) == (30, "DAY")

        questdb_client.create_table(target, packet, PACKET_DEF)
        assert _wait_for_ttl(questdb_client, table_name, (0, "HOUR")) == (0, "HOUR")

    def test_leaves_ttl_alone_for_invalid_retain_time(self, questdb_client, clean_table):
        target = "TBLTTL"
        packet = "INVALID"
        table_name = clean_table(f"DEFAULT__TLM__{target}__{packet}")

        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="30d")
        assert _get_ttl(questdb_client, table_name) == (30, "DAY")

        # A bad value should warn, not silently drop the existing retention
        questdb_client.create_table(target, packet, PACKET_DEF, retain_time="bogus")
        assert _get_ttl(questdb_client, table_name) == (30, "DAY")
