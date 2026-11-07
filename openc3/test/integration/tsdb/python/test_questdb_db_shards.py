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
Integration tests for QuestDBClient db_shard routing against two real QuestDBs.

OPENC3_TSDB_HOSTNAME is tsdb-SHARDNUM like a db_sharded deployment so the client
resolves each db_shard to its own host with hostname_for_db_shard. Locally both
QuestDBs run on 127.0.0.1 so connections to tsdb-<N> are sent to the ports of
db_shard N (questdb and questdb-shard1 in docker-compose.test.yml). Everything
else (ingest, queries, reconnects) runs against the real QuestDBs.

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
       (starts questdb and questdb-shard1)
    2. Run tests: uv run pytest ../test/integration/tsdb/python/test_questdb_db_shards.py -v
    3. Stop QuestDB: docker compose -f docker-compose.test.yml down
"""

import os
import sys
import time
from datetime import datetime, timezone
from unittest.mock import patch

import psycopg
import pytest
from questdb.ingress import Sender


# Add openc3 python path for imports
# Path: openc3/test/integration/tsdb/python -> openc3/python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "python"))

from conftest import requires_questdb_shards

from openc3.models.cvt_model import CvtModel
from openc3.utilities.questdb_client import QuestDBClient


PACKET_DEF = {"items": [{"name": "VALUE", "data_type": "INT", "bit_size": 32}]}
TARGET = "DBSHARD"
PACKET = "PKT"
# Host => port of the QuestDB for that db_shard
QUERY_PORTS = {
    "tsdb-0": int(os.environ["OPENC3_TSDB_QUERY_PORT"]),
    "tsdb-1": int(os.environ["OPENC3_TSDB_SHARD1_QUERY_PORT"]),
}
INGEST_PORTS = {
    "tsdb-0": int(os.environ["OPENC3_TSDB_INGEST_PORT"]),
    "tsdb-1": int(os.environ["OPENC3_TSDB_SHARD1_INGEST_PORT"]),
}
REAL_CONNECT = psycopg.connect


def connect(*args, host, **kwargs):
    """Send a connection to tsdb-<N> to the QuestDB of db_shard N"""
    kwargs.pop("port", None)
    if host not in QUERY_PORTS:
        raise psycopg.OperationalError(f"unknown host {host}")
    return REAL_CONNECT(*args, host="127.0.0.1", port=QUERY_PORTS[host], **kwargs)


def sender(protocol, host, _port, **kwargs):
    """Send ingest to tsdb-<N> to the QuestDB of db_shard N"""
    return Sender(protocol, "127.0.0.1", INGEST_PORTS[host], **kwargs)


def query(db_shard, sql):
    """Query the QuestDB of a db_shard directly, bypassing QuestDBClient"""
    host = f"tsdb-{db_shard}"
    with (
        connect(host=host, user="admin", password="admin", dbname="qdb", autocommit=True) as conn,
        conn.cursor() as cur,
    ):
        cur.execute(sql)
        return cur.fetchall() if cur.description else None


def ts_to_iso(ts_ns):
    return datetime.fromtimestamp(ts_ns / 1e9, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def table_exists(db_shard, table_name):
    return query(db_shard, f"SELECT count() FROM tables() WHERE table_name = '{table_name}'")[0][0] == 1


def wait_for_rows(db_shard, table_name, count, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            if query(db_shard, f'SELECT count() FROM "{table_name}"')[0][0] >= count:
                return
        except psycopg.Error:
            # The table may not exist yet because the ingest hasn't committed so keep polling
            pass
        time.sleep(0.1)
    raise TimeoutError(f"{table_name} on db_shard {db_shard} didn't get {count} rows")


@requires_questdb_shards
class TestQuestDBDbShards:
    @pytest.fixture(autouse=True)
    def db_shards(self):
        with (
            patch.dict(os.environ, {"OPENC3_TSDB_HOSTNAME": "tsdb-SHARDNUM"}),
            patch("openc3.utilities.questdb_client.psycopg.connect", side_effect=connect),
            patch("openc3.utilities.questdb_client.Sender", side_effect=sender),
            patch("openc3.models.target_model.TargetModel") as target_model,
        ):
            target_model.packet.return_value = PACKET_DEF
            QuestDBClient.disconnect()
            self.table_name, _ = QuestDBClient.sanitize_table_name(TARGET, PACKET)
            self.drop_tables()
            yield
            QuestDBClient.disconnect()
            self.drop_tables()

    def drop_tables(self):
        for db_shard in (0, 1):
            query(db_shard, f'DROP TABLE IF EXISTS "{self.table_name}"')

    def ingest(self, db_shard, values, base_ts):
        """Ingest VALUE rows one second apart with a QuestDBClient for the db_shard"""
        client = QuestDBClient(db_shard=db_shard)
        client.connect_ingest()
        client.connect_query()
        client.create_table(TARGET, PACKET, PACKET_DEF)
        for index, value in enumerate(values):
            columns = client.process_json_data({"VALUE": value}, self.table_name)
            columns["RECEIVED_COUNT"] = index
            row_ts = base_ts + index * 1_000_000_000
            client.write_row(self.table_name, columns, row_ts, rx_timestamp_ns=row_ts)
        client.flush()
        client.close()
        wait_for_rows(db_shard, self.table_name, len(values))

    def test_ingests_into_the_questdb_of_the_db_shard_only(self):
        base_ts = int(time.time()) * 1_000_000_000
        self.ingest(1, [1, 2, 3], base_ts)
        assert table_exists(1, self.table_name)
        assert not table_exists(0, self.table_name)
        assert query(1, f'SELECT VALUE FROM "{self.table_name}"') == [(1,), (2,), (3,)]

    def test_looks_up_a_target_on_the_questdb_of_its_db_shard(self):
        # The same table on both db_shards with different values
        base_ts = int(time.time()) * 1_000_000_000
        self.ingest(0, [100, 200], base_ts)
        self.ingest(1, [1, 2], base_ts)
        start_time = ts_to_iso(base_ts)
        end_time = ts_to_iso(base_ts + 5_000_000_000)
        items = [(TARGET, PACKET, "VALUE", "RAW", None)]

        for db_shard, expected in ((1, [1, 2]), (0, [100, 200])):
            with patch.object(QuestDBClient, "db_shard_for_target", return_value=db_shard):
                result = CvtModel.tsdb_lookup(items, start_time=start_time, end_time=end_time)
            assert [row[0][0] for row in result] == expected, f"db_shard {db_shard}"

    def test_keeps_a_connection_per_db_shard(self):
        base_ts = int(time.time()) * 1_000_000_000
        self.ingest(0, [100], base_ts)
        self.ingest(1, [1, 2], base_ts)
        count = f'SELECT count() as count FROM "{self.table_name}"'

        conn0 = QuestDBClient.connection(db_shard=0)
        conn1 = QuestDBClient.connection(db_shard=1)
        assert conn0 is not conn1
        assert QuestDBClient.connection(db_shard=1) is conn1
        assert QuestDBClient.query_with_retry(count, db_shard=0) == [{"count": 1}]
        assert QuestDBClient.query_with_retry(count, db_shard=1) == [{"count": 2}]

        QuestDBClient.disconnect(db_shard=1)
        assert conn1.closed
        assert not conn0.closed
        # db_shard 0 keeps its connection and db_shard 1 reconnects to its own QuestDB
        assert QuestDBClient.connection(db_shard=0) is conn0
        assert QuestDBClient.query_with_retry(count, db_shard=0) == [{"count": 1}]
        assert QuestDBClient.query_with_retry(count, db_shard=1) == [{"count": 2}]
        assert QuestDBClient.connection(db_shard=1) is not conn1

    def test_reconnects_the_db_shard_whose_connection_was_lost(self):
        base_ts = int(time.time()) * 1_000_000_000
        self.ingest(0, [100], base_ts)
        self.ingest(1, [1, 2], base_ts)
        count = f'SELECT count() as count FROM "{self.table_name}"'
        conn0 = QuestDBClient.connection(db_shard=0)
        conn1 = QuestDBClient.connection(db_shard=1)
        # Kill the db_shard 1 connection out from under the client
        conn1.close()

        with patch("openc3.utilities.questdb_client.time.sleep"):
            assert QuestDBClient.query_with_retry(count, db_shard=1) == [{"count": 2}]
        assert QuestDBClient.connection(db_shard=1) is not conn1
        assert QuestDBClient.connection(db_shard=0) is conn0
        assert QuestDBClient.query_with_retry(count, db_shard=0) == [{"count": 1}]

    def test_checks_the_connection_of_each_db_shard(self):
        assert QuestDBClient.check_connection(db_shard=0)
        assert QuestDBClient.check_connection(db_shard=1)
        # There is no QuestDB for db_shard 2
        with pytest.raises(psycopg.OperationalError):
            QuestDBClient.check_connection(db_shard=2)
