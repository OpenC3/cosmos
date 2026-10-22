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

#!/usr/bin/env python3
"""
Insert backdated INST HEALTH_STATUS TEMP1 rows into QuestDB so the
partition detach/attach workflow documented in docs/guides/backups.md
can be exercised end to end.

Data is written via the QuestDB ILP HTTP endpoint. Rows are spread
evenly across N past days starting --start-days-ago days in the past
and moving forward. Each daily partition (PARTITION BY DAY) ends up
with --rows-per-day rows of synthetic TEMP1 telemetry.

By default QuestDB port 9000 is NOT exposed on the host (see the
commented "127.0.0.1:9000:9000" line in compose.yaml). The easiest way
to run this script is from inside any container on the openc3 network,
where DNS resolves openc3-tsdb and the OPENC3_TSDB_* env vars are
already set:

    docker cp scripts/insert_questdb_test_data.py \\
        cosmos-openc3-operator-1:/tmp/insert_questdb_test_data.py
    docker exec -e OPENC3_TSDB_HOSTNAME=openc3-tsdb \\
        cosmos-openc3-operator-1 \\
        python3 /tmp/insert_questdb_test_data.py --days 5 --verify

To run from the host instead, uncomment the 9000 port mapping in
compose.yaml, restart, and supply --host 127.0.0.1 with the real
OPENC3_TSDB_USERNAME / OPENC3_TSDB_PASSWORD values.

After inserting, verify partitions in the COSMOS Admin Console TSDB
tab (or via curl) with:

    SELECT name, minTimestamp, maxTimestamp, numRows
      FROM table_partitions('DEFAULT__TLM__INST__HEALTH_STATUS');

Then exercise the workflow from docs/guides/backups.md:

    ALTER TABLE 'DEFAULT__TLM__INST__HEALTH_STATUS' DETACH PARTITION LIST '<date>';
    # ...archive .detached directory, rename to .attachable, restore...
    ALTER TABLE 'DEFAULT__TLM__INST__HEALTH_STATUS' ATTACH PARTITION LIST '<date>';
"""

import argparse
import base64
import ipaddress
import math
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--host", default=os.environ.get("OPENC3_TSDB_HOSTNAME", "127.0.0.1"))
    p.add_argument("--port", type=int, default=int(os.environ.get("OPENC3_TSDB_INGEST_PORT", "9000")))
    p.add_argument(
        "--tls",
        action="store_true",
        help="Connect with HTTPS. QuestDB open source only serves plain HTTP, so this is off by default.",
    )
    p.add_argument("--user", default=os.environ.get("OPENC3_TSDB_USERNAME", "admin"))
    p.add_argument("--password", default=os.environ.get("OPENC3_TSDB_PASSWORD", "admin"))
    p.add_argument("--scope", default="DEFAULT")
    p.add_argument("--target", default="INST")
    p.add_argument("--packet", default="HEALTH_STATUS")
    p.add_argument(
        "--item",
        default="TEMP1",
        help="Column to populate. TEMP1 is INT (raw); TEMP1__C is DOUBLE (converted).",
    )
    p.add_argument(
        "--int",
        dest="is_int",
        action="store_true",
        default=True,
        help="Treat values as integers (ILP `i` suffix). Default true for TEMP1.",
    )
    p.add_argument(
        "--float",
        dest="is_int",
        action="store_false",
        help="Treat values as doubles (no suffix). Use with TEMP1__C.",
    )
    p.add_argument("--days", type=int, default=5, help="Number of daily partitions to populate")
    p.add_argument("--rows-per-day", type=int, default=24, help="Rows per day (evenly spaced)")
    p.add_argument(
        "--start-days-ago",
        type=int,
        default=10,
        help="How many days in the past the first partition starts",
    )
    p.add_argument("--batch", type=int, default=500, help="Rows per HTTP POST batch")
    p.add_argument("--verify", action="store_true", help="Print partition listing after insert")
    return p.parse_args()


def build_ilp_line(table, item, value, ts_ns, is_int):
    """Build one ILP line. Designated timestamp (PACKET_TIMESECONDS) trails the line.

    ILP requires an `i` suffix on integer fields; floats are written bare.
    """
    field = f"{int(value)}i" if is_int else f"{value:.4f}"
    return f"{table} {item}={field} {ts_ns}"


def questdb_url(host, port, tls, path, query=""):
    """Build the QuestDB HTTP URL, refusing anything but a local/private QuestDB.

    This is a test-data script for a local COSMOS install, so the host must
    resolve only to loopback or private addresses (e.g. openc3-tsdb on the
    docker network). That keeps a bad --host from sending credentials and
    requests to an arbitrary external server.
    """
    if not 0 < port < 65536:
        raise ValueError(f"Invalid port: {port}")
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except socket.gaierror as e:
        raise ValueError(f"Cannot resolve host {host!r}: {e}") from e
    for info in infos:
        addr = ipaddress.ip_address(info[4][0])
        if not (addr.is_loopback or addr.is_private):
            raise ValueError(f"Host {host!r} resolves to non-local address {addr}; refusing to connect")
    netloc = f"[{host}]:{port}" if ":" in host else f"{host}:{port}"
    scheme = "https" if tls else "http"
    return urllib.parse.urlunsplit((scheme, netloc, path, query, ""))


def post_ilp(host, port, tls, user, password, body):
    url = questdb_url(host, port, tls, "/write")
    req = urllib.request.Request(url, data=body.encode("utf-8"), method="POST")
    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {auth}")
    req.add_header("Content-Type", "text/plain")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")


def query_exec(host, port, tls, user, password, sql):
    url = questdb_url(host, port, tls, "/exec", urllib.parse.urlencode({"query": sql}))
    req = urllib.request.Request(url)
    auth = base64.b64encode(f"{user}:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {auth}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def main():
    args = parse_args()
    table = f"{args.scope}__TLM__{args.target}__{args.packet}"
    try:
        write_url = questdb_url(args.host, args.port, args.tls, "/write")
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    now = datetime.now(timezone.utc)
    first_day = (now - timedelta(days=args.start_days_ago)).replace(hour=0, minute=0, second=0, microsecond=0)
    day_step_ns = int(timedelta(days=1).total_seconds() * 1e9)
    row_step_ns = day_step_ns // max(1, args.rows_per_day)
    total = args.days * args.rows_per_day

    print(f"Table:         {table}")
    print(f"Endpoint:      {write_url}")
    print(f"Item:          {args.item}")
    print(f"Days:          {args.days}  Rows/day: {args.rows_per_day}  Total rows: {total}")
    print(f"First day UTC: {first_day.isoformat()}")
    print(f"Last day UTC:  {(first_day + timedelta(days=args.days - 1)).isoformat()}")
    print()

    base_ns = int(first_day.timestamp() * 1e9)
    lines = []
    written = 0
    t_start = time.time()
    for day in range(args.days):
        for i in range(args.rows_per_day):
            ts_ns = base_ns + day * day_step_ns + i * row_step_ns
            # Synthetic sinusoidal TEMP1 around 25 C with daily phase
            value = 25.0 + 5.0 * math.sin((i / args.rows_per_day) * 2 * math.pi) + day * 0.1
            lines.append(build_ilp_line(table, args.item, value, ts_ns, args.is_int))
            if len(lines) >= args.batch:
                status, body = post_ilp(
                    args.host, args.port, args.tls, args.user, args.password, "\n".join(lines) + "\n"
                )
                if status >= 300:
                    print(f"ILP error {status}: {body}", file=sys.stderr)
                    sys.exit(1)
                written += len(lines)
                lines = []
                print(f"  wrote {written}/{total} rows...")

    if lines:
        status, body = post_ilp(args.host, args.port, args.tls, args.user, args.password, "\n".join(lines) + "\n")
        if status >= 300:
            print(f"ILP error {status}: {body}", file=sys.stderr)
            sys.exit(1)
        written += len(lines)

    elapsed = time.time() - t_start
    print(f"Done. Wrote {written} rows in {elapsed:.1f}s.")

    if args.verify:
        # ILP HTTP flushes asynchronously to disk; give the WAL a moment to commit
        time.sleep(2)
        print("\nPartitions:")
        sql = f"SELECT name, minTimestamp, maxTimestamp, numRows FROM table_partitions('{table}') ORDER BY minTimestamp"
        try:
            print(query_exec(args.host, args.port, args.tls, args.user, args.password, sql))
        except Exception as e:
            print(f"Verify query failed: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
