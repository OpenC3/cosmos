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
QuestDB writer helper for cross-language testing.

This script is called from Ruby tests to insert test data into QuestDB
using the Python QuestDBClient. It outputs JSON with the test parameters
that Ruby can use to verify the round-trip.

Usage:
    python questdb_writer.py <command> [options]

Commands:
    write       Write test data to QuestDB
    cleanup     Drop a test table

Examples:
    # Write integer test data
    python questdb_writer.py write --target TEST --packet INT32 \
        --data_type INT --bit_size 32 --values '[-100, 0, 100]'

    # Write with converted values
    python questdb_writer.py write --target TEST --packet FLOAT32 \
        --data_type FLOAT --bit_size 32 --values '[1.5, 2.5]' \
        --converted_values '[150.0, 250.0]'

    # Cleanup
    python questdb_writer.py cleanup --table TEST__INT32
"""

import argparse
import base64
import json
import os
import sys
import time
from datetime import datetime, timezone

# Add openc3 python path for imports
# Path: openc3/test/integration/tsdb/helpers -> openc3/python
script_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(script_dir, "..", "..", "..", "..", "python"))

# Set environment variables for QuestDB connection (test defaults)
os.environ.setdefault("OPENC3_TSDB_HOSTNAME", "127.0.0.1")
os.environ.setdefault("OPENC3_TSDB_INGEST_PORT", "9000")
os.environ.setdefault("OPENC3_TSDB_QUERY_PORT", "8812")
os.environ.setdefault("OPENC3_TSDB_USERNAME", "admin")
os.environ.setdefault("OPENC3_TSDB_PASSWORD", "admin")

from openc3.utilities.questdb_client import QuestDBClient


class QuietQuestDBClient(QuestDBClient):
    """QuestDBClient that suppresses INFO/WARN log output to stderr for clean JSON output."""

    def _log_info(self, msg):
        # Suppress info logs during test writes
        print(f"INFO: {msg}", file=sys.stderr)

    def _log_warn(self, msg):
        print(f"WARN: {msg}", file=sys.stderr)

    def _log_error(self, msg):
        print(f"ERROR: {msg}", file=sys.stderr)


def ts_to_iso(ts_ns: int) -> str:
    """Convert nanosecond timestamp to ISO string for QuestDB queries."""
    ts_us = ts_ns // 1000
    ts_s = ts_us / 1_000_000
    return datetime.fromtimestamp(ts_s, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%S.%fZ"
    )


def create_packet_def(items):
    """Create a packet definition dict."""
    return {"items": items}


def create_item(
    name,
    data_type,
    bit_size=None,
    array_size=None,
    states=None,
    read_conversion=None,
    format_string=None,
    units=None,
):
    """Create an item definition for a packet."""
    item = {"name": name, "data_type": data_type}
    if bit_size is not None:
        item["bit_size"] = bit_size
    if array_size is not None:
        item["array_size"] = array_size
    if states is not None:
        item["states"] = states
    if read_conversion is not None:
        item["read_conversion"] = read_conversion
    if format_string is not None:
        item["format_string"] = format_string
    if units is not None:
        item["units"] = units
    return item


def wait_for_data(client, table_name, expected_count, timeout=5.0):
    """Wait for data to be visible in QuestDB.

    Args:
        client: QuestDB client with query connection
        table_name: Name of the table to check
        expected_count: Minimum number of rows expected
        timeout: Maximum time to wait in seconds
    """
    start = time.time()
    while time.time() - start < timeout:
        try:
            with client.query.cursor() as cur:
                cur.execute(f'SELECT count() FROM "{table_name}"')
                count = cur.fetchone()[0]
                if count >= expected_count:
                    return count
        except Exception:
            pass
        time.sleep(0.1)
    return 0


def cmd_write(args):
    """Write test data to QuestDB."""
    client = QuietQuestDBClient()
    client.connect_ingest()
    client.connect_query()

    target_name = args.target
    packet_name = args.packet
    table_name = f"{target_name}__{packet_name}"

    # Parse values
    values = json.loads(args.values)
    converted_values = (
        json.loads(args.converted_values) if args.converted_values else None
    )
    formatted_values = (
        json.loads(args.formatted_values) if args.formatted_values else None
    )

    # Build item definition
    item_kwargs = {
        "name": "VALUE",
        "data_type": args.data_type,
    }
    if args.bit_size:
        item_kwargs["bit_size"] = args.bit_size
    if args.array_size:
        item_kwargs["array_size"] = args.array_size
    if args.states:
        item_kwargs["states"] = json.loads(args.states)
    if args.read_conversion:
        item_kwargs["read_conversion"] = json.loads(args.read_conversion)
    if args.format_string:
        item_kwargs["format_string"] = args.format_string
    if args.units:
        item_kwargs["units"] = args.units

    packet_def = create_packet_def([create_item(**item_kwargs)])

    # Drop existing table for clean state
    try:
        with client.query.cursor() as cur:
            cur.execute(f'DROP TABLE IF EXISTS "{table_name}"')
    except Exception:
        pass

    # Create table
    table_name = client.create_table(target_name, packet_name, packet_def)

    # Generate timestamp
    ts = int(time.time() * 1e9)
    ts_iso = ts_to_iso(ts)

    # Handle binary values (base64 encoded in JSON)
    if args.data_type == "BLOCK":
        values = [base64.b64decode(v) if isinstance(v, str) else v for v in values]

    # Write rows
    for i, val in enumerate(values):
        columns = client.process_json_data({"VALUE": val}, table_name)
        columns["RECEIVED_COUNT"] = i

        # Add converted value if provided
        if converted_values and i < len(converted_values):
            conv_val = converted_values[i]
            columns["VALUE__C"] = conv_val

        # Add formatted value if provided
        if formatted_values and i < len(formatted_values):
            fmt_val = formatted_values[i]
            columns["VALUE__F"] = fmt_val

        row_ts = ts + i * 1_000_000_000
        # Pass rx_timestamp_ns so the RECEIVED_TIME* items can be tested
        client.write_row(table_name, columns, row_ts, rx_timestamp_ns=row_ts)

    client.flush()

    # Wait for data to be visible
    actual_count = wait_for_data(client, table_name, len(values))

    client.close()

    # Prepare expected values for output
    # Convert bytes back to base64 for JSON serialization
    expected_values = []
    for v in values:
        if isinstance(v, bytes):
            expected_values.append({"__base64__": base64.b64encode(v).decode("ascii")})
        else:
            expected_values.append(v)

    # Output result as JSON
    result = {
        "success": actual_count >= len(values),
        "table_name": table_name,
        "target_name": target_name,
        "packet_name": packet_name,
        "start_time": ts_iso,
        "end_time": ts_to_iso(ts + len(values) * 1_000_000_000),
        "row_count": actual_count,
        "expected_values": expected_values,
        "expected_converted": converted_values,
        "expected_formatted": formatted_values,
        "packet_def": packet_def,
    }
    print(json.dumps(result))


def cmd_cleanup(args):
    """Drop a test table."""
    client = QuestDBClient()
    client.connect_query()

    try:
        with client.query.cursor() as cur:
            cur.execute(f'DROP TABLE IF EXISTS "{args.table}"')
        result = {"success": True, "table": args.table}
    except Exception as e:
        result = {"success": False, "table": args.table, "error": str(e)}

    client.close()
    print(json.dumps(result))


def cmd_check():
    """Check if QuestDB is available."""
    try:
        import psycopg

        conn = psycopg.connect(
            host=os.environ.get("OPENC3_TSDB_HOSTNAME", "127.0.0.1"),
            port=int(os.environ.get("OPENC3_TSDB_QUERY_PORT", "8812")),
            user=os.environ.get("OPENC3_TSDB_USERNAME", "admin"),
            password=os.environ.get("OPENC3_TSDB_PASSWORD", "admin"),
            dbname="qdb",
            autocommit=True,
            connect_timeout=2,
        )
        conn.close()
        print(json.dumps({"available": True}))
    except Exception as e:
        print(json.dumps({"available": False, "error": str(e)}))


def main():
    parser = argparse.ArgumentParser(
        description="QuestDB writer helper for cross-language testing"
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Write command
    write_parser = subparsers.add_parser("write", help="Write test data to QuestDB")
    write_parser.add_argument("--target", required=True, help="Target name")
    write_parser.add_argument("--packet", required=True, help="Packet name")
    write_parser.add_argument(
        "--data_type",
        required=True,
        help="COSMOS data type (INT, UINT, FLOAT, STRING, BLOCK, DERIVED)",
    )
    write_parser.add_argument("--bit_size", type=int, help="Bit size for numeric types")
    write_parser.add_argument(
        "--array_size", type=int, help="Array size (if array item)"
    )
    write_parser.add_argument(
        "--values", required=True, help="JSON array of values to write"
    )
    write_parser.add_argument(
        "--converted_values", help="JSON array of converted values"
    )
    write_parser.add_argument(
        "--formatted_values", help="JSON array of formatted values"
    )
    write_parser.add_argument("--states", help="JSON object of state definitions")
    write_parser.add_argument(
        "--read_conversion", help="JSON object for read conversion"
    )
    write_parser.add_argument(
        "--format_string", help="Format string for formatted values"
    )
    write_parser.add_argument("--units", help="Units string")

    # Cleanup command
    cleanup_parser = subparsers.add_parser("cleanup", help="Drop a test table")
    cleanup_parser.add_argument("--table", required=True, help="Table name to drop")

    # Check command
    subparsers.add_parser("check", help="Check if QuestDB is available")

    args = parser.parse_args()

    if args.command == "write":
        cmd_write(args)
    elif args.command == "cleanup":
        cmd_cleanup(args)
    elif args.command == "check":
        cmd_check()
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
