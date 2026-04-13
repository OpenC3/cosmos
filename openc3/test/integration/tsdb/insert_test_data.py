#!/usr/bin/env python3
"""Insert test telemetry data into QuestDB for gap analysis testing.

Finds the earliest timestamp in DEFAULT__TLM__INST__HEALTH_STATUS and inserts
rows backwards from that point for a given number of hours. Includes optional
gaps to exercise the Analyze Data Gap feature.

Usage:
    python insert_test_data.py --hours 48
    python insert_test_data.py --hours 48 --gap-start 12 --gap-duration 6
    python insert_test_data.py --hours 48 --gap-start 12 --gap-duration 6 --gap-start 30 --gap-duration 3

Requirements:
    pip install "psycopg[binary]"  # or: uv pip install "psycopg[binary]"
"""

import argparse
import math
import random
import sys
from datetime import datetime, timedelta, timezone

import psycopg

TABLE = "DEFAULT__TLM__INST__HEALTH_STATUS"
HOST = "127.0.0.1"
PORT = 8812
USER = "openc3quest"
PASSWORD = "openc3questpassword"


def get_earliest_timestamp(cur):
    cur.execute(f"SELECT first(PACKET_TIMESECONDS) as ts FROM '{TABLE}';")
    row = cur.fetchone()
    if row and row[0]:
        return row[0]
    return None


def build_gap_set(gap_starts, gap_durations, interval_seconds):
    """Return a set of hour-offsets (from start) that fall inside a gap."""
    skip = set()
    for start_h, dur_h in zip(gap_starts, gap_durations):
        gap_begin = int(start_h * 3600 / interval_seconds)
        gap_end = int((start_h + dur_h) * 3600 / interval_seconds)
        for i in range(gap_begin, gap_end):
            skip.add(i)
    return skip


def generate_temp1(t):
    """Generate a sinusoidal TEMP1 value that varies over time."""
    hours = t.timestamp() / 3600
    return round(50 + 30 * math.sin(hours * 0.3) + random.uniform(-2, 2), 4)


def insert_data(cur, start_time, hours, gap_starts, gap_durations, interval_seconds):
    skip = build_gap_set(gap_starts, gap_durations, interval_seconds)
    total_points = int(hours * 3600 / interval_seconds)
    inserted = 0
    skipped = 0
    batch = []
    batch_size = 500

    for i in range(total_points):
        if i in skip:
            skipped += 1
            continue
        t = start_time - timedelta(seconds=i * interval_seconds)
        ts_iso = t.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        temp1 = generate_temp1(t)
        batch.append((ts_iso, temp1))
        inserted += 1

        if len(batch) >= batch_size:
            _flush_batch(cur, batch)
            batch.clear()

    if batch:
        _flush_batch(cur, batch)

    return inserted, skipped


def _flush_batch(cur, batch):
    values = ", ".join(
        f"('{ts}', {temp1})" for ts, temp1 in batch
    )
    cur.execute(
        f"INSERT INTO '{TABLE}' (PACKET_TIMESECONDS, TEMP1__C) VALUES {values};"
    )


def main():
    parser = argparse.ArgumentParser(
        description="Insert test data into QuestDB HEALTH_STATUS table"
    )
    parser.add_argument(
        "--hours", type=float, required=True, help="Number of hours of data to insert going backwards"
    )
    parser.add_argument(
        "--interval", type=int, default=10, help="Seconds between data points (default: 10)"
    )
    parser.add_argument(
        "--gap-start",
        type=float,
        action="append",
        default=[],
        help="Hours from start where a gap begins (repeatable)",
    )
    parser.add_argument(
        "--gap-duration",
        type=float,
        action="append",
        default=[],
        help="Duration of gap in hours (repeatable, pairs with --gap-start)",
    )
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--user", default=USER)
    parser.add_argument("--password", default=PASSWORD)
    args = parser.parse_args()

    if len(args.gap_start) != len(args.gap_duration):
        print("Error: each --gap-start must have a matching --gap-duration", file=sys.stderr)
        sys.exit(1)

    conninfo = f"host={args.host} port={args.port} user={args.user} password={args.password} dbname=qdb"
    print(f"Connecting to QuestDB at {args.host}:{args.port} ...")

    with psycopg.connect(conninfo, autocommit=True) as conn:
        with conn.cursor() as cur:
            earliest = get_earliest_timestamp(cur)
            if earliest:
                # Ensure timezone-aware
                if earliest.tzinfo is None:
                    earliest = earliest.replace(tzinfo=timezone.utc)
                print(f"Earliest existing timestamp: {earliest.isoformat()}")
                start_time = earliest - timedelta(seconds=args.interval)
            else:
                start_time = datetime.now(timezone.utc)
                print(f"Table empty, starting from now: {start_time.isoformat()}")

            end_time = start_time - timedelta(hours=args.hours)
            print(f"Inserting data from {start_time.isoformat()} backwards to {end_time.isoformat()}")
            print(f"Interval: {args.interval}s | Points: ~{int(args.hours * 3600 / args.interval)}")

            if args.gap_start:
                for gs, gd in zip(args.gap_start, args.gap_duration):
                    gap_from = start_time - timedelta(hours=gs)
                    gap_to = start_time - timedelta(hours=gs + gd)
                    print(f"Gap: {gap_from.isoformat()} to {gap_to.isoformat()} ({gd}h)")

            inserted, skipped = insert_data(
                cur, start_time, args.hours, args.gap_start, args.gap_duration, args.interval
            )
            print(f"Done. Inserted: {inserted} rows, Skipped (gaps): {skipped} rows")


if __name__ == "__main__":
    main()
