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
from questdb import Protocol, QuestDBError, QuestDBErrorCode

from openc3.utilities.questdb_client import FLOAT32_POS_INF_SENTINEL, QuestDBClient
from test.test_helper import mock_redis, set_target_db_shard


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

    def test_returns_a_list_of_rows_for_placeholders_when_not_flattening(self):
        self.assertEqual(
            QuestDBClient.tsdb_lookup([[None] * 5], start_time="2026-09-13T00:00:00Z", flatten=False),
            [[[None, None]]],
        )

    def test_passes_flatten_to_a_single_db_shard_lookup(self):
        with patch.object(QuestDBClient, "_tsdb_lookup_single_db_shard", return_value=[[[1.0, None]]]) as single:
            QuestDBClient.tsdb_lookup(
                [["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED", None]],
                start_time="2026-09-13T00:00:00Z",
                flatten=False,
            )
        self.assertFalse(single.call_args.kwargs["flatten"])


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

    def lookup(self, items, start, end=None, flatten=True):
        """Items are "TARGET PACKET ITEM", or "TARGET PACKET" for a placeholder"""
        items = [
            [*item.split(), "CONVERTED", None] if len(item.split()) == 3 else [*item.split(), None, None, None]
            for item in items
        ]
        with patch.object(QuestDBClient, "_tsdb_lookup_single_db_shard", side_effect=fake_single_db_shard) as single:
            result = QuestDBClient.tsdb_lookup(
                items, start_time=iso(start), end_time=iso(end) if end is not None else None, flatten=flatten
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

    def test_keeps_a_single_row_as_a_list_of_rows_when_not_flattening(self):
        self.assertEqual(
            self.lookup(["INST HEALTH_STATUS TEMP1", "INST2 HEALTH_STATUS TEMP1"], 25, 35, flatten=False),
            [[[3, None], [30, None]]],
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


# The db_shard for each item comes from where its target is installed
class TestTsdbLookupTargetDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        set_target_db_shard("INST", 0)
        set_target_db_shard("INST2", 1)

    def test_queries_each_item_on_its_target_db_shard(self):
        items = [
            ["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED", None],
            ["INST2", "HEALTH_STATUS", "TEMP1", "CONVERTED", None],
        ]
        with patch.object(QuestDBClient, "_tsdb_lookup_single_db_shard") as single:
            # Each row ends with its packet time, with INST2 just before INST
            single.side_effect = lambda items, db_shard, **_kw: {
                0: [[[1.0, None], [BASE_NS, None]]],
                1: [[[2.0, None], [BASE_NS - 1, None]]],
            }[db_shard]
            result = QuestDBClient.tsdb_lookup(items, start_time="2026-09-13T00:00:00Z", scope="DEFAULT")
        self.assertEqual(result, [[1.0, None], [2.0, None]])
        shards = {call.kwargs["db_shard"]: call[0][0] for call in single.call_args_list}
        self.assertEqual([item.target_name for item in shards[1]], ["INST2"])


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


class TestTlmPacketsWithTables(unittest.TestCase):
    def test_returns_the_packets_with_a_table_queried_by_db_shard(self):
        tables = {0: {"DEFAULT__TLM__INST__HEALTH_STATUS"}, 1: {"DEFAULT__TLM__INST2__ADCS"}}
        packets = [("INST", "HEALTH_STATUS"), ("INST", "PARAMS"), ("INST2", "ADCS")]
        with (
            patch.object(QuestDBClient, "db_shard_for_target", side_effect=lambda t, scope: 1 if t == "INST2" else 0),
            patch.object(QuestDBClient, "table_names", side_effect=lambda db_shard: tables[db_shard]) as table_names,
        ):
            result = QuestDBClient.tlm_packets_with_tables(packets)
        self.assertEqual(result, {("INST", "HEALTH_STATUS"), ("INST2", "ADCS")})
        self.assertEqual(table_names.call_count, 2)

    def test_assumes_all_the_packets_have_a_table_if_the_table_names_cannot_be_fetched(self):
        packets = [("INST", "HEALTH_STATUS"), ("INST", "PARAMS")]
        with (
            patch.object(QuestDBClient, "db_shard_for_target", return_value=0),
            patch.object(QuestDBClient, "table_names", return_value=None),
        ):
            self.assertEqual(QuestDBClient.tlm_packets_with_tables(packets), set(packets))

    def test_does_not_query_without_packets(self):
        with patch.object(QuestDBClient, "table_names") as table_names:
            self.assertEqual(QuestDBClient.tlm_packets_with_tables([]), set())
        table_names.assert_not_called()


class TestTableNames(unittest.TestCase):
    def test_returns_the_upcased_table_names(self):
        rows = [{"table_name": "DEFAULT__TLM__INST__PARAMS"}, {"table_name": "default__cmd__inst__collect"}]
        with patch.object(QuestDBClient, "query_with_retry", return_value=rows) as query:
            self.assertEqual(
                QuestDBClient.table_names(db_shard=1),
                {"DEFAULT__TLM__INST__PARAMS", "DEFAULT__CMD__INST__COLLECT"},
            )
        self.assertEqual(query.call_args.kwargs["db_shard"], 1)

    def test_returns_none_if_the_tables_cannot_be_queried(self):
        with patch.object(QuestDBClient, "query_with_retry", side_effect=RuntimeError("down")):
            self.assertIsNone(QuestDBClient.table_names())


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


class TestHandleQwpIngressError(unittest.TestCase):
    """QWP schema mismatch messages name the column but not the table, so
    handle_ingress_error fixes the column in every pending table that has it,
    using each table's own column type."""

    def _client(self, pending_rows, column_types):
        client = QuestDBClient.__new__(QuestDBClient)
        client.pending_rows = pending_rows
        client.varchar_columns = {}
        client.json_columns = {}
        self.logs = []
        client._log_warn = lambda msg: self.logs.append(msg)
        client._log_error = lambda msg: self.logs.append(msg)
        client._log_info = lambda msg: self.logs.append(msg)
        client._reconnect_and_retry_pending = lambda: self.logs.append("retried")
        client._get_existing_columns = lambda table_name: column_types.get(table_name)
        return client

    @staticmethod
    def _error(message):
        return type("QuestDBServerRejectionError", (Exception,), {"__str__": lambda self: message})()

    def test_casts_using_each_tables_own_column_type(self):
        health = {"TEMP1": 1.5}
        adcs = {"TEMP1": 2.5}
        client = self._client(
            [("INST__HEALTH_STATUS", health, 0), ("INST__ADCS", adcs, 0)],
            {"INST__HEALTH_STATUS": {"TEMP1": "LONG"}, "INST__ADCS": {"TEMP1": "DOUBLE"}},
        )
        error = self._error(
            "QWP schema mismatch: double value 1.5 loses precision when converted to LONG [column=TEMP1]"
        )
        self.assertTrue(client.handle_ingress_error(error))
        self.assertEqual(health["TEMP1"], 1)
        # The DOUBLE column's value already fit, so it's unchanged
        self.assertEqual(adcs["TEMP1"], 2.5)
        self.assertIn("retried", self.logs)

    def test_parses_a_column_followed_by_other_fields(self):
        columns = {"TEMP1": "abc"}
        client = self._client([("INST__HEALTH_STATUS", columns, 0)], {"INST__HEALTH_STATUS": {"TEMP1": "LONG"}})
        error = self._error("QWP schema mismatch: cannot parse LONG from string [value=abc, column=TEMP1]")
        self.assertTrue(client.handle_ingress_error(error))
        # Can't be cast so it's removed and stored as NULL
        self.assertNotIn("TEMP1", columns)

    def test_removes_values_out_of_range_for_the_column(self):
        columns = {"COUNT": 2**40}
        client = self._client([("INST__HEALTH_STATUS", columns, 0)], {"INST__HEALTH_STATUS": {"COUNT": "INT"}})
        error = self._error(
            "QWP schema mismatch: integer value 1099511627776 out of range for INT "
            "[column=COUNT, min=-2147483648, max=2147483647]"
        )
        self.assertTrue(client.handle_ingress_error(error))
        self.assertNotIn("COUNT", columns)

    def test_serializes_arrays_to_json(self):
        columns = {"VALUES": [1.0, 2.0]}
        client = self._client([("INST__HEALTH_STATUS", columns, 0)], {"INST__HEALTH_STATUS": {"VALUES": "VARCHAR"}})
        error = self._error("QWP schema mismatch: cannot write DOUBLE_ARRAY to column [column=VALUES, type=VARCHAR]")
        self.assertTrue(client.handle_ingress_error(error))
        self.assertEqual(columns["VALUES"], "[1.0, 2.0]")
        self.assertIn("INST__HEALTH_STATUS__VALUES", client.json_columns)

    def test_leaves_columns_it_cannot_cast_in_other_tables_alone(self):
        health = {"FLAG": "abc"}
        timestamps = {"FLAG": True}
        missing = {"FLAG": 7}
        client = self._client(
            [("INST__HEALTH_STATUS", health, 0), ("INST__ADCS", timestamps, 0), ("INST__NEW", missing, 0)],
            # INST__NEW doesn't have the column yet (QWP adds it)
            {"INST__HEALTH_STATUS": {"FLAG": "LONG"}, "INST__ADCS": {"FLAG": "BOOLEAN"}, "INST__NEW": {}},
        )
        error = self._error("QWP schema mismatch: cannot parse LONG from string [value=abc, column=FLAG]")
        self.assertTrue(client.handle_ingress_error(error))
        self.assertNotIn("FLAG", health)
        self.assertEqual(timestamps, {"FLAG": True})
        self.assertEqual(missing, {"FLAG": 7})

    def test_only_serializes_array_values(self):
        arrays = {"VALUES": [1.0, 2.0]}
        scalars = {"VALUES": 1.5}
        client = self._client(
            [("INST__HEALTH_STATUS", arrays, 0), ("INST__ADCS", scalars, 0)],
            {"INST__HEALTH_STATUS": {"VALUES": "VARCHAR"}, "INST__ADCS": {"VALUES": "DOUBLE"}},
        )
        error = self._error("QWP schema mismatch: cannot write DOUBLE_ARRAY to column [column=VALUES, type=VARCHAR]")
        self.assertTrue(client.handle_ingress_error(error))
        self.assertEqual(arrays["VALUES"], "[1.0, 2.0]")
        self.assertEqual(scalars["VALUES"], 1.5)
        self.assertNotIn("INST__ADCS__VALUES", client.json_columns)

    def test_gives_up_when_no_pending_row_has_the_column(self):
        client = self._client([("INST__HEALTH_STATUS", {"TEMP2": 1}, 0)], {})
        error = self._error("QWP schema mismatch: cannot parse LONG from string [value=abc, column=TEMP1]")
        self.assertFalse(client.handle_ingress_error(error))
        self.assertIn("Could not find column TEMP1 in pending rows", "\n".join(self.logs))


class TestIngestProtocol(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(
            "os.environ",
            {
                "OPENC3_TSDB_HOSTNAME": "127.0.0.1",
                "OPENC3_TSDB_INGEST_PORT": "9000",
                "OPENC3_TSDB_USERNAME": "user",
                "OPENC3_TSDB_PASSWORD": "pass",
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    @patch("openc3.utilities.questdb_client.Sender")
    def test_defaults_to_qwp_over_websocket(self, sender):
        client = QuestDBClient()
        client.connect_ingest()
        args, kwargs = sender.call_args
        self.assertEqual(args[0], Protocol.Ws)
        self.assertEqual(args[1:], ("127.0.0.1", 9000))
        # Only the byte based auto flush stays on, to keep frames under the server's cap
        self.assertEqual(kwargs["auto_flush_rows"], False)
        self.assertEqual(kwargs["auto_flush_interval"], False)
        self.assertNotIn("auto_flush", kwargs)
        self.assertTrue(client.is_qwp)

    @patch("openc3.utilities.questdb_client.Sender")
    def test_selects_ilp_over_http_from_the_environment(self, sender):
        with patch.dict("os.environ", {"OPENC3_TSDB_INGEST_PROTOCOL": "HTTP"}):
            client = QuestDBClient()
        client.connect_ingest()
        self.assertEqual(sender.call_args[0][0], Protocol.Http)
        self.assertEqual(sender.call_args.kwargs["auto_flush"], False)
        self.assertFalse(client.is_qwp)

    def test_rejects_an_unknown_protocol(self):
        with (
            patch.dict("os.environ", {"OPENC3_TSDB_INGEST_PROTOCOL": "tcp"}),
            self.assertRaisesRegex(RuntimeError, "Invalid OPENC3_TSDB_INGEST_PROTOCOL 'tcp'"),
        ):
            QuestDBClient()

    @patch("openc3.utilities.questdb_client.Sender")
    def test_reconnecting_closes_a_rejected_qwp_sender_without_flushing(self, sender):
        client = QuestDBClient()
        client.connect_ingest()
        old = client.ingest
        # A QWP sender refuses every call after a server rejection, including a flushing close
        old.close.side_effect = [QuestDBError(QuestDBErrorCode.ServerRejection, "rejected"), None]
        client.connect_ingest()
        self.assertEqual(old.close.call_args_list[-1].kwargs, {"flush": False})


class TestQwpFlush(unittest.TestCase):
    def _client(self, protocol="ws"):
        client = QuestDBClient.__new__(QuestDBClient)
        client.ingest_protocol = protocol
        client.ingest = MagicMock()
        client.pending_rows = [("TABLE", {"VALUE": 1}, 0)]
        client.pending_values = 1
        client.batch_size = 500
        client.max_pending_values = 500_000
        client._log_warn = lambda msg: None
        return client

    def test_waits_for_the_server_to_acknowledge_the_flush(self):
        client = self._client()
        client.ingest.published_fsn.return_value = 7
        client.ingest.await_acked_fsn.return_value = True
        client.flush()
        client.ingest.await_acked_fsn.assert_called_once_with(7, QuestDBClient.QWP_ACK_TIMEOUT_MS)
        self.assertEqual(client.pending_rows, [])

    def test_keeps_pending_rows_when_the_acknowledgement_times_out(self):
        client = self._client()
        client.ingest.published_fsn.return_value = 7
        client.ingest.await_acked_fsn.return_value = False
        with self.assertRaisesRegex(ConnectionError, "No QWP acknowledgement"):
            client.flush()
        self.assertEqual(len(client.pending_rows), 1)

    def test_does_not_wait_when_nothing_was_ever_published(self):
        client = self._client()
        client.ingest.published_fsn.return_value = None
        client.flush()
        client.ingest.await_acked_fsn.assert_not_called()

    def test_ilp_flush_does_not_wait(self):
        client = self._client("http")
        client.flush()
        client.ingest.published_fsn.assert_not_called()
        client.ingest.await_acked_fsn.assert_not_called()

    def test_starts_a_new_sender_when_a_column_changes_type(self):
        client = self._client()
        client.ingest.published_fsn.return_value = 1
        client.ingest.await_acked_fsn.return_value = True
        old = client.ingest
        old.row.side_effect = QuestDBError(
            QuestDBErrorCode.InvalidApiCall, 'QWP/WebSocket column "VALUE" changes type within a batched table'
        )
        new = MagicMock()

        def connect_ingest():
            client.ingest = new

        client.connect_ingest = connect_ingest
        client.write_row("TABLE", {"VALUE": 2.5}, 1)
        # The earlier row was flushed on the old sender and the new row went to the new one
        old.flush.assert_called_once()
        new.row.assert_called_once()
        self.assertEqual(new.row.call_args.kwargs["columns"], {"VALUE": 2.5})
        self.assertEqual(client.pending_rows, [("TABLE", {"VALUE": 2.5}, 1)])

    def test_other_row_errors_are_raised(self):
        client = self._client()
        client.ingest.row.side_effect = QuestDBError(QuestDBErrorCode.InvalidApiCall, "something else")
        with self.assertRaises(QuestDBError):
            client.write_row("TABLE", {"VALUE": 2.5}, 1)


class TestConvertValueToColumnType(unittest.TestCase):
    """Values are sent as their column's declared type so a QWP sender, which
    fixes each column's type the first time it sees it, never sees a change."""

    def _client(self, column_types):
        client = QuestDBClient.__new__(QuestDBClient)
        client.json_columns = {}
        client.varchar_columns = {}
        client.float_bit_sizes = {}
        client.column_types = {"TABLE": column_types}
        client.truncation_warned = set()
        self.logs = []
        client._log_warn = lambda msg: self.logs.append(msg)
        return client

    def test_sends_ints_and_bools_as_floats_for_float_columns(self):
        client = self._client({"VALUE": "DOUBLE"})
        for value, expected in ((3, 3.0), (True, 1.0)):
            converted, skip = client.convert_value(value, "VALUE", "TABLE")
            self.assertFalse(skip)
            self.assertIs(type(converted), float)
            self.assertEqual(converted, expected)

    def test_sends_bools_and_whole_floats_as_ints_for_integer_columns(self):
        client = self._client({"VALUE": "LONG"})
        self.assertIs(type(client.convert_value(True, "VALUE", "TABLE")[0]), int)
        converted, _ = client.convert_value(3.0, "VALUE", "TABLE")
        self.assertIs(type(converted), int)
        self.assertEqual(converted, 3)
        self.assertEqual(self.logs, [])

    def test_truncates_non_integer_floats_for_integer_columns_and_warns_once(self):
        client = self._client({"VALUE": "INT"})
        self.assertEqual(client.convert_value(3.7, "VALUE", "TABLE")[0], 3)
        self.assertEqual(client.convert_value(4.2, "VALUE", "TABLE")[0], 4)
        self.assertEqual(len(self.logs), 1)
        self.assertIn("Column VALUE in table TABLE is INT but received non-integer value 3.7", self.logs[0])

    def test_stores_non_finite_floats_in_integer_columns_as_null(self):
        client = self._client({"VALUE": "LONG"})
        self.assertIsNone(client.convert_value(float("nan"), "VALUE", "TABLE")[0])

    def test_stores_floats_out_of_the_integer_column_range_as_null(self):
        client = self._client({"VALUE": "INT"})
        self.assertIsNone(client.convert_value(1e30, "VALUE", "TABLE")[0])
        self.assertIsNone(client.convert_value(float(2**31), "VALUE", "TABLE")[0])
        self.assertEqual(client.convert_value(float(2**31 - 1), "VALUE", "TABLE")[0], 2**31 - 1)

    def test_still_encodes_special_values_for_float_columns(self):
        client = self._client({"VALUE": "FLOAT"})
        client.float_bit_sizes = {"TABLE__VALUE": 32}
        self.assertEqual(client.convert_value(float("inf"), "VALUE", "TABLE")[0], FLOAT32_POS_INF_SENTINEL)

    def test_leaves_undeclared_columns_alone(self):
        client = self._client({})
        converted, _ = client.convert_value(3, "OTHER", "TABLE")
        self.assertIs(type(converted), int)


class TestWriteRowBatching(unittest.TestCase):
    """write_row flushes after batch_size rows or max_pending_values values,
    whichever comes first, so wide packets don't buffer unbounded memory."""

    def _client(self, batch_size, max_pending_values):
        client = QuestDBClient.__new__(QuestDBClient)
        client.ingest_protocol = "http"
        client.ingest = MagicMock()
        client.pending_rows = []
        client.pending_values = 0
        client.batch_size = batch_size
        client.max_pending_values = max_pending_values
        return client

    def test_defaults(self):
        client = QuestDBClient()
        self.assertEqual(client.batch_size, 5000)
        self.assertEqual(client.max_pending_values, 500_000)

    def test_flushes_after_batch_size_rows(self):
        client = self._client(batch_size=3, max_pending_values=1000)
        flushed = [client.write_row("TABLE", {"A": n}, n) for n in range(3)]
        self.assertEqual(flushed, [False, False, True])
        client.ingest.flush.assert_called_once()
        self.assertEqual((client.pending_rows, client.pending_values), ([], 0))

    def test_flushes_after_max_pending_values(self):
        client = self._client(batch_size=1000, max_pending_values=10)
        wide = {f"ITEM{i}": i for i in range(4)}
        flushed = [client.write_row("TABLE", dict(wide), n) for n in range(3)]
        # 4, 8, then 12 values >= 10
        self.assertEqual(flushed, [False, False, True])
        client.ingest.flush.assert_called_once()

    def test_restarts_the_count_when_pending_rows_are_cleared_elsewhere(self):
        client = self._client(batch_size=1000, max_pending_values=10)
        client.write_row("TABLE", {f"ITEM{i}": i for i in range(8)}, 0)
        # Error recovery in TsdbMicroservice drops the pending rows directly
        client.pending_rows.clear()
        self.assertFalse(client.write_row("TABLE", {f"ITEM{i}": i for i in range(8)}, 1))
        self.assertEqual(client.pending_values, 8)
