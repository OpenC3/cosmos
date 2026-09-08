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

from openc3.utilities.questdb_client import QuestDBClient


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
