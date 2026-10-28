# Copyright 2026 OpenC3, Inc.
# All Rights Reserved
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import psycopg

from openc3.utilities.questdb_client import QuestDBClient


class TestTsdbLookup(unittest.TestCase):
    def test_returns_a_row_of_nones_when_every_item_is_a_placeholder(self):
        # get_tlm_available returns None for items which don't exist, which arrive
        # here as [None, None, None, None, None]. There's no table to query so the
        # values come back None rather than building a query with no FROM clause.
        items = [[None] * 5, [None] * 5, [None] * 5]
        self.assertEqual(
            QuestDBClient.tsdb_lookup(items, start_time="2026-09-13T00:00:00Z", end_time="2026-09-13T01:00:00Z"),
            [[None, None], [None, None], [None, None]],
        )

    def test_returns_a_row_of_nones_for_a_placeholder_without_an_end_time(self):
        self.assertEqual(
            QuestDBClient.tsdb_lookup([[None] * 5], start_time="2026-09-13T00:00:00Z"),
            [[None, None]],
        )


# Base time for the db_shard tests. Table times are in seconds after it.
BASE_NS = 1_789_257_600_000_000_000  # 2026-09-13T00:00:00Z
# Target name => db_shard
DB_SHARDS = {"INST": 0, "INST2": 1}
# (target_name, packet_name) => [(seconds, {item_name: value})]
TABLES = {
    ("INST", "HEALTH_STATUS"): [
        (10, {"TEMP1": 1, "TEMP2": 2}),
        (30, {"TEMP1": 3, "TEMP2": 4}),
        (50, {"TEMP1": 5, "TEMP2": 6}),
    ],
    ("INST2", "HEALTH_STATUS"): [(20, {"TEMP1": 20}), (30, {"TEMP1": 30}), (40, {"TEMP1": 40}), (60, {"TEMP1": 60})],
    # Only a row before the start of the range lookups
    ("INST2", "EARLY"): [(0, {"TEMP1": 0})],
    # A row between the last two INST2 HEALTH_STATUS rows in the range lookups
    ("INST2", "LATER"): [(45, {"TEMP1": 45})],
}


def iso(seconds):
    return QuestDBClient.nsec_to_iso(BASE_NS + seconds * 1_000_000_000)


def iso_to_nsec(value):
    seconds, fraction = value.rstrip("Z").split(".")
    whole = datetime.strptime(seconds, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    return int(whole.timestamp()) * 1_000_000_000 + int(fraction.ljust(9, "0"))


def fake_single_db_shard(
    items, start_time, end_time=None, scope="DEFAULT", db_shard=0, flatten=True, inclusive=False, with_time=False
):
    """Stands in for one QuestDB query: the first packet (T0) is filtered by time and
    every other packet is ASOF JOINed to it, using its last row at or before each T0 row
    """
    assert not flatten
    real_items = [item for item in items if item.item_name is not None]
    for item in real_items:
        assert DB_SHARDS[item.target_name] == db_shard, f"{item.target_name} queried on db_shard {db_shard}"
    first = real_items[0]
    start = iso_to_nsec(start_time)
    rows = [
        (BASE_NS + seconds * 1_000_000_000, values)
        for seconds, values in TABLES[(first.target_name, first.packet_name)]
    ]
    if end_time:
        rows = [row for row in rows if start <= row[0] < iso_to_nsec(end_time)]
    else:
        rows = [row for row in rows if row[0] < start or (inclusive and row[0] == start)][-1:]

    result = []
    for time_ns, _ in rows:
        row = []
        for item in items:
            if item.item_name is None:
                row.append([None, None])
                continue
            joined = [
                values
                for seconds, values in TABLES[(item.target_name, item.packet_name)]
                if BASE_NS + seconds * 1_000_000_000 <= time_ns
            ]
            if item.item_name == "PACKET_TIMESECONDS":
                row.append([time_ns / 1_000_000_000, None])
            else:
                row.append([joined[-1][item.item_name] if joined else None, None])
        if with_time:
            row.append([time_ns, None])
        result.append(row)
    return result or {}


class TestTsdbLookupDbShards(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(
            QuestDBClient, "db_shard_for_target", side_effect=lambda target_name, scope: DB_SHARDS.get(target_name, 0)
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def lookup(self, items, start, end=None):
        """Items are "TARGET PACKET ITEM", or "TARGET PACKET" for a placeholder"""
        items = [
            [*item.split(), "CONVERTED", None] if len(item.split()) == 3 else [*item.split(), None, None, None]
            for item in items
        ]
        with patch.object(QuestDBClient, "_tsdb_lookup_single_db_shard", side_effect=fake_single_db_shard) as single:
            result = QuestDBClient.tsdb_lookup(
                items, start_time=iso(start), end_time=iso(end) if end is not None else None
            )
        self.queries = [
            (call.kwargs["db_shard"], [item.packet_name for item in call[0][0]]) for call in single.call_args_list
        ]
        return result

    def test_uses_the_single_db_shard_fast_path(self):
        with patch.object(QuestDBClient, "_tsdb_lookup_single_db_shard", return_value="result") as single:
            items = [
                ["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED", None],
                ["INST", "HEALTH_STATUS", "TEMP2", "CONVERTED", None],
            ]
            self.assertEqual(QuestDBClient.tsdb_lookup(items, start_time=iso(0), scope="OTHER"), "result")
        single.assert_called_once()
        self.assertEqual(single.call_args.kwargs["db_shard"], 0)
        self.assertEqual(single.call_args.kwargs["scope"], "OTHER")
        self.assertEqual(single.call_args[0][0][1].item_name, "TEMP2")

    def test_aligns_the_other_db_shards_to_the_first_items_db_shard_by_packet_time(self):
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1", "INST HEALTH_STATUS TEMP2"], 5, 55),
            [
                # No INST2 row at or before 10 seconds
                [[1, None], [None, None], [2, None]],
                # The INST2 row at the same time
                [[3, None], [30, None], [4, None]],
                # The last INST2 row before 50 seconds and never the later 60 second row
                [[5, None], [40, None], [6, None]],
            ],
        )

    def test_drives_the_rows_from_the_db_shard_of_the_first_item(self):
        self.assertEqual(
            self.lookup(["INST2 HEALTH_STATUS TEMP1", "INST HEALTH_STATUS TEMP1"], 5, 55),
            [[[20, None], [1, None]], [[30, None], [3, None]], [[40, None], [3, None]]],
        )

    def test_carries_forward_a_row_before_start_time(self):
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 EARLY TEMP1"], 5, 55),
            [[[1, None], [0, None]], [[3, None], [0, None]], [[5, None], [0, None]]],
        )

    def test_aligns_each_packet_on_a_db_shard_independently(self):
        items = ["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1", "INST2 LATER TEMP1"]
        # INST2 LATER is aligned to INST at 50 seconds, not INST2 HEALTH_STATUS at 40 seconds
        self.assertEqual(
            self.lookup(items, 5, 55),
            [
                [[1, None], [None, None], [None, None]],
                [[3, None], [30, None], [None, None]],
                [[5, None], [40, None], [45, None]],
            ],
        )
        self.assertEqual(self.lookup(items, 55), [[5, None], [40, None], [45, None]])
        # Each packet on another db_shard is queried on its own
        self.assertEqual(
            {tuple(packets) for db_shard, packets in self.queries if db_shard == 1}, {("HEALTH_STATUS",), ("LATER",)}
        )

    def test_returns_the_last_row_at_or_before_the_driving_row(self):
        # INST drives at 50 seconds so INST2 returns its 40 second row, not its 60 second row
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 70), [[5, None], [40, None]]
        )
        # Including a row at the same time as the driving row
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 31), [[3, None], [30, None]]
        )

    def test_returns_a_single_row_as_a_flat_list(self):
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 25, 35), [[3, None], [30, None]]
        )

    def test_fills_an_other_db_shard_with_no_rows_with_nones(self):
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 5, 15), [[1, None], [None, None]]
        )

    def test_returns_empty_when_the_db_shard_of_the_first_item_has_no_rows(self):
        self.assertEqual(self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 55, 58), {})
        self.assertEqual(self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 5), {})

    def test_does_not_query_a_db_shard_with_only_placeholders(self):
        self.assertEqual(
            self.lookup(["INST2 HEALTH_STATUS", "INST HEALTH_STATUS TEMP1", "INST2 LATER"], 25, 35),
            [[None, None], [3, None], [None, None]],
        )
        self.assertEqual(self.queries, [(0, ["HEALTH_STATUS"])])

    def test_does_not_query_the_placeholders_on_another_db_shard(self):
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1", "INST2 LATER"], 25, 35),
            [[3, None], [30, None], [None, None]],
        )
        self.assertNotIn((1, ["LATER"]), self.queries)


class TestQueryWithRetry(unittest.TestCase):
    def test_queries_and_reconnects_the_given_db_shard(self):
        cursor = MagicMock()
        cursor.__enter__.return_value.execute.side_effect = [psycopg.OperationalError("down"), None]
        cursor.__enter__.return_value.fetchall.return_value = [{"A": 1}]
        conn = MagicMock()
        conn.cursor.return_value = cursor
        with (
            patch.object(QuestDBClient, "connection", return_value=conn) as connection,
            patch.object(QuestDBClient, "disconnect") as disconnect,
            patch("openc3.utilities.questdb_client.time.sleep"),
        ):
            self.assertEqual(QuestDBClient.query_with_retry("SELECT 1", db_shard=2), [{"A": 1}])
        connection.assert_called_with(db_shard=2)
        disconnect.assert_called_once_with(db_shard=2)


class TestBuildAggregationSelects(unittest.TestCase):
    def test_aggregates_raw_column_for_raw_value_type(self):
        selects, mapping = QuestDBClient.build_aggregation_selects("TEMP1", "RAW")
        self.assertEqual(
            selects,
            [
                'min("TEMP1") as "TEMP1__N"',
                'max("TEMP1") as "TEMP1__X"',
                'avg("TEMP1") as "TEMP1__A"',
                'stddev("TEMP1") as "TEMP1__S"',
            ],
        )
        self.assertEqual(mapping["TEMP1__N"], ["TEMP1", "MIN", "RAW"])

    def test_aggregates_converted_column_for_converted_value_type(self):
        selects, mapping = QuestDBClient.build_aggregation_selects("TEMP1", "CONVERTED")
        self.assertEqual(selects[0], 'min("TEMP1__C") as "TEMP1__CN"')
        self.assertEqual(mapping["TEMP1__CN"], ["TEMP1", "MIN", "CONVERTED"])

    def test_uses_converted_column_when_it_exists_and_is_numeric(self):
        existing = {"TEMP1": "FLOAT", "TEMP1__C": "DOUBLE", "TEMP1__F": "VARCHAR"}
        selects, _ = QuestDBClient.build_aggregation_selects("TEMP1", "CONVERTED", existing_columns=existing)
        self.assertEqual(selects[0], 'min("TEMP1__C") as "TEMP1__CN"')

    def test_falls_back_to_raw_when_converted_column_missing(self):
        # Items without a read_conversion (e.g. only a format string) have no __C
        # column. CONVERTED reduced queries must fall back to the raw column.
        existing = {"POSPROGRESS": "FLOAT", "POSPROGRESS__F": "VARCHAR"}
        selects, mapping = QuestDBClient.build_aggregation_selects(
            "POSPROGRESS", "CONVERTED", existing_columns=existing
        )
        self.assertEqual(
            selects,
            [
                'min("POSPROGRESS") as "POSPROGRESS__CN"',
                'max("POSPROGRESS") as "POSPROGRESS__CX"',
                'avg("POSPROGRESS") as "POSPROGRESS__CA"',
                'stddev("POSPROGRESS") as "POSPROGRESS__CS"',
            ],
        )
        # The mapping value type stays CONVERTED so the requested object still matches.
        self.assertEqual(mapping["POSPROGRESS__CN"], ["POSPROGRESS", "MIN", "CONVERTED"])

    def test_falls_back_to_raw_when_converted_column_non_numeric(self):
        # States items store their converted value as a VARCHAR string, which can't be
        # aggregated. Fall back to the raw (numeric) column.
        existing = {"MODE": "INT", "MODE__C": "VARCHAR"}
        selects, _ = QuestDBClient.build_aggregation_selects("MODE", "CONVERTED", existing_columns=existing)
        self.assertEqual(selects[0], 'min("MODE") as "MODE__CN"')

    def test_numeric_column_type(self):
        for t in ["BYTE", "SHORT", "INT", "LONG", "FLOAT", "DOUBLE", "double", "float"]:
            self.assertTrue(QuestDBClient.numeric_column_type(t))
        for t in ["VARCHAR", "SYMBOL", "STRING", "BOOLEAN", "TIMESTAMP", None]:
            self.assertFalse(QuestDBClient.numeric_column_type(t))


class TestCreateTableConvertedColumns(unittest.TestCase):
    def setUp(self):
        self.client = QuestDBClient()
        self.ddl = []
        self.client._execute_ddl = lambda sql: self.ddl.append(sql)
        # Table doesn't exist so create_table takes the CREATE TABLE path
        self.client._get_existing_columns = lambda table_name: None

    def _create(self, item, cmd_or_tlm):
        self.client.create_table("INST", "PKT", {"items": [item]}, cmd_or_tlm, scope="DEFAULT")
        return "\n".join(self.ddl)

    def test_commands_type_write_conversion_converted_column_as_double(self):
        # The user given value is logged into __C and is typically engineering units
        # (a float) even when the item itself is an integer
        item = {
            "name": "VALUE",
            "data_type": "UINT",
            "bit_size": 16,
            "write_conversion": {"class": "PolynomialConversion"},
        }
        sql = self._create(item, "CMD")
        self.assertIn('"VALUE" int', sql)
        self.assertIn('"VALUE__C" double', sql)

    def test_commands_type_string_write_conversion_converted_column_as_varchar(self):
        item = {
            "name": "LABEL",
            "data_type": "STRING",
            "bit_size": 64,
            "write_conversion": {"class": "GenericConversion"},
        }
        sql = self._create(item, "CMD")
        self.assertIn('"LABEL__C" varchar', sql)
        self.assertTrue(self.client.varchar_columns["DEFAULT__CMD__INST__PKT__LABEL__C"])

    def test_states_take_precedence_over_write_conversion(self):
        item = {
            "name": "STATE",
            "data_type": "UINT",
            "bit_size": 8,
            "states": {"FALSE": 0, "TRUE": 1},
            "write_conversion": {"class": "GenericConversion"},
        }
        sql = self._create(item, "CMD")
        self.assertIn('"STATE__C" varchar', sql)

    def test_telemetry_ignores_write_conversion(self):
        item = {
            "name": "VALUE",
            "data_type": "UINT",
            "bit_size": 16,
            "write_conversion": {"class": "PolynomialConversion"},
        }
        sql = self._create(item, "TLM")
        self.assertNotIn("VALUE__C", sql)


class TestHandleIngressError(unittest.TestCase):
    """handle_ingress_error parses the offending table and column out of the
    QuestDB error message before casting the pending row to fit the column."""

    def _client(self, pending_rows=None):
        # Bypass __init__ so no connection is required
        client = QuestDBClient.__new__(QuestDBClient)
        client.pending_rows = pending_rows if pending_rows is not None else []
        client.varchar_columns = {}
        self.logs = []
        client._log_warn = lambda msg: self.logs.append(msg)
        client._log_error = lambda msg: self.logs.append(msg)
        client._log_info = lambda msg: self.logs.append(msg)
        client._reconnect_and_retry_pending = lambda: self.logs.append("retried")
        return client

    @staticmethod
    def _error(message):
        return type("IngressError", (Exception,), {"__str__": lambda self: message})()

    CAST_ERROR = (
        "error in line 1: table: INST__HEALTH_STATUS, column: TEMP1; "
        "cast error from protocol type: DOUBLE to column type: LONG"
    )

    def test_parses_the_table_and_column_from_the_error(self):
        client = self._client()
        self.assertFalse(client.handle_ingress_error(self._error(self.CAST_ERROR)))
        self.assertIn(
            "Could not find column TEMP1 in pending rows for table INST__HEALTH_STATUS",
            "\n".join(self.logs),
        )

    def test_casts_the_value_in_the_matching_pending_row(self):
        columns = {"TEMP1": 1.5}
        client = self._client([("INST__HEALTH_STATUS", columns, 0)])
        self.assertTrue(client.handle_ingress_error(self._error(self.CAST_ERROR)))
        self.assertEqual(columns["TEMP1"], 1)
        self.assertIn("retried", self.logs)

    def test_leaves_rows_for_other_tables_alone(self):
        columns = {"TEMP1": 1.5}
        client = self._client([("INST__ADCS", columns, 0)])
        self.assertFalse(client.handle_ingress_error(self._error(self.CAST_ERROR)))
        self.assertEqual(columns["TEMP1"], 1.5)

    def test_parses_a_multi_line_error_message(self):
        message = (
            "error in line 1:\n table: INST__HEALTH_STATUS,\n column: TEMP1;\n cast error from protocol type: DOUBLE"
        )
        client = self._client()
        self.assertFalse(client.handle_ingress_error(self._error(message)))
        self.assertIn("for table INST__HEALTH_STATUS", "\n".join(self.logs))

    def test_does_not_run_a_name_past_the_end_of_its_line(self):
        # The table name is bounded by the newline as well as the comma, matching
        # the r"(.+?)," this replaced (`.` never matched a newline)
        message = "table: INST\nHEALTH_STATUS, column: TEMP1; cast error from protocol type: DOUBLE"
        client = self._client()
        self.assertFalse(client.handle_ingress_error(self._error(message)))
        self.assertIn("Could not parse table or column", "\n".join(self.logs))

    def test_gives_up_when_the_table_and_column_cannot_be_parsed(self):
        client = self._client()
        message = "cast error from protocol type: DOUBLE but no table or column named"
        self.assertFalse(client.handle_ingress_error(self._error(message)))
        self.assertIn("Could not parse table or column", "\n".join(self.logs))

    def test_ignores_errors_that_are_not_type_mismatches(self):
        client = self._client()
        client.connect_ingest = lambda: None
        self.assertFalse(client.handle_ingress_error(self._error("connection reset by peer")))
