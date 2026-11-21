# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import re
import unittest
from decimal import Decimal
from unittest.mock import MagicMock, patch

import psycopg
from questdb import TimestampMicros, TimestampNanos

from openc3.utilities.logger import Logger
from openc3.utilities.questdb_client import QuestDBClient
from openc3.utilities.tsdb_cmd_sync import (
    SyncError,
    command_tables,
    complete_rows,
    convert_value,
    main,
    sync_table,
)


TABLE = "DEFAULT__CMD__INST__COLLECT"


class FakeCursor:
    """Answers the queries tsdb_cmd_sync makes from {table: (columns, rows)}.
    Rows hold the time in nanoseconds first, then the other columns in order.
    """

    def __init__(self, tables):
        self.tables = tables
        self.queries = []
        self.result = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def execute(self, sql, params=None):
        self.queries.append((sql, params))
        if sql == "SELECT table_name FROM tables()":
            self.result = [(name,) for name in self.tables]
            return
        if sql.startswith("SELECT table_name FROM tables() WHERE"):
            self.result = [(params[0],)] if params[0] in self.tables else []
            return
        table = re.search(r'FROM "([^"]+)"', sql).group(1)
        if table not in self.tables:
            raise psycopg.errors.SyntaxError(f"table does not exist [table={table}]")
        columns, rows = self.tables[table]
        if sql.startswith("SHOW COLUMNS"):
            self.result = list(columns.items())
        elif "max(" in sql:
            self.result = [(rows[-1][0] if rows else None,)]
        else:
            if params:
                after = QuestDBClient.nsec_to_iso
                rows = [row for row in rows if after(row[0]) > params[0]]
            limit = int(re.search(r"LIMIT (\d+)", sql).group(1))
            selected = re.findall(r'"([^"]+)"', sql.split(" FROM ")[0])
            indexes = [list(columns).index(name) for name in selected]
            self.result = [tuple(row[i] for i in indexes) for row in rows[:limit]]

    def fetchall(self):
        return self.result

    def fetchone(self):
        return self.result[0] if self.result else None


class FakeConnection:
    def __init__(self, tables):
        self.cursor_obj = FakeCursor(tables)

    def cursor(self):
        return self.cursor_obj

    def close(self):
        pass


COLUMNS = {
    "PACKET_TIMESECONDS": "TIMESTAMP_NS",
    "RECEIVED_TIMESECONDS": "TIMESTAMP_NS",
    "COSMOS_DATA_TAG": "SYMBOL",
    "COSMOS_EXTRA": "VARCHAR",
    "DURATION": "DOUBLE",
}


def make_dest(rows=None, columns=None, tables=None):
    dest = MagicMock(spec=QuestDBClient)
    dest.query = FakeConnection({TABLE: (columns or COLUMNS, rows or [])} if tables is None else tables)
    dest.ingest = MagicMock()
    return dest


def plain(value):
    """TimestampNanos and TimestampMicros don't compare equal, so compare their values."""
    if isinstance(value, (TimestampNanos, TimestampMicros)):
        return (type(value).__name__, value.value)
    if isinstance(value, dict):
        return {k: plain(v) for k, v in value.items()}
    return value


def select_queries(source):
    """The (sql, params) of each page read from the source."""
    return [query for query in source.cursor_obj.queries if query[0].startswith("SELECT cast")]


def source_rows(count, start=1_000):
    return [(start + i, start + i + 5, "tag", '{"username":"op"}', 1.5) for i in range(count)]


class TestConvertValue(unittest.TestCase):
    def test_timestamps_keep_nanoseconds(self):
        self.assertEqual(plain(convert_value(123, "TIMESTAMP_NS", "TIMESTAMP_NS")), ("TimestampNanos", 123))
        self.assertEqual(plain(convert_value(123, "TIMESTAMP", "TIMESTAMP_NS")), ("TimestampNanos", 123_000))
        self.assertEqual(plain(convert_value(123_456, "TIMESTAMP_NS", "TIMESTAMP")), ("TimestampMicros", 123))

    def test_converts_to_the_destination_type(self):
        self.assertEqual(convert_value(3, "LONG", "DOUBLE"), 3.0)
        self.assertIsInstance(convert_value(3, "LONG", "DOUBLE"), float)
        self.assertEqual(convert_value(3.0, "DOUBLE", "LONG"), 3)
        self.assertEqual(convert_value(3, "LONG", "VARCHAR"), "3")
        self.assertEqual(convert_value("x", "VARCHAR", "SYMBOL"), "x")
        self.assertIs(convert_value(True, "BOOLEAN", "BOOLEAN"), True)
        self.assertEqual(convert_value("1.5", "VARCHAR", "DECIMAL"), Decimal("1.5"))

    def test_rejects_lossy_or_unsupported_conversions(self):
        with self.assertRaises(SyncError):
            convert_value(3.5, "DOUBLE", "LONG")
        with self.assertRaises(SyncError):
            convert_value(5, "LONG", "TIMESTAMP_NS")
        with self.assertRaises(SyncError):
            convert_value(5, "TIMESTAMP_NS", "LONG")
        with self.assertRaises(SyncError):
            convert_value(b"x", "BINARY", "BINARY")


class TestCommandTables(unittest.TestCase):
    def test_lists_command_tables_by_scope(self):
        names = [TABLE, "DEFAULT__TLM__INST__HEALTH_STATUS", "OTHER__CMD__INST__ABORT", "sys.telemetry"]
        cursor = FakeCursor(dict.fromkeys(names))
        self.assertEqual(command_tables(cursor, None), ["DEFAULT__CMD__INST__COLLECT", "OTHER__CMD__INST__ABORT"])
        self.assertEqual(command_tables(cursor, ["OTHER"]), ["OTHER__CMD__INST__ABORT"])


class TestCompleteRows(unittest.TestCase):
    def test_keeps_a_partial_page(self):
        rows = [(1,), (2,), (2,)]
        self.assertEqual(complete_rows(rows, 5), rows)

    def test_drops_rows_sharing_the_last_time_of_a_full_page(self):
        self.assertEqual(complete_rows([(1,), (2,), (3,), (3,)], 4), [(1,), (2,)])

    def test_raises_when_a_full_page_shares_one_time(self):
        with self.assertRaises(SyncError):
            complete_rows([(1,), (1,)], 2)


class TestSyncTable(unittest.TestCase):
    def test_copies_rows_newer_than_the_destination(self):
        rows = source_rows(5)
        source = FakeConnection({TABLE: (COLUMNS, rows)})
        dest = make_dest(rows=rows[:2])

        self.assertEqual(sync_table(source, dest, TABLE, page_size=2), 3)

        written = dest.ingest.row.call_args_list
        self.assertEqual([call.kwargs["at"].value for call in written], [1002, 1003, 1004])
        first = written[0]
        self.assertEqual(first.args, (TABLE,))
        self.assertEqual(first.kwargs["symbols"], {"COSMOS_DATA_TAG": "tag"})
        self.assertEqual(
            plain(first.kwargs["columns"]),
            {"RECEIVED_TIMESECONDS": ("TimestampNanos", 1007), "COSMOS_EXTRA": '{"username":"op"}', "DURATION": 1.5},
        )
        # A full page leaves its last time for the next page: 1002, 1003, then 1004
        self.assertEqual(dest.flush.call_count, 3)
        self.assertEqual(select_queries(source)[0][1], [QuestDBClient.nsec_to_iso(1001)])

    def test_copies_everything_into_an_empty_table_with_timestamps_as_longs(self):
        source = FakeConnection({TABLE: (COLUMNS, source_rows(3))})
        self.assertEqual(sync_table(source, make_dest(), TABLE), 3)
        sql, params = select_queries(source)[0]
        self.assertIn('cast("PACKET_TIMESECONDS" as long), cast("RECEIVED_TIMESECONDS" as long)', sql)
        self.assertNotIn("WHERE", sql)
        self.assertIsNone(params)

    def test_skips_null_values(self):
        source = FakeConnection({TABLE: (COLUMNS, [(1000, None, None, None, 2.0)])})
        dest = make_dest()
        sync_table(source, dest, TABLE)
        call = dest.ingest.row.call_args
        self.assertIsNone(call.kwargs["symbols"])
        self.assertEqual(call.kwargs["columns"], {"DURATION": 2.0})

    def test_copies_only_columns_the_destination_has(self):
        source = FakeConnection({TABLE: (COLUMNS, source_rows(1))})
        dest_columns = {k: v for k, v in COLUMNS.items() if k != "DURATION"}
        dest = make_dest(columns=dest_columns)
        warnings = []
        sync_table(source, dest, TABLE, warn=warnings.append)
        self.assertNotIn("DURATION", dest.ingest.row.call_args.kwargs["columns"])
        self.assertEqual(warnings, [f"{TABLE}: destination has no column DURATION, values not copied"])

    def test_skips_a_table_missing_on_the_destination(self):
        source = FakeConnection({TABLE: (COLUMNS, source_rows(1))})
        dest = make_dest(tables={})
        warnings = []
        self.assertEqual(sync_table(source, dest, TABLE, warn=warnings.append), 0)
        self.assertEqual(len(warnings), 1)
        dest.ingest.row.assert_not_called()

    def test_raises_when_a_connection_fails(self):
        source = FakeConnection({TABLE: (COLUMNS, source_rows(1))})
        dest = make_dest()
        dest.query.cursor_obj.execute = MagicMock(side_effect=psycopg.OperationalError("connection lost"))
        with self.assertRaises(psycopg.OperationalError):
            sync_table(source, dest, TABLE)

    def test_writes_nothing_from_a_page_with_a_value_it_cant_convert(self):
        # The third row's DURATION can't become a LONG on the destination
        rows = [(1000, 1005, "tag", "{}", 1.0), (1001, 1006, "tag", "{}", 2.0), (1002, 1007, "tag", "{}", 3.5)]
        source = FakeConnection({TABLE: (COLUMNS, rows)})
        dest = make_dest(columns={**COLUMNS, "DURATION": "LONG"})
        with self.assertRaises(SyncError):
            sync_table(source, dest, TABLE)
        dest.ingest.row.assert_not_called()

    def test_dry_run_counts_without_writing(self):
        source = FakeConnection({TABLE: (COLUMNS, source_rows(4))})
        dest = make_dest()
        self.assertEqual(sync_table(source, dest, TABLE, page_size=3, dry_run=True), 4)
        dest.ingest.row.assert_not_called()
        dest.flush.assert_not_called()


class TestMain(unittest.TestCase):
    @patch("openc3.utilities.tsdb_cmd_sync.QuestDBClient")
    @patch("openc3.utilities.tsdb_cmd_sync.psycopg.connect")
    def test_syncs_each_db_shard_from_its_own_host(self, connect, client):
        connect.return_value = FakeConnection({})
        self.assertEqual(main(["--source-host", "blue-tsdb-SHARDNUM", "--db-shards", "2"]), 0)
        self.assertEqual([c.kwargs["host"] for c in connect.call_args_list], ["blue-tsdb-0", "blue-tsdb-1"])
        self.assertEqual([c.kwargs["db_shard"] for c in client.call_args_list], [0, 1])

    @patch("openc3.utilities.tsdb_cmd_sync.sync_table", side_effect=[SyncError("bad"), 1])
    @patch("openc3.utilities.tsdb_cmd_sync.QuestDBClient")
    @patch("openc3.utilities.tsdb_cmd_sync.psycopg.connect")
    def test_continues_after_a_failed_table_and_returns_1(self, connect, client, sync):
        connect.return_value = FakeConnection(dict.fromkeys(["A__CMD__T__P1", "A__CMD__T__P2"]))
        ingest = client.return_value.ingest
        self.assertEqual(main(["--source-host", "blue"]), 1)
        self.assertEqual(sync.call_count, 2)
        # The sender is replaced after a failure, on top of the initial connect,
        # and the failed table's buffered rows are discarded rather than sent
        ingest.close.assert_called_once_with(flush=False)
        self.assertEqual(client.return_value.connect_ingest.call_count, 2)

    @patch("openc3.utilities.tsdb_cmd_sync.QuestDBClient")
    @patch("openc3.utilities.tsdb_cmd_sync.psycopg.connect")
    def test_continues_after_an_unreachable_db_shard_and_returns_1(self, connect, client):
        connect.side_effect = [psycopg.OperationalError("unreachable"), FakeConnection({})]
        self.assertEqual(main(["--source-host", "blue-tsdb-SHARDNUM", "--db-shards", "2"]), 1)
        self.assertEqual([c.kwargs["host"] for c in connect.call_args_list], ["blue-tsdb-0", "blue-tsdb-1"])
        self.assertEqual(client.return_value.close.call_count, 2)

    @patch("openc3.utilities.tsdb_cmd_sync.QuestDBClient")
    @patch("openc3.utilities.tsdb_cmd_sync.psycopg.connect")
    def test_keeps_the_logger_from_publishing(self, connect, client):
        connect.return_value = FakeConnection({})
        Logger.instance().no_store = False
        main(["--source-host", "blue"])
        self.assertTrue(Logger.instance().no_store)

    def test_requires_a_source_host(self):
        with patch.dict("os.environ", {"SOURCE_TSDB_HOSTNAME": ""}), self.assertRaises(SystemExit):
            main([])


if __name__ == "__main__":
    unittest.main()
