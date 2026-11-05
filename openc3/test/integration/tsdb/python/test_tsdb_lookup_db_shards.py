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
Integration tests for CvtModel.tsdb_lookup across db_shards.

Each db_shard is a separate QuestDB so a lookup with targets on different
db_shards runs separate queries. The results must match what ASOF JOIN returns
when every table is on a single db_shard, so each lookup is also compared against
the same tables written to a single db_shard.

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
       (starts questdb and questdb-shard1)
    2. Run tests: uv run pytest ../test/integration/tsdb/python/test_tsdb_lookup_db_shards.py -v
    3. Stop QuestDB: docker compose -f docker-compose.test.yml down
"""

import os
import sys
import time
from datetime import datetime, timezone
from unittest.mock import patch

import pytest


# Add openc3 python path for imports
# Path: openc3/test/integration/tsdb/python -> openc3/python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "python"))

from conftest import db_shard_ports, requires_questdb_shards

from openc3.models.cvt_model import CvtModel
from openc3.utilities.questdb_client import QuestDBClient


PACKET_DEF = {"items": [{"name": "VALUE", "data_type": "INT", "bit_size": 32}]}
# Target name => db_shard. The SINGLE targets hold the same tables as the SHARD
# targets but all on db_shard 0 so they are queried with a single ASOF JOIN.
DB_SHARDS = {"SHARD_A": 0, "SHARD_B": 1, "SINGLE_A": 0, "SINGLE_B": 0}
SINGLE = {"SHARD_A": "SINGLE_A", "SHARD_B": "SINGLE_B"}
# (target_name, packet_name) => [(seconds after the base time, VALUE)]
TABLES = {
    ("SHARD_A", "PKT"): [(0, 0), (2, 2), (4, 4)],
    # The row at 6 seconds is after the end of the lookup range
    ("SHARD_B", "PKT"): [(1, 1), (3, 3), (6, 6)],
    # Only a row before the start of the lookup range
    ("SHARD_B", "EARLY"): [(-1, 10)],
    # A row after the last SHARD_B PKT row in the lookup range
    ("SHARD_B", "LATER"): [(3.5, 35)],
}
# Lists of items as (target_name, packet_name)
LOOKUPS = [
    [("SHARD_A", "PKT"), ("SHARD_B", "PKT")],
    [("SHARD_B", "PKT"), ("SHARD_A", "PKT")],
    [("SHARD_A", "PKT"), ("SHARD_B", "EARLY")],
    [("SHARD_A", "PKT"), ("SHARD_B", "PKT"), ("SHARD_B", "LATER")],
    [("SHARD_A", "PKT"), ("SHARD_B", "LATER"), ("SHARD_B", "EARLY"), ("SHARD_A", "PKT")],
    [("SHARD_B", "LATER"), ("SHARD_A", "PKT"), ("SHARD_B", "PKT")],
]
# (start_time, end_time) as seconds after the base time
WINDOWS = [(0, 5), (-2, 10), (3, 4), (5, None), (7, None), (3.5, None)]


def ts_to_iso(ts_ns):
    return datetime.fromtimestamp(ts_ns / 1e9, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def create_query_connection(original):
    def create(db_shard=0, **kwargs):
        kwargs.setdefault("port", db_shard_ports(db_shard).get("query_port"))
        return original(db_shard=db_shard, **kwargs)

    return staticmethod(create)


@requires_questdb_shards
class TestTsdbLookupDbShards:
    @pytest.fixture(autouse=True)
    def db_shards(self, wait_for_data):
        original = QuestDBClient._create_query_connection
        with (
            patch.object(QuestDBClient, "_create_query_connection", create_query_connection(original)),
            patch.object(
                QuestDBClient, "db_shard_for_target", side_effect=lambda target_name, scope: DB_SHARDS[target_name]
            ),
            patch("openc3.models.target_model.TargetModel") as target_model,
        ):
            target_model.packet.return_value = PACKET_DEF
            QuestDBClient.disconnect()
            self.base_ts = self.write_rows(wait_for_data)
            yield
            QuestDBClient.disconnect()
            self.drop_tables()

    def tables(self):
        """Every table written as (target_name, packet_name, rows) including the SINGLE copies"""
        for (target_name, packet_name), rows in TABLES.items():
            yield target_name, packet_name, rows
            yield SINGLE[target_name], packet_name, rows

    def write_rows(self, wait_for_data):
        # A whole second so start_time converts exactly and includes the first row
        base_ts = int(time.time()) * 1_000_000_000
        for target_name, packet_name, rows in self.tables():
            db_shard = DB_SHARDS[target_name]
            client = QuestDBClient(db_shard=db_shard, **db_shard_ports(db_shard))
            client.connect_ingest()
            client.connect_query()
            table_name, _ = client.sanitize_table_name(target_name, packet_name)
            with client.query.cursor() as cur:
                cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
            client.create_table(target_name, packet_name, PACKET_DEF)
            for i, (seconds, value) in enumerate(rows):
                columns = client.process_json_data({"VALUE": value}, table_name)
                columns["RECEIVED_COUNT"] = i
                row_ts = base_ts + int(seconds * 1_000_000_000)
                client.write_row(table_name, columns, row_ts, rx_timestamp_ns=row_ts)
            client.flush()
            assert wait_for_data(client, table_name, len(rows)) == len(rows)
            client.close()
        return base_ts

    def drop_tables(self):
        for target_name, packet_name, _ in self.tables():
            db_shard = DB_SHARDS[target_name]
            client = QuestDBClient(db_shard=db_shard, **db_shard_ports(db_shard))
            client.connect_query()
            table_name, _ = client.sanitize_table_name(target_name, packet_name)
            with client.query.cursor() as cur:
                cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
            client.close()

    def iso(self, seconds):
        return ts_to_iso(self.base_ts + int(seconds * 1_000_000_000))

    def lookup(self, packets, start, end=None):
        items = [(target_name, packet_name, "VALUE", "RAW", False) for target_name, packet_name in packets]
        return CvtModel.tsdb_lookup(
            items, start_time=self.iso(start), end_time=self.iso(end) if end is not None else None
        )

    def test_aligns_the_other_db_shard_to_the_first_by_packet_time(self):
        assert self.lookup([("SHARD_A", "PKT"), ("SHARD_B", "PKT")], 0, 5) == [
            # SHARD_B has no row at or before 0 seconds
            [[0, None], [None, None]],
            [[2, None], [1, None]],
            [[4, None], [3, None]],
        ]

    def test_aligns_the_other_db_shard_row_before_start_time(self):
        # Like ASOF JOIN the SHARD_B row at 1 second aligns to the first SHARD_A row at 2 seconds
        assert self.lookup([("SHARD_A", "PKT"), ("SHARD_B", "PKT")], 2, 5) == [
            [[2, None], [1, None]],
            [[4, None], [3, None]],
        ]

    def test_drives_the_rows_from_the_db_shard_of_the_first_item(self):
        assert self.lookup([("SHARD_B", "PKT"), ("SHARD_A", "PKT")], 0, 5) == [
            [[1, None], [0, None]],
            [[3, None], [2, None]],
        ]

    def test_carries_forward_a_row_before_start_time(self):
        assert self.lookup([("SHARD_A", "PKT"), ("SHARD_B", "EARLY")], 0, 5) == [
            [[0, None], [10, None]],
            [[2, None], [10, None]],
            [[4, None], [10, None]],
        ]

    def test_aligns_each_packet_on_a_db_shard_independently(self):
        # SHARD_B LATER is aligned to SHARD_A at 4 seconds, not SHARD_B PKT at 3 seconds
        assert self.lookup([("SHARD_A", "PKT"), ("SHARD_B", "PKT"), ("SHARD_B", "LATER")], 0, 5) == [
            [[0, None], [None, None], [None, None]],
            [[2, None], [1, None], [None, None]],
            [[4, None], [3, None], [35, None]],
        ]
        assert self.lookup([("SHARD_A", "PKT"), ("SHARD_B", "PKT"), ("SHARD_B", "LATER")], 5) == [
            [4, None],
            [3, None],
            [35, None],
        ]

    def test_returns_the_last_row_at_or_before_the_driving_row(self):
        # SHARD_A drives at 4 seconds so SHARD_B returns its row at 3 seconds, not 6 seconds
        assert self.lookup([("SHARD_A", "PKT"), ("SHARD_B", "PKT")], 7) == [[4, None], [3, None]]

    @pytest.mark.parametrize("packets", LOOKUPS)
    @pytest.mark.parametrize("window", WINDOWS)
    def test_matches_a_single_db_shard_lookup(self, packets, window):
        single = [(SINGLE[target_name], packet_name) for target_name, packet_name in packets]
        assert self.lookup(packets, *window) == self.lookup(single, *window)
