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

"""Copy command rows from another COSMOS release's TSDB into this one's.

A standby release that follows the active release's telemetry never receives its
commands, so its {scope}__CMD__ tables fall behind. This copies the rows the
destination doesn't have yet, table by table and db_shard by db_shard. It assumes
nothing else writes to the destination's command tables, so the newest row in
each destination table marks where to resume.

Run it in the destination release, where the OPENC3_TSDB_* variables point at
the destination TSDB:

    python -m openc3.utilities.tsdb_cmd_sync --source-host openc3-tsdb-SHARDNUM.openc3-tsdb.openc3.svc.cluster.local

The source credentials default to the destination's. Set SOURCE_TSDB_USERNAME
and SOURCE_TSDB_PASSWORD when they differ.
"""

import argparse
import contextlib
import os
import sys
from collections.abc import Callable
from decimal import Decimal
from typing import Any
from uuid import UUID

import psycopg
from questdb import TimestampMicros, TimestampNanos

from openc3.utilities.logger import Logger
from openc3.utilities.questdb_client import QuestDBClient


TIME_COLUMN = "PACKET_TIMESECONDS"
DEFAULT_PAGE_SIZE = 10_000

# Units of the long that cast(<column> as long) returns, in nanoseconds
TIMESTAMP_TYPE_NSEC = {"TIMESTAMP_NS": 1, "TIMESTAMP": 1_000, "DATE": 1_000_000}
INTEGER_TYPES = {"BYTE", "SHORT", "INT", "LONG"}
FLOAT_TYPES = {"FLOAT", "DOUBLE"}
STRING_TYPES = {"VARCHAR", "STRING", "SYMBOL"}


class SyncError(Exception):
    pass


def log(message: str) -> None:
    print(message, flush=True)


def base_type(column_type: str) -> str:
    """Upcase a QuestDB type and drop parameters, e.g. 'decimal(20,0)' -> 'DECIMAL'."""
    return column_type.upper().split("(")[0].strip()


def convert_value(value: Any, source_type: str, dest_type: str) -> Any:
    """Convert a value read from the source into what the ingest Sender expects
    for the destination column. Timestamp values arrive as longs (see select_sql).

    Raises:
        SyncError: If the destination type isn't supported or the value can't be converted.
    """
    if (source_type in TIMESTAMP_TYPE_NSEC) != (dest_type in TIMESTAMP_TYPE_NSEC):
        raise SyncError(f"can't convert {source_type} to {dest_type}")
    if dest_type in TIMESTAMP_TYPE_NSEC:
        nsec = int(value) * TIMESTAMP_TYPE_NSEC[source_type]
        if dest_type == "TIMESTAMP_NS":
            return TimestampNanos(nsec)
        if dest_type == "TIMESTAMP":
            return TimestampMicros(nsec // 1_000)
        raise SyncError("DATE columns are not supported")
    if dest_type in INTEGER_TYPES:
        if isinstance(value, float) and not value.is_integer():
            raise SyncError(f"{value} is not an integer")
        return int(value)
    if dest_type in FLOAT_TYPES:
        return float(value)
    if dest_type in STRING_TYPES:
        return str(value)
    if dest_type == "BOOLEAN":
        return bool(value)
    if dest_type == "DECIMAL":
        return Decimal(str(value))
    if dest_type == "UUID":
        return UUID(str(value))
    raise SyncError(f"{dest_type} columns are not supported")


def quote(name: str) -> str:
    if '"' in name:
        raise SyncError(f"Invalid name: {name}")
    return f'"{name}"'


def select_sql(table: str, columns: list[str], source_types: dict[str, str]) -> str:
    """Select the given columns, with timestamps as longs so nanoseconds aren't lost."""
    selects = []
    for column in columns:
        if source_types[column] in TIMESTAMP_TYPE_NSEC:
            selects.append(f"cast({quote(column)} as long)")
        else:
            selects.append(quote(column))
    return f"SELECT {', '.join(selects)} FROM {quote(table)}"


def get_columns(cursor: Any, table: str) -> dict[str, str] | None:
    """Return {column: base type} for a table, or None if it doesn't exist.

    Checks tables() rather than catching the SHOW COLUMNS error, so a dropped
    connection raises instead of looking like a missing table.
    """
    cursor.execute("SELECT table_name FROM tables() WHERE table_name = %s", [table])
    if cursor.fetchone() is None:
        return None
    cursor.execute(f"SHOW COLUMNS FROM {quote(table)}")
    return {row[0]: base_type(row[1]) for row in cursor.fetchall()}


def latest_time_nsec(cursor: Any, table: str, time_type: str) -> int | None:
    cursor.execute(f"SELECT cast(max({quote(TIME_COLUMN)}) as long) FROM {quote(table)}")
    row = cursor.fetchone()
    if row is None or row[0] is None:
        return None
    return int(row[0]) * TIMESTAMP_TYPE_NSEC[time_type]


def command_tables(cursor: Any, scopes: list[str] | None) -> list[str]:
    cursor.execute("SELECT table_name FROM tables()")
    tables = []
    for (name,) in cursor.fetchall():
        parts = name.split("__")
        if len(parts) >= 4 and parts[1] == "CMD" and (not scopes or parts[0] in scopes):
            tables.append(name)
    return sorted(tables)


def read_page(cursor: Any, sql: str, after_nsec: int | None, page_size: int) -> list[tuple]:
    """Read up to page_size rows newer than after_nsec, oldest first. The time
    column is the first column of each row, in the source's units.
    """
    params: list[Any] = []
    if after_nsec is not None:
        sql += f" WHERE {quote(TIME_COLUMN)} > %s"
        params.append(QuestDBClient.nsec_to_iso(after_nsec))
    sql += f" ORDER BY {quote(TIME_COLUMN)} LIMIT {page_size}"
    cursor.execute(sql, params or None)
    return cursor.fetchall()


def complete_rows(rows: list[tuple], page_size: int) -> list[tuple]:
    """Drop the trailing rows that share the last time of a full page, so the next
    page (which starts after the last copied time) doesn't skip their duplicates.
    """
    if len(rows) < page_size:
        return rows
    last = rows[-1][0]
    keep = len(rows)
    while keep > 0 and rows[keep - 1][0] == last:
        keep -= 1
    if keep == 0:
        raise SyncError(f"More than {page_size} rows share one time, increase --page-size")
    return rows[:keep]


def ingest_rows(
    dest: QuestDBClient, table: str, fields: list[tuple[str, str, str]], source_nsec: int, rows: list[tuple]
) -> None:
    """Write rows to the destination. fields holds (column, source type, destination type)
    for each column after the time column.
    """
    if dest.ingest is None:
        raise SyncError("Destination ingest is not connected")
    ingest = dest.ingest
    # Convert the whole page before writing any of it, so a value that can't be
    # converted fails the page without leaving part of it in the sender's buffer
    converted_rows = []
    for row in rows:
        symbols = {}
        values = {}
        for (column, source_type, dest_type), value in zip(fields, row[1:], strict=True):
            if value is None:
                continue
            converted = convert_value(value, source_type, dest_type)
            if dest_type == "SYMBOL":
                symbols[column] = converted
            else:
                values[column] = converted
        converted_rows.append((symbols or None, values, TimestampNanos(int(row[0]) * source_nsec)))
    for symbols, values, at in converted_rows:
        ingest.row(table, symbols=symbols, columns=values, at=at)
    dest.flush()


def sync_table(
    source: Any,
    dest: QuestDBClient,
    table: str,
    page_size: int = DEFAULT_PAGE_SIZE,
    dry_run: bool = False,
    warn: Callable[[str], None] = log,
) -> int:
    """Copy the source rows newer than the destination's newest row.

    Returns:
        The number of rows copied (or that would be copied, with dry_run).
    """
    if dest.query is None:
        raise SyncError("Destination query is not connected")
    with source.cursor() as source_cursor, dest.query.cursor() as dest_cursor:
        source_types = get_columns(source_cursor, table)
        dest_types = get_columns(dest_cursor, table)
        if source_types is None:
            return 0
        if dest_types is None:
            warn(f"{table}: not on the destination, skipped (is the command defined there?)")
            return 0
        for side, types in (("source", source_types), ("destination", dest_types)):
            if types.get(TIME_COLUMN) not in TIMESTAMP_TYPE_NSEC:
                raise SyncError(f"{table} has no {TIME_COLUMN} timestamp on the {side}")

        missing = sorted(set(source_types) - set(dest_types))
        if missing:
            warn(f"{table}: destination has no column {', '.join(missing)}, values not copied")
        # The time column comes first, for read_page and complete_rows
        columns = [TIME_COLUMN] + [c for c in source_types if c in dest_types and c != TIME_COLUMN]
        fields = [(c, source_types[c], dest_types[c]) for c in columns[1:]]
        source_nsec = TIMESTAMP_TYPE_NSEC[source_types[TIME_COLUMN]]
        sql = select_sql(table, columns, source_types)

        after_nsec = latest_time_nsec(dest_cursor, table, dest_types[TIME_COLUMN])
        copied = 0
        while True:
            rows = complete_rows(read_page(source_cursor, sql, after_nsec, page_size), page_size)
            if not rows:
                return copied
            if not dry_run:
                ingest_rows(dest, table, fields, source_nsec, rows)
            copied += len(rows)
            after_nsec = int(rows[-1][0]) * source_nsec


def sync_db_shard(db_shard: int, args: argparse.Namespace) -> bool:
    """Sync every command table on one db_shard. Returns False if any table failed."""
    source_host = args.source_host.replace("SHARDNUM", str(db_shard))
    log(f"db_shard {db_shard}: copying command rows from {source_host}")
    source = None
    dest = QuestDBClient(name="TSDB_CMD_SYNC", db_shard=db_shard)
    ok = True
    try:
        source = psycopg.connect(
            host=source_host,
            port=args.source_port,
            user=os.environ.get("SOURCE_TSDB_USERNAME") or os.environ.get("OPENC3_TSDB_USERNAME"),
            password=os.environ.get("SOURCE_TSDB_PASSWORD") or os.environ.get("OPENC3_TSDB_PASSWORD"),
            dbname="qdb",
            autocommit=True,
        )
        dest.connect_query()
        if not args.dry_run:
            dest.connect_ingest()
        with source.cursor() as cursor:
            tables = command_tables(cursor, args.scope)
        total = 0
        for table in tables:
            try:
                copied = sync_table(source, dest, table, args.page_size, args.dry_run)
            except Exception as error:
                ok = False
                log(f"{table}: FAILED: {error}")
                # A rejected batch leaves the sender unusable. Discard what's still
                # buffered rather than sending it: a partial page can end partway
                # through a time, and the next run resumes after the newest time
                # written, skipping the rest of the rows at that time.
                if not args.dry_run:
                    if dest.ingest is not None:
                        with contextlib.suppress(Exception):
                            dest.ingest.close(flush=False)
                        dest.ingest = None
                    dest.connect_ingest()
                continue
            if copied:
                log(f"{table}: {'would copy' if args.dry_run else 'copied'} {copied} rows")
            total += copied
        log(f"db_shard {db_shard}: {total} rows from {len(tables)} command tables")
    finally:
        if source is not None:
            source.close()
        dest.close()
    return ok


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="python -m openc3.utilities.tsdb_cmd_sync",
        description="Copy command rows from another COSMOS release's TSDB into this one's",
    )
    parser.add_argument(
        "--source-host",
        default=os.environ.get("SOURCE_TSDB_HOSTNAME"),
        help="Source TSDB hostname, with SHARDNUM for the db_shard number (default SOURCE_TSDB_HOSTNAME)",
    )
    parser.add_argument(
        "--source-port",
        default=os.environ.get("SOURCE_TSDB_QUERY_PORT") or os.environ.get("OPENC3_TSDB_QUERY_PORT") or "8812",
        help="Source TSDB PostgreSQL port (default SOURCE_TSDB_QUERY_PORT, then OPENC3_TSDB_QUERY_PORT)",
    )
    parser.add_argument(
        "--db-shards",
        type=int,
        default=1,
        help="Number of db_shards to sync, starting at 0 (default 1)",
    )
    parser.add_argument("--scope", action="append", help="Only sync this scope (repeatable, default all scopes)")
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE, help="Rows read per query")
    parser.add_argument("--dry-run", action="store_true", help="Count the rows to copy without writing them")
    args = parser.parse_args(argv)
    if not args.source_host:
        parser.error("--source-host or SOURCE_TSDB_HOSTNAME is required")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    # Keep the Logger from publishing to Redis, which this job has no credentials for.
    # OPENC3_NO_STORE can't do it: openc3/__init__ reads it before this module runs.
    Logger.instance().no_store = True
    ok = True
    for db_shard in range(args.db_shards):
        try:
            ok = sync_db_shard(db_shard, args) and ok
        except Exception as error:
            # Can't reach a TSDB, so try the remaining db_shards
            ok = False
            log(f"db_shard {db_shard}: FAILED: {error}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
