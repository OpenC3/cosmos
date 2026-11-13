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
A batch of wide packets can be larger than the QWP frame cap the server
advertises (about 2 MB by default). QuestDBClient must still write the whole
batch rather than having the flush refused.
"""

import os
import sys
import time


# Add openc3 python path for imports
# Path: openc3/test/integration/tsdb/python -> openc3/python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "python"))

os.environ.setdefault("OPENC3_TSDB_HOSTNAME", "127.0.0.1")
os.environ.setdefault("OPENC3_TSDB_INGEST_PORT", "9000")
os.environ.setdefault("OPENC3_TSDB_QUERY_PORT", "8812")
os.environ.setdefault("OPENC3_TSDB_USERNAME", "admin")
os.environ.setdefault("OPENC3_TSDB_PASSWORD", "admin")
os.environ.setdefault("OPENC3_SCOPE", "DEFAULT")

from conftest import requires_questdb  # noqa: E402


ITEMS = 2000


@requires_questdb
def test_batch_larger_than_the_frame_cap(questdb_client, clean_table, wait_for_data):
    table_name = clean_table("DEFAULT__TLM__LARGE__WIDE")
    packet = {"items": [{"name": f"ITEM{i}", "data_type": "FLOAT", "bit_size": 64} for i in range(ITEMS)]}
    questdb_client.create_table("LARGE", "WIDE", packet)

    # About 8 MB (2000 doubles plus overhead per row). The value cap flushes every
    # 250 rows, which is still about 4 MB per flush, twice the frame cap.
    rows = 500
    base_ts = int(time.time() * 1e9)
    for n in range(rows):
        values = questdb_client.process_json_data({f"ITEM{i}": n + i / 10 for i in range(ITEMS)}, table_name)
        questdb_client.write_row(table_name, values, base_ts + n)
    questdb_client.flush()
    assert questdb_client.pending_rows == []

    wait_for_data(questdb_client, table_name, rows)
    with questdb_client.query.cursor() as cur:
        cur.execute(f'SELECT count(), sum("ITEM0"), sum("ITEM1999") FROM "{table_name}"')
        count, first, last = cur.fetchone()
    assert count == rows
    assert first == sum(range(rows))
    assert abs(last - (sum(range(rows)) + rows * 199.9)) < 1e-6
