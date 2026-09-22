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


class TestTsdbLookupDbShards(unittest.TestCase):
    ITEMS = [
        ["INST", "HEALTH_STATUS", "TEMP1", "CONVERTED", None],
        ["INST2", "HEALTH_STATUS", "TEMP1", "CONVERTED", None],
        ["INST", "HEALTH_STATUS", "TEMP2", "CONVERTED", None],
    ]

    def setUp(self):
        # INST is on db_shard 0 and INST2 is on db_shard 1
        patcher = patch.object(
            QuestDBClient,
            "db_shard_for_target",
            side_effect=lambda target_name, scope: 1 if target_name == "INST2" else 0,
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def lookup(self, results, **kwargs):
        with patch.object(QuestDBClient, "_tsdb_lookup_single_db_shard") as single:
            single.side_effect = lambda items, db_shard, **_kw: results[db_shard]
            return QuestDBClient.tsdb_lookup(self.ITEMS, start_time="2026-09-13T00:00:00Z", **kwargs), single

    def test_uses_the_single_db_shard_fast_path(self):
        with patch.object(QuestDBClient, "_tsdb_lookup_single_db_shard", return_value="result") as single:
            items = [self.ITEMS[0], self.ITEMS[2]]
            self.assertEqual(
                QuestDBClient.tsdb_lookup(items, start_time="2026-09-13T00:00:00Z", scope="OTHER"), "result"
            )
        single.assert_called_once()
        self.assertEqual(single.call_args.kwargs["db_shard"], 0)
        self.assertEqual(single.call_args.kwargs["scope"], "OTHER")
        self.assertEqual(single.call_args[0][0][1].item_name, "TEMP2")

    def test_queries_each_db_shard_and_merges_a_single_row(self):
        result, single = self.lookup({0: [[[1.0, None], [3.0, "RED"]]], 1: [[[2.0, None]]]})
        self.assertEqual(result, [[1.0, None], [2.0, None], [3.0, "RED"]])
        self.assertEqual(single.call_count, 2)
        shards = {call.kwargs["db_shard"]: call[0][0] for call in single.call_args_list}
        self.assertEqual([item.item_name for item in shards[0]], ["TEMP1", "TEMP2"])
        self.assertEqual([item.target_name for item in shards[1]], ["INST2"])
        for call in single.call_args_list:
            self.assertFalse(call.kwargs["flatten"])

    def test_merges_multiple_rows_filling_missing_rows_with_nones(self):
        result, _ = self.lookup(
            {0: [[[1.0, None], [3.0, None]], [[4.0, None], [6.0, None]]], 1: [[[2.0, None]]]},
            end_time="2026-09-13T01:00:00Z",
        )
        self.assertEqual(
            result,
            [
                [[1.0, None], [2.0, None], [3.0, None]],
                [[4.0, None], [None, None], [6.0, None]],
            ],
        )

    def test_merges_array_values(self):
        # An array item's value is itself a list which must not be mistaken for a row
        result, _ = self.lookup(
            {0: [[[[1, 2], None], [[5, 6], None]]], 1: [[[[3, 4], None]]]}, end_time="2026-09-13T01:00:00Z"
        )
        self.assertEqual(result, [[[1, 2], None], [[3, 4], None], [[5, 6], None]])

    def test_fills_a_db_shard_with_no_results_with_nones(self):
        result, _ = self.lookup({0: [[[1.0, None], [3.0, None]]], 1: {}})
        self.assertEqual(result, [[1.0, None], [None, None], [3.0, None]])

    def test_returns_empty_when_no_db_shard_has_results(self):
        result, _ = self.lookup({0: {}, 1: {}}, end_time="2026-09-13T01:00:00Z")
        self.assertEqual(result, {})


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
