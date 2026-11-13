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
Ingest and query benchmarks for comparing QuestDB server versions, ingest
protocols (ILP/HTTP vs QWP/WebSocket) and commit modes (nosync vs adaptive).

Everything goes through QuestDBClient (create_table, process_json_data,
write_row, flush) the same way TsdbMicroservice does, so the numbers reflect
what COSMOS actually sees rather than the raw client library.

Scenarios:
  - bulk_wide: one wide telemetry packet (raw, converted and formatted values)
    flushed every DEFAULT_BATCH_SIZE rows, like a busy TsdbMicroservice.
  - interleaved: many packets round-robin into one batch, so each flush
    commits to many tables at once.
  - flush_latency: small flushes to one table (the TsdbMicroservice flush
    period on a quiet system). This is the worst case for adaptive commit mode,
    which flushes the WAL files on every commit.
  - back_orbit: a dump of stored packets (mostly one packet with a few event
    packets) whose timestamps are earlier than the live data already in the
    table, while live packets keep arriving. QuestDB has to merge the dump into
    the existing data (out-of-order writes), into an older day partition for
    the prior_day variant.
  - queries: the read patterns of the cmd-tlm-api (full range, SAMPLE BY,
    latest row) against the bulk_wide table.

These are skipped unless OPENC3_TSDB_PERF=1 since they take a few minutes.

Run with:
    1. Start QuestDB (pick the version and commit mode to measure):
         QUESTDB_VERSION=10.2.0 QDB_CAIRO_COMMIT_MODE=adaptive \\
           docker compose -f docker-compose.test.yml up -d --force-recreate questdb
    2. Run (from openc3/python), labelling the run:
         OPENC3_TSDB_PERF=1 OPENC3_TSDB_PERF_LABEL=10.2.0-qwp-adaptive \\
           uv run pytest ../test/integration/tsdb/python/test_perf_ingest.py -v -s
       Results are appended to OPENC3_TSDB_PERF_RESULTS
       (default: openc3/test/integration/tsdb/perf_results.jsonl).
    3. Compare runs:
         uv run python ../test/integration/tsdb/helpers/compare_perf.py

Tuning (env vars): OPENC3_TSDB_PERF_ROWS (bulk_wide rows, default 50000),
OPENC3_TSDB_PERF_TABLES (interleaved tables, default 20),
OPENC3_TSDB_PERF_FLUSHES (flush_latency flushes, default 300),
OPENC3_TSDB_PERF_REPEAT (query repetitions, default 5),
OPENC3_TSDB_PERF_BATCH_SIZE (rows per write_row flush, default QuestDBClient.DEFAULT_BATCH_SIZE).
"""

import json
import os
import platform
import statistics
import sys
import time
from datetime import datetime, timezone

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

from conftest import requires_questdb  # noqa: E402


PERF_ENABLED = os.environ.get("OPENC3_TSDB_PERF") == "1"
LABEL = os.environ.get("OPENC3_TSDB_PERF_LABEL", "unlabelled")
RESULTS_FILE = os.environ.get(
    "OPENC3_TSDB_PERF_RESULTS",
    os.path.join(os.path.dirname(__file__), "..", "perf_results.jsonl"),
)
BULK_ROWS = int(os.environ.get("OPENC3_TSDB_PERF_ROWS", "50000"))
INTERLEAVED_TABLES = int(os.environ.get("OPENC3_TSDB_PERF_TABLES", "20"))
FLUSHES = int(os.environ.get("OPENC3_TSDB_PERF_FLUSHES", "300"))
QUERY_REPEAT = int(os.environ.get("OPENC3_TSDB_PERF_REPEAT", "5"))
BATCH_SIZE = int(os.environ["OPENC3_TSDB_PERF_BATCH_SIZE"]) if os.environ.get("OPENC3_TSDB_PERF_BATCH_SIZE") else None

# Server settings recorded with each result (commit mode and its tuning)
SERVER_PARAMETERS = {
    "commit_mode": "cairo.commit.mode",
    "group_window": "cairo.adaptive.commit.group.window",
    "epoch_interval": "cairo.adaptive.epoch.interval",
    "writeback_drain": "cairo.wal.commit.writeback.drain",
    "shared_workers": "shared.worker.count",
}

pytestmark = [
    requires_questdb,
    pytest.mark.skipif(not PERF_ENABLED, reason="Set OPENC3_TSDB_PERF=1 to run the TSDB benchmarks"),
]

# Packet timestamps are spaced 1ms apart starting at a fixed time so every run
# writes the same partitions and SAMPLE BY buckets.
BASE_TS_NS = int(datetime(2026, 1, 1, tzinfo=timezone.utc).timestamp() * 1_000_000_000)
ROW_SPACING_NS = 1_000_000


def _wide_packet_def(item_count=30):
    """Packet resembling a typical health and status packet.

    A third of the items are UINT 16 with a FLOAT read conversion and units
    (raw int, converted double, formatted varchar), a third are FLOAT 32 with
    units (float plus formatted varchar), and a third are UINT 8 with states
    (raw int plus converted varchar). Plus one 32-bit counter and one string.
    """
    items = [
        {"name": "COUNTER", "data_type": "UINT", "bit_size": 32},
        {"name": "LABEL", "data_type": "STRING", "bit_size": 0},
    ]
    for i in range(item_count):
        kind = i % 3
        if kind == 0:
            items.append(
                {
                    "name": f"TEMP{i}",
                    "data_type": "UINT",
                    "bit_size": 16,
                    "read_conversion": {"converted_type": "FLOAT", "converted_bit_size": 64},
                    "units": "C",
                }
            )
        elif kind == 1:
            items.append({"name": f"VOLT{i}", "data_type": "FLOAT", "bit_size": 32, "units": "V"})
        else:
            items.append({"name": f"MODE{i}", "data_type": "UINT", "bit_size": 8, "states": {"OFF": 0, "ON": 1}})
    return {"items": items}


def _wide_packet_json(packet_def, n):
    """Decommutated json_data for one packet, as the decom microservice publishes it."""
    data = {}
    for item in packet_def["items"]:
        name = item["name"]
        if name == "COUNTER":
            data[name] = n
        elif name == "LABEL":
            data[name] = f"PKT{n % 100}"
        elif name.startswith("TEMP"):
            raw = (n * 7) % 65536
            data[name] = raw
            data[f"{name}__C"] = raw * 0.01 - 20.0
            data[f"{name}__F"] = f"{raw * 0.01 - 20.0:.2f} C"
        elif name.startswith("VOLT"):
            value = ((n * 13) % 1000) / 100.0
            data[name] = value
            data[f"{name}__F"] = f"{value:.2f} V"
        else:
            raw = n % 2
            data[name] = raw
            data[f"{name}__C"] = "ON" if raw else "OFF"
    return data


def _new_client(questdb_client_cls):
    client = questdb_client_cls(batch_size=BATCH_SIZE)
    client.connect_ingest()
    client.connect_query()
    return client


def _query_one(client, sql):
    with client.query.cursor() as cur:
        cur.execute(sql)
        return cur.fetchone()


def _wait_for_rows(client, table_name, expected, timeout=120.0):
    """Wait until WAL apply makes *expected* rows visible. Returns seconds waited."""
    start = time.perf_counter()
    while time.perf_counter() - start < timeout:
        try:
            if _query_one(client, f'SELECT count() FROM "{table_name}"')[0] >= expected:
                return time.perf_counter() - start
        except Exception:
            pass
        time.sleep(0.05)
    pytest.fail(f"Timed out waiting for {expected} rows in {table_name}")


def _server_info(client):
    info = {}
    try:
        info["server_version"] = _query_one(client, "SELECT build()")[0]
    except Exception as exc:
        info["server_version"] = f"unknown ({exc})"
    # Older servers don't report the adaptive settings (or SHOW PARAMETERS)
    for key in SERVER_PARAMETERS:
        info[key] = "not reported"
    try:
        with client.query.cursor() as cur:
            cur.execute("SELECT property_path, value FROM (SHOW PARAMETERS)")
            parameters = dict(cur.fetchall())
        for key, path in SERVER_PARAMETERS.items():
            if path in parameters:
                info[key] = parameters[path]
    except Exception:
        pass
    return info


def _client_info(client):
    import questdb

    sender = client.ingest
    protocol = getattr(client, "ingest_protocol", None) or "http"
    return {
        "client_version": getattr(questdb, "__version__", "unknown"),
        "protocol": protocol,
        "sender": type(sender).__name__,
    }


def _record(scenario, metrics, client):
    result = {
        "label": LABEL,
        "scenario": scenario,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "host": platform.node(),
        **_server_info(client),
        **_client_info(client),
        **metrics,
    }
    print(f"\n  [{LABEL}] {scenario}: " + ", ".join(f"{k}={v}" for k, v in metrics.items()))
    with open(RESULTS_FILE, "a") as f:
        f.write(json.dumps(result) + "\n")
    return result


def _percentile(values, pct):
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round(pct / 100.0 * (len(ordered) - 1))))
    return ordered[index]


def _drop(client, table_name):
    with client.query.cursor() as cur:
        cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')


@pytest.fixture(scope="module")
def perf_client():
    from openc3.utilities.questdb_client import QuestDBClient

    client = _new_client(QuestDBClient)
    yield client
    client.close()


class TestPerfIngest:
    BULK_TABLE = "DEFAULT__TLM__PERF__BULK_WIDE"

    def test_bulk_wide(self, perf_client):
        client = perf_client
        packet_def = _wide_packet_def()
        _drop(client, self.BULK_TABLE)
        client.create_table("PERF", "BULK_WIDE", packet_def)
        # Pre-build the json so the timing measures QuestDBClient + server, not the generator
        payloads = [_wide_packet_json(packet_def, n) for n in range(BULK_ROWS)]

        start = time.perf_counter()
        for n, json_data in enumerate(payloads):
            values = client.process_json_data(json_data, self.BULK_TABLE)
            ts = BASE_TS_NS + n * ROW_SPACING_NS
            client.write_row(self.BULK_TABLE, values, ts, ts + 500_000)
        client.flush()
        ingest_s = time.perf_counter() - start
        visible_s = _wait_for_rows(client, self.BULK_TABLE, BULK_ROWS)

        columns = len(client.process_json_data(payloads[0], self.BULK_TABLE)) + 2
        _record(
            "bulk_wide",
            {
                "rows": BULK_ROWS,
                "columns": columns,
                "batch_size": client.batch_size,
                "ingest_s": round(ingest_s, 3),
                "ingest_rows_per_s": round(BULK_ROWS / ingest_s),
                "visible_after_s": round(visible_s, 3),
                "end_to_end_rows_per_s": round(BULK_ROWS / (ingest_s + visible_s)),
            },
            client,
        )

    def test_interleaved_tables(self, perf_client):
        client = perf_client
        packet_def = _wide_packet_def(item_count=9)
        rows_per_table = max(1, BULK_ROWS // INTERLEAVED_TABLES)
        tables = []
        for t in range(INTERLEAVED_TABLES):
            table_name = f"DEFAULT__TLM__PERF__MULTI_{t}"
            _drop(client, table_name)
            client.create_table("PERF", f"MULTI_{t}", packet_def)
            tables.append(table_name)
        payloads = [_wide_packet_json(packet_def, n) for n in range(rows_per_table)]

        start = time.perf_counter()
        for n, json_data in enumerate(payloads):
            ts = BASE_TS_NS + n * ROW_SPACING_NS
            for table_name in tables:
                values = client.process_json_data(json_data, table_name)
                client.write_row(table_name, values, ts, ts + 500_000)
        client.flush()
        ingest_s = time.perf_counter() - start
        visible_s = 0.0
        for table_name in tables:
            visible_s += _wait_for_rows(client, table_name, rows_per_table)
        total = rows_per_table * INTERLEAVED_TABLES

        _record(
            "interleaved",
            {
                "rows": total,
                "tables": INTERLEAVED_TABLES,
                "batch_size": client.batch_size,
                "ingest_s": round(ingest_s, 3),
                "ingest_rows_per_s": round(total / ingest_s),
                "visible_after_s": round(visible_s, 3),
                "end_to_end_rows_per_s": round(total / (ingest_s + visible_s)),
            },
            client,
        )
        for table_name in tables:
            _drop(client, table_name)

    @pytest.mark.parametrize("rows_per_flush", [1, 10, 100])
    def test_flush_latency(self, perf_client, rows_per_flush):
        client = perf_client
        packet_def = _wide_packet_def()
        table_name = f"DEFAULT__TLM__PERF__FLUSH_{rows_per_flush}"
        _drop(client, table_name)
        client.create_table("PERF", f"FLUSH_{rows_per_flush}", packet_def)
        payloads = [_wide_packet_json(packet_def, n) for n in range(rows_per_flush)]

        latencies_ms = []
        n = 0
        for _ in range(FLUSHES):
            for json_data in payloads:
                values = client.process_json_data(json_data, table_name)
                ts = BASE_TS_NS + n * ROW_SPACING_NS
                client.write_row(table_name, values, ts, ts + 500_000)
                n += 1
            start = time.perf_counter()
            client.flush()
            latencies_ms.append((time.perf_counter() - start) * 1000.0)
        _wait_for_rows(client, table_name, n)

        _record(
            f"flush_latency_{rows_per_flush}",
            {
                "flushes": FLUSHES,
                "rows_per_flush": rows_per_flush,
                "flush_p50_ms": round(statistics.median(latencies_ms), 3),
                "flush_p95_ms": round(_percentile(latencies_ms, 95), 3),
                "flush_p99_ms": round(_percentile(latencies_ms, 99), 3),
                "flush_max_ms": round(max(latencies_ms), 3),
                "rows_per_s": round(n / (sum(latencies_ms) / 1000.0)),
            },
            client,
        )
        _drop(client, table_name)


def _event_packet_def():
    """Small event packet: an id, a severity, a message and a value."""
    return {
        "items": [
            {"name": "EVENT_ID", "data_type": "UINT", "bit_size": 16},
            {"name": "SEVERITY", "data_type": "UINT", "bit_size": 8, "states": {"INFO": 0, "WARN": 1, "ERROR": 2}},
            {"name": "MESSAGE", "data_type": "STRING", "bit_size": 0},
            {"name": "VALUE", "data_type": "FLOAT", "bit_size": 32},
        ]
    }


def _event_packet_json(n):
    return {
        "EVENT_ID": n % 1000,
        "SEVERITY": n % 3,
        "SEVERITY__C": ("INFO", "WARN", "ERROR")[n % 3],
        "MESSAGE": f"Event {n} occurred during the pass",
        "VALUE": n / 7.0,
    }


class TestPerfBackOrbit:
    """Back orbit (stored) telemetry dumped all at once.

    The packet table already has 10 minutes of live data at 10 Hz starting at
    noon. The dump is `dump` packets at 1 Hz from earlier the same day (09:00)
    or from the previous day, with 2% event packets spread over 3 event tables.
    A live packet keeps arriving after every 10 dump packets.
    """

    LIVE_HZ = 10
    LIVE_SEED_S = 600
    EVENT_EVERY = 50
    LIVE_EVERY = 10
    EVENT_TABLES = 3

    @pytest.mark.parametrize("dump", [1000, 5000])
    @pytest.mark.parametrize("variant", ["same_day", "prior_day"])
    def test_back_orbit(self, perf_client, variant, dump):
        client = perf_client
        hour_ns = 3600 * 1_000_000_000
        noon = BASE_TS_NS + 12 * hour_ns
        dump_start = BASE_TS_NS + (9 if variant == "same_day" else -15) * hour_ns

        packet_def = _wide_packet_def()
        # Distinct names per case: ILP/HTTP silently drops rows written to a
        # table that was dropped and recreated while its connection stayed open
        suffix = f"{variant.upper()}_{dump}"
        table_name = f"DEFAULT__TLM__PERF__BACK_ORBIT_{suffix}"
        event_tables = [f"DEFAULT__TLM__PERF__EVENT_{e}_{suffix}" for e in range(self.EVENT_TABLES)]
        for name in [table_name, *event_tables]:
            _drop(client, name)
        client.create_table("PERF", f"BACK_ORBIT_{suffix}", packet_def)
        for e in range(self.EVENT_TABLES):
            client.create_table("PERF", f"EVENT_{e}_{suffix}", _event_packet_def())

        # Live data already in the table before the dump arrives
        live_spacing = 1_000_000_000 // self.LIVE_HZ
        seed = self.LIVE_SEED_S * self.LIVE_HZ
        for n in range(seed):
            ts = noon + n * live_spacing
            client.write_row(table_name, client.process_json_data(_wide_packet_json(packet_def, n), table_name), ts, ts)
        client.flush()
        _wait_for_rows(client, table_name, seed)

        # The dump, with events and live packets mixed in, in arrival order
        messages = []
        live = seed
        events = 0
        for n in range(dump):
            messages.append((table_name, _wide_packet_json(packet_def, n), dump_start + n * 1_000_000_000))
            if n % self.EVENT_EVERY == 0:
                event_table = event_tables[events % self.EVENT_TABLES]
                messages.append((event_table, _event_packet_json(n), dump_start + n * 1_000_000_000 + 1))
                events += 1
            if n % self.LIVE_EVERY == 0:
                messages.append((table_name, _wide_packet_json(packet_def, live), noon + live * live_spacing))
                live += 1

        start = time.perf_counter()
        for name, json_data, ts in messages:
            client.write_row(name, client.process_json_data(json_data, name), ts, ts)
        client.flush()
        ingest_s = time.perf_counter() - start
        visible_s = _wait_for_rows(client, table_name, live + dump)
        for e, name in enumerate(event_tables):
            visible_s += _wait_for_rows(client, name, len(range(e, events, self.EVENT_TABLES)))

        _record(
            f"back_orbit_{variant}_{dump}",
            {
                "rows": len(messages),
                "dump": dump,
                "events": events,
                "live": live - seed,
                "batch_size": client.batch_size,
                "ingest_s": round(ingest_s, 3),
                "ingest_rows_per_s": round(len(messages) / ingest_s),
                "visible_after_s": round(visible_s, 3),
                "end_to_end_rows_per_s": round(len(messages) / (ingest_s + visible_s)),
            },
            client,
        )
        for name in [table_name, *event_tables]:
            _drop(client, name)


class TestPerfQuery:
    """Read patterns from the cmd-tlm-api against the bulk_wide table.

    Depends on TestPerfIngest.test_bulk_wide having populated the table.
    """

    TABLE = TestPerfIngest.BULK_TABLE

    def _time_query(self, client, sql):
        timings_ms = []
        rows = 0
        for _ in range(QUERY_REPEAT):
            start = time.perf_counter()
            with client.query.cursor() as cur:
                cur.execute(sql)
                rows = len(cur.fetchall())
            timings_ms.append((time.perf_counter() - start) * 1000.0)
        return statistics.median(timings_ms), rows

    def test_queries(self, perf_client):
        client = perf_client
        try:
            count = _query_one(client, f'SELECT count() FROM "{self.TABLE}"')[0]
        except Exception:
            pytest.skip("bulk_wide table missing, run test_bulk_wide first")
        if count < BULK_ROWS:
            pytest.skip("bulk_wide table incomplete, run test_bulk_wide first")

        start_iso = datetime.fromtimestamp(BASE_TS_NS / 1e9, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        end_ns = BASE_TS_NS + BULK_ROWS * ROW_SPACING_NS
        end_iso = datetime.fromtimestamp(end_ns / 1e9, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        where = f"WHERE PACKET_TIMESECONDS >= '{start_iso}' AND PACKET_TIMESECONDS < '{end_iso}'"
        queries = {
            "select_star": f'SELECT *, CAST(PACKET_TIMESECONDS AS LONG) as "__pkt_time_ns" FROM "{self.TABLE}" {where}',
            "select_items": (
                f'SELECT CAST(PACKET_TIMESECONDS AS LONG), "TEMP0__C", "VOLT1", "MODE2__C" FROM "{self.TABLE}" {where}'
            ),
            "sample_by_1s": (
                f'SELECT PACKET_TIMESECONDS, min("TEMP0__C"), max("TEMP0__C"), avg("TEMP0__C"), '
                f'stddev("TEMP0__C"), min("VOLT1"), max("VOLT1"), avg("VOLT1") '
                f'FROM "{self.TABLE}" {where} SAMPLE BY 1s'
            ),
            "latest": f'SELECT * FROM "{self.TABLE}" LIMIT -1',
            "count": f'SELECT count() FROM "{self.TABLE}" {where}',
        }
        metrics = {}
        for name, sql in queries.items():
            median_ms, rows = self._time_query(client, sql)
            metrics[f"{name}_ms"] = round(median_ms, 2)
            metrics[f"{name}_rows"] = rows
        _record("queries", metrics, client)
