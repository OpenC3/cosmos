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
db_shards runs one query per db_shard. A range lookup must align those rows by
packet time (the way ASOF JOIN aligns tables within a db_shard) rather than by
row number.

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
# Target name => db_shard
DB_SHARDS = {"SHARD_A": 0, "SHARD_B": 1}
# Target name => [(seconds after the base time, VALUE)]
ROWS = {
    "SHARD_A": [(0, 0), (2, 2), (4, 4)],
    # The row at 6 seconds is after the end of the lookup range
    "SHARD_B": [(1, 1), (3, 3), (6, 6)],
}


def ts_to_iso(ts_ns):
    return datetime.fromtimestamp(ts_ns / 1e9, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def create_query_connection(original):
    def create(db_shard=0, **kwargs):
        with db_shard_ports(db_shard):
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

    def write_rows(self, wait_for_data):
        # A whole second so start_time converts exactly and includes the first row
        base_ts = int(time.time()) * 1_000_000_000
        for target_name, rows in ROWS.items():
            db_shard = DB_SHARDS[target_name]
            with db_shard_ports(db_shard):
                client = QuestDBClient(db_shard=db_shard)
                client.connect_ingest()
                client.connect_query()
                table_name, _ = client.sanitize_table_name(target_name, "PKT")
                with client.query.cursor() as cur:
                    cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
                client.create_table(target_name, "PKT", PACKET_DEF)
                for i, (seconds, value) in enumerate(rows):
                    columns = client.process_json_data({"VALUE": value}, table_name)
                    columns["RECEIVED_COUNT"] = i
                    row_ts = base_ts + seconds * 1_000_000_000
                    client.write_row(table_name, columns, row_ts, rx_timestamp_ns=row_ts)
                client.flush()
                assert wait_for_data(client, table_name, len(rows)) == len(rows)
                client.close()
        return base_ts

    def drop_tables(self):
        for target_name, db_shard in DB_SHARDS.items():
            with db_shard_ports(db_shard):
                client = QuestDBClient(db_shard=db_shard)
                client.connect_query()
                table_name, _ = client.sanitize_table_name(target_name, "PKT")
                with client.query.cursor() as cur:
                    cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
                client.close()

    def lookup(self, target_names, start_seconds=0):
        items = [(target_name, "PKT", "VALUE", "RAW", False) for target_name in target_names]
        return CvtModel.tsdb_lookup(
            items,
            start_time=ts_to_iso(self.base_ts + start_seconds * 1_000_000_000),
            end_time=ts_to_iso(self.base_ts + 5_000_000_000),
        )

    def test_aligns_the_other_db_shard_to_the_first_by_packet_time(self):
        assert self.lookup(["SHARD_A", "SHARD_B"]) == [
            # SHARD_B has no row at or before 0 seconds
            [[0, None], [None, None]],
            [[2, None], [1, None]],
            [[4, None], [3, None]],
        ]

    def test_aligns_the_other_db_shard_row_before_start_time(self):
        # Like ASOF JOIN the SHARD_B row at 1 second aligns to the first SHARD_A row at 2 seconds
        assert self.lookup(["SHARD_A", "SHARD_B"], start_seconds=2) == [
            [[2, None], [1, None]],
            [[4, None], [3, None]],
        ]

    def test_drives_the_rows_from_the_db_shard_of_the_first_item(self):
        assert self.lookup(["SHARD_B", "SHARD_A"]) == [
            [[1, None], [0, None]],
            [[3, None], [2, None]],
        ]

    def test_returns_the_last_row_before_start_time_from_each_db_shard(self):
        items = [("SHARD_A", "PKT", "VALUE", "RAW", False), ("SHARD_B", "PKT", "VALUE", "RAW", False)]
        result = CvtModel.tsdb_lookup(items, start_time=ts_to_iso(self.base_ts + 5_000_000_000))
        assert result == [[4, None], [3, None]]
