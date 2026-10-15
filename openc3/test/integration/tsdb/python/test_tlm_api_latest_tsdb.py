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

"""
End-to-end tests for historical get_tlm_values with LATEST items.

LATEST must return the value from whichever packet containing the item was
received most recently at the requested time, not the packet received most
recently now, and not just the first packet in the QuestDB ASOF JOIN.

Run with:
    1. Start QuestDB: docker compose -f docker-compose.test.yml up -d
    2. Run tests: uv run pytest ../test/integration/tsdb/python/test_tlm_api_latest_tsdb.py (from openc3/python)
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

os.environ.setdefault("OPENC3_TSDB_HOSTNAME", "127.0.0.1")
os.environ.setdefault("OPENC3_TSDB_INGEST_PORT", "9000")
os.environ.setdefault("OPENC3_TSDB_QUERY_PORT", "8812")
os.environ.setdefault("OPENC3_TSDB_USERNAME", "admin")
os.environ.setdefault("OPENC3_TSDB_PASSWORD", "admin")
os.environ.setdefault("OPENC3_SCOPE", "DEFAULT")

from conftest import requires_questdb

from openc3.api.tlm_api import get_tlm_values
from openc3.models.target_model import TargetModel
from openc3.utilities.questdb_client import QuestDBClient


TARGET = "PY_LT"
PACKET_DEF = {"items": [{"name": "VALUE", "data_type": "INT", "bit_size": 32}]}
# Only PKT_B has units so only it has a formatted (VALUE__F) column
UNITS_PACKET_DEF = {"items": [{"name": "VALUE", "data_type": "INT", "bit_size": 32, "units": "degC"}]}
PACKET_DEFS = {"PKT_A": PACKET_DEF, "PKT_B": UNITS_PACKET_DEF, "REGULAR": PACKET_DEF}
# Timeline in ms from the base time (VALUE written to each packet)
ROWS = {
    "PKT_A": [(0, 1), (2000, 3)],
    "PKT_B": [(1000, 2), (3000, 4)],  # Formatted as '2 degC' and '4 degC'
    "REGULAR": [(500, 10), (1500, 20), (2500, 30), (3500, 40)],
}


def ts_to_iso(ts_ns):
    return datetime.fromtimestamp(ts_ns / 1e9, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


@requires_questdb
class TestTlmApiLatestTsdb:
    @pytest.fixture
    def base_ns(self, questdb_client, clean_table, wait_for_data):
        # Align to microseconds since ts_to_iso drops nanoseconds and could round the range start past the first row
        base_ns = time.time_ns() // 1000 * 1000
        for packet_name, rows in ROWS.items():
            table_name, _ = QuestDBClient.sanitize_table_name(TARGET, packet_name)
            clean_table(table_name)
            questdb_client.create_table(TARGET, packet_name, PACKET_DEFS[packet_name])
            for i, (offset_ms, value) in enumerate(rows):
                columns = questdb_client.process_json_data({"VALUE": value}, table_name)
                columns["RECEIVED_COUNT"] = i
                if packet_name == "PKT_B":
                    columns["VALUE__F"] = f"{value} degC"
                questdb_client.write_row(table_name, columns, base_ns + offset_ms * 1_000_000)
        questdb_client.flush()
        for packet_name, rows in ROWS.items():
            table_name, _ = QuestDBClient.sanitize_table_name(TARGET, packet_name)
            assert wait_for_data(questdb_client, table_name, len(rows)) >= len(rows)
        with (
            patch.object(TargetModel, "packet", side_effect=lambda _tgt, packet_name, **_kw: PACKET_DEFS[packet_name]),
            patch.object(TargetModel, "get_item_to_packet_map", return_value={"VALUE": ["PKT_A", "PKT_B"]}),
            patch("openc3.api.tlm_api.authorize"),
        ):
            yield base_ns
        QuestDBClient.disconnect()

    def at(self, base_ns, offset_ms):
        return ts_to_iso(base_ns + offset_ms * 1_000_000)

    def test_returns_the_packet_received_most_recently_at_a_point_in_time(self, base_ns):
        assert get_tlm_values([f"{TARGET}__LATEST__VALUE__RAW"], start_time=self.at(base_ns, 2500)) == [[3, None]]

    def test_returns_a_packet_received_after_the_last_row_of_the_first_candidate(self, base_ns):
        # PKT_A was last received at 2000 but PKT_B at 3000 so PKT_B is the latest at 3500
        assert get_tlm_values([f"{TARGET}__LATEST__VALUE__RAW"], start_time=self.at(base_ns, 3500)) == [[4, None]]

    def test_returns_formatted_from_a_candidate_with_a_formatted_value(self, base_ns):
        vals = get_tlm_values([f"{TARGET}__LATEST__VALUE__FORMATTED"], start_time=self.at(base_ns, 3500))
        assert vals == [["4 degC", None]]

    def test_returns_raw_from_a_candidate_without_a_formatted_value(self, base_ns):
        assert get_tlm_values([f"{TARGET}__LATEST__VALUE__FORMATTED"], start_time=self.at(base_ns, 2500)) == [[3, None]]

    def test_returns_formatted_from_each_candidate_as_available_in_a_range(self, base_ns):
        vals = get_tlm_values(
            [f"{TARGET}__LATEST__VALUE__FORMATTED", f"{TARGET}__REGULAR__VALUE__RAW"],
            start_time=self.at(base_ns, 0),
            end_time=self.at(base_ns, 4000),
        )
        assert [row[0][0] for row in vals] == [1, "2 degC", 3, "4 degC"]

    def test_returns_latest_alongside_a_regular_item_at_a_point_in_time(self, base_ns):
        vals = get_tlm_values(
            [f"{TARGET}__LATEST__VALUE__RAW", f"{TARGET}__REGULAR__VALUE__RAW"], start_time=self.at(base_ns, 3600)
        )
        assert vals == [[4, None], [40, None]]

    def test_returns_the_latest_packet_at_each_row_of_a_range_driven_by_a_regular_item(self, base_ns):
        vals = get_tlm_values(
            [f"{TARGET}__LATEST__VALUE__RAW", f"{TARGET}__REGULAR__VALUE__RAW"],
            start_time=self.at(base_ns, 0),
            end_time=self.at(base_ns, 4000),
        )
        assert vals == [
            [[1, None], [10, None]],
            [[2, None], [20, None]],
            [[3, None], [30, None]],
            [[4, None], [40, None]],
        ]
