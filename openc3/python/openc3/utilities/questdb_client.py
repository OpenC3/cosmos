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
Shared QuestDB client for connection management, table creation, and data ingestion.
Used by both TsdbMicroservice (real-time) and MigrationMicroservice (historical data).
"""

import base64
import contextlib
import json
import math
import os
import re
import threading
import time
from datetime import datetime, timezone
from decimal import Decimal

import numpy
import psycopg
from psycopg.rows import dict_row
from questdb.ingress import Protocol, Sender, TimestampNanos


# Sentinel values for storing float special values (inf, -inf, nan) in QuestDB.
# QuestDB stores these as NULL, so we use sentinel values near float max instead.
# 64-bit double sentinels (for FLOAT 64-bit columns)
FLOAT64_POS_INF_SENTINEL = 1.7976931348623155e308
FLOAT64_NEG_INF_SENTINEL = -1.7976931348623155e308
FLOAT64_NAN_SENTINEL = -1.7976931348623153e308

# 32-bit float sentinels (for FLOAT 32-bit columns)
# These are the values to write; they'll be truncated to 32-bit precision on storage
FLOAT32_POS_INF_SENTINEL = 3.4028233e38
FLOAT32_NEG_INF_SENTINEL = -3.4028233e38
FLOAT32_NAN_SENTINEL = -3.4028231e38

# What we'll read back after 32-bit storage (for comparison on read)
FLOAT32_POS_INF_STORED = 3.4028232635611926e38
FLOAT32_NEG_INF_STORED = -3.4028232635611926e38
FLOAT32_NAN_STORED = -3.4028230607370965e38


def encode_float_special_values(value, bit_size=64):
    """
    Convert float special values (inf, -inf, nan) to sentinel values for QuestDB storage.

    Args:
        value: The float value to potentially encode
        bit_size: 32 for single precision, 64 for double precision

    Returns:
        The value with special values replaced by sentinels
    """
    if not isinstance(value, float):
        return value

    if bit_size == 32:
        if math.isinf(value):
            return FLOAT32_POS_INF_SENTINEL if value > 0 else FLOAT32_NEG_INF_SENTINEL
        if math.isnan(value):
            return FLOAT32_NAN_SENTINEL
    else:
        if math.isinf(value):
            return FLOAT64_POS_INF_SENTINEL if value > 0 else FLOAT64_NEG_INF_SENTINEL
        if math.isnan(value):
            return FLOAT64_NAN_SENTINEL

    return value


def decode_float_special_values(value):
    """
    Convert sentinel values back to float special values (inf, -inf, nan).

    Checks against both 32-bit and 64-bit sentinel values since we may not
    know the original column type at read time.

    Args:
        value: The float value to potentially decode

    Returns:
        The value with sentinels replaced by special values
    """
    if not isinstance(value, float):
        return value

    # Check 64-bit sentinels
    if value == FLOAT64_POS_INF_SENTINEL:
        return float("inf")
    if value == FLOAT64_NEG_INF_SENTINEL:
        return float("-inf")
    if value == FLOAT64_NAN_SENTINEL:
        return float("nan")

    # Check 32-bit sentinels (stored values after precision loss)
    if value == FLOAT32_POS_INF_STORED:
        return float("inf")
    if value == FLOAT32_NEG_INF_STORED:
        return float("-inf")
    if value == FLOAT32_NAN_STORED:
        return float("nan")

    return value


class QuestDBClient:
    """
    QuestDB client for managing connections and data ingestion.

    Provides:
    - HTTP ILP connection for high-throughput writes
    - PostgreSQL connection for queries and DDL
    - Table creation from packet definitions
    - Value conversion and sanitization
    - Schema-safe ingestion with error handling
    """

    # Special timestamp items that are calculated from PACKET_TIMESECONDS/RECEIVED_TIMESECONDS columns
    # rather than stored as separate columns. PACKET_TIMESECONDS and RECEIVED_TIMESECONDS are stored
    # as timestamp_ns columns and need conversion to float seconds on read. The TIMEFORMATTED items
    # are derived from these timestamp columns.
    TIMESTAMP_ITEMS = {
        "PACKET_TIMEFORMATTED": {"source": "PACKET_TIMESECONDS", "format": "formatted"},
        "RECEIVED_TIMEFORMATTED": {
            "source": "RECEIVED_TIMESECONDS",
            "format": "formatted",
        },
    }

    # Stored timestamp items that are stored as timestamp_ns columns and need
    # conversion to float seconds on read. Distinguished from calculated items above.
    STORED_TIMESTAMP_ITEMS = frozenset(["PACKET_TIMESECONDS", "RECEIVED_TIMESECONDS"])

    # Class-level shared connection for query operations (singleton pattern)
    _shared_conn = None
    _shared_conn_mutex = threading.Lock()

    # Class-level shared connection for query operations (singleton pattern)
    _shared_conn = None
    _shared_conn_mutex = threading.Lock()

    @staticmethod
    def _create_query_connection(**extra_kwargs):
        """Create a new psycopg connection to QuestDB using standard env vars.

        Args:
            **extra_kwargs: Additional keyword arguments passed to psycopg.connect
                (e.g., autocommit=True, connect_timeout=2).

        Returns:
            A new psycopg connection.
        """
        return psycopg.connect(
            host=os.environ.get("OPENC3_TSDB_HOSTNAME"),
            port=os.environ.get("OPENC3_TSDB_QUERY_PORT"),
            user=os.environ.get("OPENC3_TSDB_USERNAME"),
            password=os.environ.get("OPENC3_TSDB_PASSWORD"),
            dbname="qdb",
            **extra_kwargs,
        )

    @classmethod
    def connection(cls):
        """Get or create a thread-safe shared psycopg connection.

        Returns a shared singleton connection — callers should not close it.
        """
        with cls._shared_conn_mutex:
            if cls._shared_conn is None:
                cls._shared_conn = cls._create_query_connection()
            return cls._shared_conn

    @classmethod
    def disconnect(cls):
        """Reset the shared connection (close if open, set to None). Used after errors."""
        with cls._shared_conn_mutex:
            if cls._shared_conn is not None:
                with contextlib.suppress(Exception):
                    cls._shared_conn.close()
                cls._shared_conn = None

    @classmethod
    def check_connection(cls):
        """Health check — attempt to connect and immediately close.

        Returns True if successful, raises on failure.
        """
        conn = cls._create_query_connection(autocommit=True, connect_timeout=2)
        conn.close()
        return True

    # QuestDB name restrictions - characters that need to be replaced
    # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
    TABLE_NAME_INVALID_CHARS = r'[?,\'"\\/:)(+*%~]'
    # ILP protocol special characters that must be sanitized in column names
    COLUMN_NAME_INVALID_CHARS = r'[?\.,\'"\\/:)(+=\-*%~;!@#$^&]'

    @staticmethod
    def decode_value(value, data_type=None, array_size=None):
        """
        Decode a value retrieved from QuestDB back to its original Python type.

        QuestDB stores certain COSMOS types specially:
        - Arrays are JSON-encoded: "[1, 2, 3]" or '["a", "b"]'
        - Objects/Dicts are JSON-encoded: '{"key": "value"}'
        - Binary data (BLOCK) is base64-encoded
        - Large integers (≥64-bit) are stored as VARCHAR strings

        Args:
            value: The value to decode
            data_type: COSMOS data type (INT, UINT, FLOAT, STRING, BLOCK, DERIVED, etc.)
            array_size: If not None, indicates this is an array item

        Returns:
            The decoded value
        """
        # Handle Decimal values from legacy QuestDB DECIMAL columns
        # (pre-existing tables may still use DECIMAL; new tables use VARCHAR)
        if isinstance(value, Decimal):
            if data_type in ("INT", "UINT"):
                return int(value)
            return value

        # Decode float sentinel values back to inf/nan
        if isinstance(value, float):
            return decode_float_special_values(value)

        # Non-strings don't need decoding (already handled by psycopg type mapping)
        if not isinstance(value, str):
            return value

        # Handle based on data type if provided
        if data_type == "BLOCK":
            # Empty string should be empty bytes for BLOCK type
            if not value:
                return b""
            try:
                return base64.b64decode(value)
            except Exception:
                return value

        # Empty strings stay as empty strings (for non-BLOCK types)
        if not value:
            return value

        # Arrays are JSON-encoded
        if array_size is not None:
            try:
                return json.loads(value)
            except json.JSONDecodeError:
                return value

        # Integer values stored as VARCHAR strings (≥64-bit integers)
        if data_type in ("INT", "UINT"):
            try:
                return int(value)
            except (ValueError, OverflowError):
                return value

        # DERIVED items are JSON-encoded (could be any type)
        if data_type == "DERIVED":
            try:
                return json.loads(value)
            except json.JSONDecodeError:
                # Could be a plain string from DERIVED
                return value

        # No data_type provided - fall back to heuristic decoding
        if data_type is None:
            first_char = value[0]
            # Try JSON for arrays/objects
            if first_char == "[" or first_char == "{":
                try:
                    return json.loads(value)
                except json.JSONDecodeError:
                    pass
            # Try integer conversion for numeric strings
            elif (first_char == "-" or first_char.isdigit()) and value.lstrip("-").isdigit():
                try:
                    return int(value)
                except (ValueError, OverflowError):
                    pass

        # Return as-is (STRING type or unknown)
        return value

    DEFAULT_BATCH_SIZE = 500

    def __init__(self, logger=None, name=None, batch_size=None):
        """
        Initialize QuestDB client.

        Args:
            logger: Optional logger instance. If not provided, uses print.
            name: Optional name for error messages (e.g., microservice name)
            batch_size: Number of rows to buffer before auto-flushing (default: DEFAULT_BATCH_SIZE)
        """
        self.batch_size = batch_size or self.DEFAULT_BATCH_SIZE
        self.logger = logger
        self.name = name or "QuestDBClient"
        self.ingest = None
        self.query = None
        # Track columns that need JSON serialization due to type conflicts or DERIVED type
        # Key is "table__column", value is True
        self.json_columns = {}
        # Track columns that are VARCHAR type (for ≥64-bit integers, state __C columns, etc.)
        # Non-string values must be converted to strings before ILP ingestion.
        # Key is "table__column", value is True
        self.varchar_columns = {}
        # Track FLOAT column bit sizes for proper inf/nan sentinel encoding
        # Key is "table__column", value is bit_size (32 or 64)
        self.float_bit_sizes = {}
        # Track pending rows for error recovery (cleared on successful flush)
        # Each entry is (table_name, columns_dict, timestamp_ns)
        self.pending_rows = []

    def _log_info(self, msg):
        print(f"INFO: {msg}")

    def _log_warn(self, msg):
        if self.logger:
            self.logger.warn(msg)
        else:
            print(f"WARN: {msg}")

    def _log_error(self, msg):
        if self.logger:
            self.logger.error(msg)
        else:
            print(f"ERROR: {msg}")

    def _get_connection_env(self, port_env_var):
        """Read and validate QuestDB connection environment variables.

        Args:
            port_env_var: Name of the port environment variable

        Returns:
            Tuple of (host, port, username, password)

        Raises:
            RuntimeError: If any required environment variable is missing
        """
        host = os.environ.get("OPENC3_TSDB_HOSTNAME")
        port = os.environ.get(port_env_var)
        username = os.environ.get("OPENC3_TSDB_USERNAME")
        password = os.environ.get("OPENC3_TSDB_PASSWORD")

        if not host:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_HOSTNAME")
        if not port:
            raise RuntimeError(f"{self.name} missing env var {port_env_var}")
        if not username:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_USERNAME")
        if not password:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_PASSWORD")

        return host, int(port), username, password

    def connect_ingest(self):
        """
        Establish HTTP ILP connection for data ingestion.

        Raises:
            RuntimeError: If required environment variables are missing
            ConnectionError: If connection fails
        """
        host, port, username, password = self._get_connection_env("OPENC3_TSDB_INGEST_PORT")

        try:
            if self.ingest:
                self.ingest.close()
            self.ingest = Sender(Protocol.Http, host, port, username=username, password=password)
            self.ingest.establish()
        except Exception as e:
            raise ConnectionError(f"Failed to connect to QuestDB: {e}") from e

    def connect_query(self):
        """
        Establish PostgreSQL connection for queries and DDL.

        Raises:
            ConnectionError: If connection fails
        """
        try:
            if self.query:
                self.query.close()

            self.query = self._create_query_connection(autocommit=True)
        except Exception as e:
            raise ConnectionError(f"Failed to connect to QuestDB: {e}") from e

    def close(self):
        """Close all connections."""
        if self.ingest:
            with contextlib.suppress(Exception):
                self.ingest.close()
            self.ingest = None
        if self.query:
            with contextlib.suppress(Exception):
                self.query.close()
            self.query = None

    def _get_column_type_from_conversion(self, table_name, column_name, converted_type, converted_bit_size):
        """
        Determine the QuestDB column type based on a read_conversion's converted_type and converted_bit_size.

        Args:
            table_name: Table name for tracking column metadata
            column_name: Column name for tracking column metadata
            converted_type: The converted_type from read_conversion (FLOAT, INT, UINT, TIME, STRING, BLOCK, etc.)
            converted_bit_size: The converted_bit_size from read_conversion

        Returns:
            Tuple of (column_type_sql, needs_json) where:
                - column_type_sql is the QuestDB column type string (e.g., "float", "double", "varchar")
                - needs_json is True if the column should be JSON-serialized
        """
        if converted_type == "FLOAT":
            if converted_bit_size == 32:
                self.float_bit_sizes[f"{table_name}__{column_name}"] = 32
                return "float", False
            else:
                self.float_bit_sizes[f"{table_name}__{column_name}"] = 64
                return "double", False
        elif converted_type in ("INT", "UINT"):
            if converted_bit_size < 32:
                return "int", False
            elif converted_bit_size < 64:
                return "long", False
            else:
                # ≥64-bit integers stored as VARCHAR to avoid LONG NULL sentinel
                # (0x8000000000000000) and DECIMAL limitations
                self.varchar_columns[f"{table_name}__{column_name}"] = True
                return "varchar", False
        elif converted_type == "TIME" or converted_type == "STRING":
            return "varchar", False
        elif converted_type == "BLOCK":
            # BLOCK type is base64 encoded, not JSON
            return "varchar", False
        else:
            # Unknown converted_type - fall back to JSON serialization
            return "varchar", True

    @staticmethod
    def find_item_def(packet_def, item_name):
        """Find an item definition within a packet definition by name.

        Args:
            packet_def: Packet definition dict from TargetModel.packet, or None
            item_name: Item name to find

        Returns:
            Item definition dict, or None if not found
        """
        if not packet_def:
            return None
        for item in packet_def.get("items", []):
            if item.get("name") == item_name:
                return item
        return None

    @staticmethod
    def resolve_item_type(item_def, value_type):
        """Resolve the data_type and array_size for a QuestDB column based on
        the item definition and requested value type.

        Args:
            item_def: Item definition dict from packet definition, or None
            value_type: One of 'RAW', 'CONVERTED', 'FORMATTED', 'WITH_UNITS'

        Returns:
            dict with 'data_type' and 'array_size' keys
        """
        if value_type in ("FORMATTED", "WITH_UNITS"):
            return {"data_type": "STRING", "array_size": None}
        elif value_type == "CONVERTED":
            if item_def:
                rc = item_def.get("read_conversion")
                if rc and rc.get("converted_type"):
                    return {
                        "data_type": rc.get("converted_type"),
                        "array_size": item_def.get("array_size"),
                    }
                elif item_def.get("states"):
                    return {"data_type": "STRING", "array_size": None}
                else:
                    return {
                        "data_type": item_def.get("data_type"),
                        "array_size": item_def.get("array_size"),
                    }
            else:
                return {"data_type": None, "array_size": None}
        else:  # RAW or default
            if item_def:
                return {
                    "data_type": item_def.get("data_type"),
                    "array_size": item_def.get("array_size"),
                }
            else:
                return {"data_type": None, "array_size": None}

    @classmethod
    def query_with_retry(cls, query, params=None, max_retries=5, label=None):
        """Execute a SQL query with automatic retry on connection errors.

        Args:
            query: SQL query string
            params: Query parameters (list/tuple), or None
            max_retries: Maximum number of retry attempts (default 5)
            label: Optional label for log messages

        Returns:
            List of result rows (dicts)

        Raises:
            RuntimeError: After exhausting retries
        """
        from openc3.utilities.logger import Logger

        retry_count = 0
        label_str = f" ({label})" if label else ""
        while True:
            try:
                conn = cls.connection()
                with conn.cursor(binary=True, row_factory=dict_row) as cursor:
                    cursor.execute(query, params or None)
                    return cursor.fetchall()
            except (psycopg.Error, OSError) as e:
                retry_count += 1
                if retry_count >= max_retries:
                    raise RuntimeError(f"Error querying TSDB{label_str}: {e!s}") from e
                Logger.warn(f"TSDB{label_str}: Retrying due to error: {e!s}")
                Logger.warn(f"TSDB{label_str}: Last query: {query}")
                cls.disconnect()
                time.sleep(0.1)

    @staticmethod
    def nsec_to_utc_time(nsec):
        """Convert a nanosecond integer timestamp to a UTC datetime.

        Args:
            nsec: Nanoseconds since epoch

        Returns:
            UTC-aware datetime or None
        """
        if nsec is None:
            return None
        seconds = nsec / 1_000_000_000
        remainder_ns = nsec % 1_000_000_000
        microseconds = remainder_ns / 1000
        return datetime.fromtimestamp(seconds, tz=timezone.utc).replace(microsecond=int(microseconds))

    @staticmethod
    def coerce_to_utc(value):
        """Coerce a value from QuestDB into a UTC datetime.

        Handles datetime, float (unix seconds), int (nanoseconds), and string timestamps.

        Args:
            value: Timestamp value in any supported format

        Returns:
            UTC-aware datetime or None
        """
        if value is None:
            return None
        if isinstance(value, datetime):
            if value.tzinfo is None:
                return value.replace(tzinfo=timezone.utc)
            return value.astimezone(timezone.utc)
        elif isinstance(value, float):
            return datetime.fromtimestamp(value, tz=timezone.utc)
        elif isinstance(value, int):
            return QuestDBClient.nsec_to_utc_time(value)
        elif isinstance(value, str):
            from datetime import datetime as dt

            parsed = dt.fromisoformat(value.replace("Z", "+00:00"))
            return parsed.astimezone(timezone.utc)
        else:
            # Assume PG timestamp-like object
            return QuestDBClient.pg_timestamp_to_utc(value)

    @staticmethod
    def column_suffix_for_value_type(value_type):
        """Return the QuestDB column suffix for a given value type.

        Args:
            value_type: One of 'RAW', 'CONVERTED', 'FORMATTED', 'WITH_UNITS'

        Returns:
            Column suffix ('__C', '__F', or '')
        """
        return {"FORMATTED": "__F", "WITH_UNITS": "__F", "CONVERTED": "__C"}.get(value_type, "")

    @staticmethod
    def value_type_for_column_suffix(column_name):
        """Determine the value type from a QuestDB column name's suffix.

        Args:
            column_name: Column name possibly ending in __C, __F, __L

        Returns:
            One of 'FORMATTED', 'CONVERTED', 'RAW'
        """
        if column_name.endswith("__F"):
            return "FORMATTED"
        elif column_name.endswith("__C"):
            return "CONVERTED"
        else:
            return "RAW"

    @staticmethod
    def fetch_packet_def(target_name, packet_name, type="TLM", scope="DEFAULT"):
        """Fetch a packet definition from TargetModel, returning None if not found.

        Args:
            target_name: Target name
            packet_name: Packet name
            type: 'CMD' or 'TLM' (default 'TLM')
            scope: Scope name

        Returns:
            Packet definition dict or None
        """
        from openc3.models.target_model import TargetModel

        try:
            return TargetModel.packet(target_name, packet_name, type=type, scope=scope)
        except RuntimeError:
            return None

    @classmethod
    def build_item_defs_map(cls, packet_def):
        """Build a dict mapping sanitized column names to item definitions.

        Args:
            packet_def: Packet definition dict from TargetModel.packet, or None

        Returns:
            dict of {sanitized_column_name: item_def_dict}
        """
        result = {}
        if not packet_def:
            return result
        for item in packet_def.get("items", []):
            result[cls.sanitize_column_name(item["name"])] = item
        return result

    @staticmethod
    def build_aggregation_selects(safe_item_name, value_type, item_name=None):
        """Build aggregation SELECT columns (min/max/avg/stddev) for a single item.

        Args:
            safe_item_name: Sanitized column name
            value_type: 'RAW' or 'CONVERTED'
            item_name: Original (unsanitized) item name for mapping values.
                Defaults to safe_item_name if not provided.

        Returns:
            Tuple of (select_fragments_list, column_mapping_dict)
            column_mapping maps result column alias to [item_name, reduced_type, value_type]
        """
        if item_name is None:
            item_name = safe_item_name
        selects = []
        mapping = {}
        if value_type == "RAW":
            col = safe_item_name
            for suffix, reduced_type in [("N", "MIN"), ("X", "MAX"), ("A", "AVG"), ("S", "STDDEV")]:
                alias_name = f"{safe_item_name}__{suffix}"
                selects.append(f'{reduced_type.lower()}("{col}") as "{alias_name}"')
                mapping[alias_name] = [item_name, reduced_type, "RAW"]
        elif value_type == "CONVERTED":
            col = f"{safe_item_name}__C"
            for suffix, reduced_type in [("CN", "MIN"), ("CX", "MAX"), ("CA", "AVG"), ("CS", "STDDEV")]:
                alias_name = f"{safe_item_name}__{suffix}"
                selects.append(f'{reduced_type.lower()}("{col}") as "{alias_name}"')
                mapping[alias_name] = [item_name, reduced_type, "CONVERTED"]
        return selects, mapping

    @classmethod
    def add_timestamp_entries(cls, entry, timestamp_ns, prefix):
        """Add TIMESECONDS and TIMEFORMATTED entries to a dict from a nanosecond timestamp.

        Args:
            entry: Entry dict to populate
            timestamp_ns: Nanoseconds since epoch
            prefix: 'PACKET' or 'RECEIVED'
        """
        if timestamp_ns is None:
            return
        utc_time = cls.nsec_to_utc_time(timestamp_ns)
        entry[f"{prefix}_TIMESECONDS"] = cls.format_timestamp(utc_time, "seconds")
        entry[f"{prefix}_TIMEFORMATTED"] = cls.format_timestamp(utc_time, "formatted")

    @classmethod
    def tsdb_lookup(cls, items, start_time, end_time=None, scope="DEFAULT"):
        """Query historical telemetry data from QuestDB for a list of items.
        Builds the SQL query, executes it, and decodes all results.

        Args:
            items: List of [target_name, packet_name, item_name, value_type, limits].
                item_name may be None to indicate a placeholder (non-existent item).
            start_time: Start timestamp for the query
            end_time: End timestamp, or None for "latest single row"
            scope: Scope name

        Returns:
            Array of [value, limits_state] pairs per row, or {} if no results.
            Single-row results return a flat array; multi-row results return array of arrays.
        """
        tables = {}
        names = []
        nil_count = 0
        packet_cache = {}
        item_types = {}
        calculated_items = {}
        needed_timestamps = {}
        current_position = 0

        for item in items:
            target_name, packet_name, item_name, value_type, limits = item
            if item_name is None:
                names.append(f"PACKET_TIMESECONDS as __nil{nil_count}")
                nil_count += 1
                current_position += 1
                continue

            table_name, _ = cls.sanitize_table_name(target_name, packet_name, scope=scope)
            tables[table_name] = 1
            index = list(tables.keys()).index(table_name)

            if item_name in cls.STORED_TIMESTAMP_ITEMS:
                names.append(f'"T{index}.{item_name}"')
                current_position += 1
                continue

            if item_name in cls.TIMESTAMP_ITEMS:
                ts_info = cls.TIMESTAMP_ITEMS[item_name]
                calculated_items[current_position] = {
                    "source": ts_info["source"],
                    "format": ts_info["format"],
                    "table_index": index,
                }
                if index not in needed_timestamps:
                    needed_timestamps[index] = set()
                needed_timestamps[index].add(ts_info["source"])
                current_position += 1
                continue

            safe_item_name = cls.sanitize_column_name(item_name)

            cache_key = (target_name, packet_name)
            if cache_key not in packet_cache:
                packet_cache[cache_key] = cls.fetch_packet_def(target_name, packet_name, scope=scope)

            packet_def = packet_cache[cache_key]
            item_def = cls.find_item_def(packet_def, item_name)

            suffix = cls.column_suffix_for_value_type(value_type)
            col_name = f"T{index}.{safe_item_name}{suffix}"
            names.append(f'"{col_name}"')
            item_types[col_name] = cls.resolve_item_type(item_def, value_type)

            current_position += 1
            if limits:
                names.append(f'"T{index}.{safe_item_name}__L"')

        # Add needed timestamp columns to the SELECT for calculated items
        for table_index, ts_columns in needed_timestamps.items():
            for ts_col in ts_columns:
                names.append(f"T{table_index}.{ts_col} as T{table_index}___ts_{ts_col}")

        # Build the SQL query
        query = f"SELECT {', '.join(names)} FROM "
        for index, (table_name, _) in enumerate(tables.items()):
            if index == 0:
                query += f"{table_name} as T{index} "
            else:
                query += f"ASOF JOIN {table_name} as T{index} "

        query_params = []
        if start_time and not end_time:
            query += "WHERE T0.PACKET_TIMESECONDS < %s LIMIT -1"
            query_params.append(start_time)
        elif start_time and end_time:
            query += "WHERE T0.PACKET_TIMESECONDS >= %s AND T0.PACKET_TIMESECONDS < %s"
            query_params.append(start_time)
            query_params.append(end_time)

        result = cls.query_with_retry(query, params=query_params or None, label="tsdb_lookup")

        if not result:
            return {}

        data = []
        for row_index, row in enumerate(result):
            data.append([])
            col_index = 0
            row_timestamps = {}
            for col_name, col_value in row.items():
                if "__L" in col_name:
                    if col_index > 0:
                        data[row_index][col_index - 1] = [
                            data[row_index][col_index - 1][0],
                            col_value,
                        ]
                elif col_name.startswith("__nil"):
                    data[row_index].append([None, None])
                    col_index += 1
                elif re.match(r"^T(\d+)___ts_(.+)$", col_name):
                    match = re.match(r"^T(\d+)___ts_(.+)$", col_name)
                    table_idx = int(match.group(1))
                    ts_source = match.group(2)
                    row_timestamps[f"T{table_idx}.{ts_source}"] = col_value
                elif (
                    col_name.endswith(".PACKET_TIMESECONDS")
                    or col_name.endswith(".RECEIVED_TIMESECONDS")
                    or col_name in ("PACKET_TIMESECONDS", "RECEIVED_TIMESECONDS")
                ):
                    ts_utc = cls.coerce_to_utc(col_value)
                    seconds_value = cls.format_timestamp(ts_utc, "seconds")
                    data[row_index].append([seconds_value, None])
                    col_index += 1
                    if "." in col_name:
                        row_timestamps[col_name] = col_value
                    else:
                        row_timestamps[f"T0.{col_name}"] = col_value
                else:
                    type_info = item_types.get(col_name, {})
                    if not type_info:
                        for prefix in [f"T{i}." for i in range(len(tables))]:
                            prefixed_name = prefix + col_name
                            type_info = item_types.get(prefixed_name, {})
                            if type_info:
                                break
                    decoded_value = cls.decode_value(
                        col_value,
                        data_type=type_info.get("data_type"),
                        array_size=type_info.get("array_size"),
                    )
                    data[row_index].append([decoded_value, None])
                    col_index += 1

            for position in sorted(calculated_items.keys()):
                calc_info = calculated_items[position]
                ts_key = f"T{calc_info['table_index']}.{calc_info['source']}"
                ts_value = row_timestamps.get(ts_key)
                ts_utc = cls.coerce_to_utc(ts_value)
                calculated_value = cls.format_timestamp(ts_utc, calc_info["format"])
                data[row_index].insert(position, [calculated_value, None])

        if len(result) == 1:
            data = data[0]
        return data

    @classmethod
    def sanitize_table_name(cls, target_name, packet_name, cmd_or_tlm="TLM", scope="DEFAULT"):
        """
        Create a valid QuestDB table name from target and packet names.

        Args:
            target_name: Target name
            packet_name: Packet name
            cmd_or_tlm: "CMD" or "TLM" prefix (default "TLM")
            scope: Scope name (default "DEFAULT")

        Returns:
            Tuple of (sanitized_table_name, original_table_name)
        """
        orig_table_name = f"{scope}__{cmd_or_tlm}__{target_name}__{packet_name}"
        table_name = re.sub(cls.TABLE_NAME_INVALID_CHARS, "_", orig_table_name)
        return table_name, orig_table_name

    @classmethod
    def sanitize_column_name(cls, item_name):
        """
        Create a valid QuestDB column name from an item name.

        Args:
            item_name: Original item name

        Returns:
            Sanitized column name
        """
        return re.sub(cls.COLUMN_NAME_INVALID_CHARS, "_", item_name)

    @staticmethod
    def pg_timestamp_to_utc(pg_time):
        """
        Convert a psycopg timestamp to UTC.
        psycopg returns timestamps as naive datetime objects that need UTC treatment.
        QuestDB stores timestamps in UTC, but the psycopg driver may return naive datetimes.

        Args:
            pg_time: Timestamp from psycopg query result (datetime)

        Returns:
            UTC-aware datetime
        """
        if pg_time is None:
            return None
        # Replace timezone info with UTC (psycopg may return naive datetimes)
        return pg_time.replace(tzinfo=timezone.utc)

    @staticmethod
    def format_timestamp(utc_time, format_type):
        """
        Format a UTC timestamp according to the specified format.

        Args:
            utc_time: UTC datetime
            format_type: 'seconds' for Unix seconds (float), 'formatted' for ISO 8601

        Returns:
            Formatted timestamp (float or string) or None if utc_time is None
        """
        if utc_time is None:
            return None
        if format_type == "seconds":
            return utc_time.timestamp()
        elif format_type == "formatted":
            return utc_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        else:
            return None

    # Maps SQL type strings used in CREATE TABLE to canonical type names returned by SHOW COLUMNS
    @staticmethod
    def _canonical_type(sql_type):
        """Normalize a SQL type string for comparison.

        Uppercases and strips internal whitespace so that parameterized types
        like 'DECIMAL(20, 0)' and 'DECIMAL(20,0)' compare equal.
        """
        return re.sub(r"\s+", "", sql_type.upper())

    # psycopg errors that indicate the connection itself is broken (vs a SQL error).
    # These are the only DDL failures we retry — schema errors, missing tables, etc.
    # bubble up so the caller sees them.
    _CONNECTION_ERROR_TYPES = (psycopg.OperationalError, psycopg.InterfaceError)

    def _execute_ddl(self, sql, max_retries=3):
        """Execute a DDL statement, reconnecting and retrying on connection errors.

        Raises the last exception after retries are exhausted, or any non-connection
        psycopg error immediately.
        """
        for attempt in range(max_retries):
            try:
                with self.query.cursor() as cur:
                    cur.execute(sql)
                return
            except self._CONNECTION_ERROR_TYPES as error:
                if attempt == max_retries - 1:
                    raise
                self._log_warn(
                    f"QuestDB: DDL connection error on attempt {attempt + 1}/{max_retries}, "
                    f"reconnecting: {error}"
                )
                try:
                    self.connect_query()
                except Exception as reconnect_err:
                    self._log_warn(f"QuestDB: Reconnect failed: {reconnect_err}")
                time.sleep(0.1 * (attempt + 1))

    def _get_existing_columns(self, table_name, max_retries=3):
        """Query QuestDB for existing column names and types.

        Returns:
            Dict of column_name -> column_type, or None if the table does not exist.

        Raises:
            psycopg.OperationalError / psycopg.InterfaceError if the connection
            cannot be reestablished within max_retries.
        """
        for attempt in range(max_retries):
            try:
                with self.query.cursor() as cur:
                    cur.execute(f'SHOW COLUMNS FROM "{table_name}"')
                    columns = {}
                    for row in cur.fetchall():
                        columns[row[0]] = row[1]
                    return columns
            except self._CONNECTION_ERROR_TYPES as error:
                if attempt == max_retries - 1:
                    raise
                self._log_warn(
                    f"QuestDB: SHOW COLUMNS connection error on attempt {attempt + 1}/{max_retries}, "
                    f"reconnecting: {error}"
                )
                try:
                    self.connect_query()
                except Exception as reconnect_err:
                    self._log_warn(f"QuestDB: Reconnect failed: {reconnect_err}")
                time.sleep(0.1 * (attempt + 1))
            except (psycopg.Error, TypeError):
                # psycopg.Error: table doesn't exist in QuestDB
                # TypeError: can occur in unit tests with mock cursors
                return None

    def create_table(self, target_name, packet_name, packet, cmd_or_tlm="TLM", retain_time=None, scope="DEFAULT"):
        """
        Create a QuestDB table for a target/packet combination.

        Args:
            target_name: Target name
            packet_name: Packet name
            packet: Packet definition dict with 'items' list
            cmd_or_tlm: "CMD" or "TLM" prefix (default "TLM")
            retain_time: Optional Time To Live for the table (e.g., "30d", "1y")
            scope: Scope name (default "DEFAULT")

        Returns:
            The sanitized table name that was created
        """
        table_name, orig_table_name = self.sanitize_table_name(target_name, packet_name, cmd_or_tlm, scope=scope)

        if table_name != orig_table_name:
            self._log_warn(
                f"QuestDB: Target / packet {orig_table_name} changed to {table_name} due to invalid characters"
            )

        # Build desired column definitions: dict of column_name -> sql_type
        # Used both for CREATE TABLE (new tables) and ALTER TABLE (existing tables)
        desired_columns = {}

        items = packet.get("items", [])
        for item in items:
            name = item.get("name")
            if not name:
                continue
            item_name = self.sanitize_column_name(name)

            # Skip standard derived items as they're explicitly created
            if item_name in [
                "PACKET_TIMESECONDS",
                "RECEIVED_TIMESECONDS",
                "PACKET_TIMEFORMATTED",
                "RECEIVED_TIMEFORMATTED",
                "RECEIVED_COUNT",
            ]:
                continue

            data_type = item.get("data_type")

            # DERIVED items: check if conversion declares a specific type
            # If so, use that type instead of falling back to VARCHAR/JSON
            if data_type == "DERIVED":
                rc = item.get("read_conversion")
                converted_type = rc.get("converted_type") if rc else None
                converted_bit_size = rc.get("converted_bit_size", 0) if rc else 0
                converted_array_size = rc.get("converted_array_size") if rc else None

                # Types that require JSON serialization (complex or unknown types)
                if converted_type is None or converted_type in ["ARRAY", "OBJECT", "ANY"] or converted_array_size:
                    desired_columns[item_name] = "varchar"
                    self.json_columns[f"{table_name}__{item_name}"] = True
                else:
                    col_type, needs_json = self._get_column_type_from_conversion(
                        table_name, item_name, converted_type, converted_bit_size
                    )
                    desired_columns[item_name] = col_type
                    if needs_json:
                        self.json_columns[f"{table_name}__{item_name}"] = True
                continue

            if item.get("array_size") is not None:
                # Always json encode arrays to avoid QuestDB array type issues
                desired_columns[item_name] = "varchar"
                self.json_columns[f"{table_name}__{item_name}"] = True
            else:
                # Determine the QuestDB column type based on item data type
                # We need to make sure to choose nullable types and choose types that
                # can support the full range of the given type. This is tricky because
                # QuestDB uses the minimum possible value in a given type as NULL.
                # See https://questdb.com/docs/reference/sql/datatypes for more details.
                bit_size = item.get("bit_size", 0)
                col_type, needs_json = self._get_column_type_from_conversion(table_name, item_name, data_type, bit_size)
                desired_columns[item_name] = col_type
                if needs_json:
                    self.json_columns[f"{table_name}__{item_name}"] = True

                if item.get("states"):
                    desired_columns[f"{item_name}__C"] = "varchar"
                    self.varchar_columns[f"{table_name}__{item_name}__C"] = True
                elif item.get("read_conversion"):
                    rc = item.get("read_conversion")
                    converted_type = rc.get("converted_type") if rc else None
                    converted_bit_size = rc.get("converted_bit_size", 0) if rc else 0
                    col_type, needs_json = self._get_column_type_from_conversion(
                        table_name,
                        f"{item_name}__C",
                        converted_type,
                        converted_bit_size,
                    )
                    desired_columns[f"{item_name}__C"] = col_type
                    if needs_json:
                        self.json_columns[f"{table_name}__{item_name}__C"] = True

                if item.get("format_string") or item.get("units"):
                    desired_columns[f"{item_name}__F"] = "varchar"

        # Check if table already exists and reconcile column types
        existing_columns = self._get_existing_columns(table_name)

        if existing_columns is not None:
            # Table exists — check for type mismatches and missing columns.
            # Connection errors bubble out of _execute_ddl (fatal). Non-connection
            # errors on a single column are logged so other columns still reconcile.
            altered = False
            for col_name, desired_sql_type in desired_columns.items():
                desired_canonical = self._canonical_type(desired_sql_type)
                existing_raw = existing_columns.get(col_name)
                existing_type = self._canonical_type(existing_raw) if existing_raw else None

                try:
                    if existing_type is None:
                        # Column doesn't exist yet — add it
                        alter = f'ALTER TABLE "{table_name}" ADD COLUMN {col_name} {desired_sql_type}'
                        self._execute_ddl(alter)
                        self._log_info(f"QuestDB: Added column: {alter}")
                        altered = True
                    elif existing_type != desired_canonical:
                        # Skip DECIMAL -> VARCHAR: blocked by QuestDB bug #6923.
                        # String values sent via ILP are auto-cast to DECIMAL,
                        # so the column remains usable without the ALTER.
                        if "DECIMAL" in existing_type and desired_canonical == "VARCHAR":
                            self._log_warn(
                                f"QuestDB: Skipping ALTER {col_name} from {existing_type} to VARCHAR "
                                f"in table {table_name} — blocked by QuestDB bug #6923. "
                                f"Column will continue to function as DECIMAL."
                            )
                        else:
                            # Type mismatch — ALTER the column type
                            alter = f'ALTER TABLE "{table_name}" ALTER COLUMN {col_name} TYPE {desired_sql_type}'
                            self._execute_ddl(alter)
                            self._log_info(
                                f"QuestDB: Altered column type: {alter} (was {existing_type}, now {desired_canonical})"
                            )
                            altered = True
                except self._CONNECTION_ERROR_TYPES:
                    # Connection is fatally broken — let caller see it.
                    raise
                except psycopg.Error as error:
                    # Per-column schema error (bad type, constraint, etc.) — log and continue
                    # so other columns still reconcile.
                    self._log_error(f"QuestDB: Error reconciling column {col_name} in table {table_name}: {error}")

            if altered:
                # QuestDB applies ALTER asynchronously — wait for changes to propagate
                time.sleep(0.5)
                # Reconnect ILP sender to clear its cached schema
                self.connect_ingest()
        else:
            # Table doesn't exist — create it. _execute_ddl retries connection errors;
            # any non-connection failure propagates so the caller knows table creation failed.
            columns_sql = ",\n".join(f'"{col}" {col_type}' for col, col_type in desired_columns.items())

            # Create table with COSMOS_DATA_TAG as a symbol for use as filtering/indexing column,
            sql = f"""
                CREATE TABLE IF NOT EXISTS "{table_name}" (
                    PACKET_TIMESECONDS timestamp_ns,
                    RECEIVED_TIMESECONDS timestamp_ns,
                    RECEIVED_COUNT long,
                    COSMOS_DATA_TAG symbol """

            # COSMOS command packets have an extra field for command information: user, approver, etc
            # COSMOS telemetry packets may also have an extra field for additional information that doesn't fit in defined items
            sql += ",\nCOSMOS_EXTRA varchar"
            if columns_sql:
                sql += f",\n{columns_sql}"

            # Primary DEDUP will be on PACKET_TIMESECONDS
            # If for some reason you're duplicating PACKET_TIMESECONDS you can
            # explicitly include COSMOS_DATA_TAG as well.
            sql += """
                ) TIMESTAMP(PACKET_TIMESECONDS)
                    PARTITION BY DAY
            """

            # Add TTL clause if specified
            # QuestDB TTL format: TTL <value> <unit> where unit is HOUR, DAY, WEEK, MONTH, YEAR
            if retain_time:
                retain_time_sql = self._convert_retain_time_to_questdb_format(retain_time)
                if retain_time_sql:
                    sql += f"\n                TTL {retain_time_sql}"

            self._log_info(f"QuestDB: Creating table:\n{sql}")
            self._execute_ddl(sql)

        return table_name

    def _convert_retain_time_to_questdb_format(self, retain_time):
        """
        Convert TTL from compact format (e.g., "30d", "1y") to QuestDB format (e.g., "30 DAY", "1 YEAR").

        Args:
            retain_time: TTL string in format like "30d", "1w", "6M", "1y"

        Returns:
            QuestDB-compatible TTL string or None if invalid
        """
        if not retain_time:
            return None

        # Map of unit suffixes to QuestDB TTL units
        unit_map = {
            "h": "HOUR",
            "d": "DAY",
            "w": "WEEK",
            "M": "MONTH",
            "y": "YEAR",
        }

        # Extract the numeric value and unit
        match = re.match(r"^(\d+)([hdwMy])$", retain_time)
        if not match:
            self._log_warn(f"QuestDB: Invalid retain_time format '{retain_time}', expected format like '30d', '1y'")
            return None

        value = match.group(1)
        unit_suffix = match.group(2)
        questdb_unit = unit_map.get(unit_suffix)

        if not questdb_unit:
            self._log_warn(f"QuestDB: Unknown retain_time unit '{unit_suffix}'")
            return None

        return f"{value} {questdb_unit}"

    def convert_value(self, value, item_name, table_name=None):
        """
        Convert a value to a QuestDB-compatible format.

        Args:
            value: The value to convert
            item_name: Sanitized item name (for json_columns lookup)
            table_name: Table name (for json_columns lookup)

        Returns:
            Tuple of (converted_value, should_skip) where should_skip is True if value should be skipped
        """
        # Check if this column needs JSON serialization (DERIVED items or prior type conflicts)
        if table_name:
            json_key = f"{table_name}__{item_name}"
            force_json = json_key in self.json_columns
        else:
            force_json = False

        # For DERIVED columns, serialize everything as JSON string to avoid type conflicts
        if force_json:
            if isinstance(value, bytes):
                return base64.b64encode(value).decode("ascii"), False
            elif not isinstance(value, str):
                return json.dumps(value), False
            return value, False

        # Check if this column is VARCHAR (e.g. state __C columns where values
        # may be numeric when they don't match any defined state)
        if table_name:
            varchar_key = f"{table_name}__{item_name}"
            is_varchar = varchar_key in self.varchar_columns
        else:
            is_varchar = False

        if is_varchar and not isinstance(value, str):
            return str(value), False

        # Handle various data types for non-DERIVED columns
        match value:
            case int():
                # QuestDB Python client uses C long internally (signed 64-bit).
                # Values outside signed 64-bit range must be sent as strings.
                if value > 9223372036854775807 or value < -9223372036854775808:
                    value = str(value)

            case float():
                # Encode inf/nan as sentinel values (QuestDB stores these as NULL)
                if table_name:
                    float_key = f"{table_name}__{item_name}"
                    bit_size = self.float_bit_sizes.get(float_key, 64)
                else:
                    bit_size = 64
                value = encode_float_special_values(value, bit_size)

            case str() | None:
                pass

            case bytes():
                value = base64.b64encode(value).decode("ascii")

            case list():
                value = json.dumps(value)

            case dict():
                json_class = value.get("json_class")
                raw = value.get("raw")
                if json_class == "Float" and raw is not None:
                    value = float(raw)
                    # Must encode sentinel values here since match won't re-enter float() case
                    if table_name:
                        float_key = f"{table_name}__{item_name}"
                        bit_size = self.float_bit_sizes.get(float_key, 64)
                    else:
                        bit_size = 64
                    value = encode_float_special_values(value, bit_size)
                elif json_class == "String" and isinstance(raw, list):
                    value = base64.b64encode(bytes(raw)).decode("ascii")
                else:
                    value = json.dumps(value)
                if isinstance(value, list) and all(isinstance(b, int) and 0 <= b <= 255 for b in value):
                    value = base64.b64encode(bytes(value)).decode("ascii")

            case _:
                return None, True  # Skip unsupported types

        return value, False

    # Items that are derived from or stored in the PACKET_TIMESECONDS/RECEIVED_TIMESECONDS
    # timestamp columns and should not be stored as separate columns from json_data.
    # The timestamp values come from message metadata (time, received_time), not json_data.
    # PACKET_TIMESECONDS, RECEIVED_TIMESECONDS: stored as timestamp_ns columns (from message metadata)
    # PACKET_TIMEFORMATTED, RECEIVED_TIMEFORMATTED: calculated on read from timestamp columns
    SKIP_TIME_ITEMS = {
        "PACKET_TIMESECONDS",
        "PACKET_TIMEFORMATTED",
        "RECEIVED_TIMESECONDS",
        "RECEIVED_TIMEFORMATTED",
    }

    def process_json_data(self, json_data, table_name=None):
        """
        Process JSON data dict into QuestDB-compatible columns.

        Args:
            json_data: Dict of item_name -> value
            table_name: Optional table name for json_columns lookup

        Returns:
            Dict of sanitized_column_name -> converted_value
        """
        values = {}

        for orig_item_name, value in json_data.items():
            item_name = self.sanitize_column_name(orig_item_name)

            # Skip time-related items that are calculated from the PACKET_TIMESECONDS/RECEIVED_TIMESECONDS
            # timestamp columns. These values are derived on read and don't need separate storage.
            if item_name in self.SKIP_TIME_ITEMS:
                continue

            converted, skip = self.convert_value(value, item_name, table_name)
            if skip:
                self._log_warn(f"QuestDB: Unsupported value type for {orig_item_name}: {type(value)}")
                continue

            values[item_name] = converted

        return values

    def write_row(self, table_name, columns, timestamp_ns, rx_timestamp_ns=None):
        """
        Write a single row to QuestDB.

        Args:
            table_name: Target table name (already sanitized)
            columns: Dict of column_name -> value
            timestamp_ns: Packet timestamp in nanoseconds (stored as PACKET_TIMESECONDS)
            rx_timestamp_ns: Received timestamp in nanoseconds (stored as RECEIVED_TIMESECONDS, optional)

        Returns:
            True if a batch flush was performed, False otherwise
        """
        if rx_timestamp_ns is not None:
            # Convert nanoseconds to datetime for QuestDB timestamp column
            columns["RECEIVED_TIMESECONDS"] = datetime.fromtimestamp(rx_timestamp_ns / 1_000_000_000, tz=timezone.utc)
        self.pending_rows.append((table_name, columns.copy(), timestamp_ns))
        self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
        # Flush in batches to avoid overwhelming QuestDB's HTTP endpoint
        if len(self.pending_rows) >= self.batch_size:
            self.flush()
            return True
        return False

    def flush(self):
        """Flush pending writes to QuestDB."""
        if self.ingest:
            self.ingest.flush()
            self.pending_rows.clear()

    def _convert_column_to_json(self, table_name, column_name, columns):
        """Mark a column for JSON serialization and convert its current value."""
        self.json_columns[f"{table_name}__{column_name}"] = True
        if column_name in columns:
            value = columns[column_name]
            if isinstance(value, numpy.ndarray):
                columns[column_name] = json.dumps(value.tolist())
            else:
                columns[column_name] = json.dumps(value)

    def _reconnect_and_retry_pending(self):
        """Reconnect the ILP sender and replay all pending rows."""
        self.connect_ingest()
        for table_name, columns, timestamp_ns in self.pending_rows:
            self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))

    # Map QuestDB column types to Python casting functions for value conversion.
    # Used by handle_ingress_error to cast mismatched values to fit the column type.
    COLUMN_TYPE_CASTERS = {
        "LONG": int,
        "INT": int,
        "SHORT": int,
        "BYTE": int,
        "FLOAT": float,
        "DOUBLE": float,
        "VARCHAR": str,
        "STRING": str,
        "SYMBOL": str,
        # Legacy DECIMAL columns accept string values via ILP auto-cast
        "DECIMAL": str,
    }

    def _cast_value_to_column_type(self, value, column_type):
        """Attempt to cast a value to match the expected column type.

        Args:
            value: The value to cast
            column_type: QuestDB column type name (e.g., "LONG", "DOUBLE", "VARCHAR")

        Returns:
            The casted value, or None if casting fails.
        """
        caster = self.COLUMN_TYPE_CASTERS.get(column_type)
        if caster is None:
            return None
        try:
            return caster(value)
        except (ValueError, TypeError, OverflowError):
            return None

    def handle_ingress_error(self, error):
        """
        Handle an IngressError by casting the value to fit the column type.

        Since create_table proactively reconciles column types on startup,
        IngressErrors indicate the data doesn't match the user's definitions.
        We cast the value to fit the column type rather than altering the schema.

        Uses self.pending_rows (populated by write_row) to find and fix the
        affected row data, then replays all pending rows.

        Args:
            error: The IngressError

        Returns:
            True if error was handled and retry succeeded, False otherwise
        """
        self._log_warn(f"QuestDB: IngressError: {error}\n")

        error_message = str(error)
        is_cast_error = "cast error from protocol type" in error_message
        is_value_error = "cannot be converted to column type" in error_message

        if not is_cast_error and not is_value_error:
            self._log_error(f"QuestDB: Error writing to QuestDB: {error}\n")
            self.pending_rows.clear()
            try:
                time.sleep(0.1)
                self.connect_ingest()
                self._log_info("QuestDB: Reconnected after connection error")
            except Exception as reconnect_err:
                self._log_error(f"QuestDB: Failed to reconnect: {reconnect_err}")
            return False

        try:
            table_match = re.search(r"table:\s+(.+?),", error_message)
            column_match = re.search(r"column:\s+(.+?);", error_message)
            to_type_match = re.search(r"column type:\s+([A-Z]+)", error_message)

            # "cast error from protocol type" includes the protocol type;
            # "cannot be converted to column type" does not
            type_match = re.search(r"protocol type:\s+([A-Z]+(?:\[\])?)\s", error_message)
            protocol_type = type_match.group(1) if type_match else None

            if not (table_match and column_match):
                self._log_error("QuestDB: Could not parse table or column from error message")
                return False

            err_table_name = table_match.group(1)
            column_name = column_match.group(1)
            column_type = to_type_match.group(1) if to_type_match else ""

            is_array_protocol = protocol_type is not None and (
                protocol_type.endswith("[]") or protocol_type.upper() == "ARRAY"
            )

            # Apply the fix to all pending rows for the affected table
            fixed = False
            for _row_table, columns, _row_ts in self.pending_rows:
                if _row_table != err_table_name:
                    continue

                # Handle array type mismatches — convert to JSON string
                if is_array_protocol:
                    self._convert_column_to_json(err_table_name, column_name, columns)
                    fixed = True
                    continue

                # For scalar type mismatches, cast the value to fit the column type
                if column_name not in columns:
                    continue

                value = columns[column_name]
                casted = self._cast_value_to_column_type(value, column_type)
                if casted is not None:
                    columns[column_name] = casted
                    fixed = True
                else:
                    # Can't cast — remove from row (will be NULL in QuestDB)
                    del columns[column_name]
                    fixed = True

            if not fixed:
                self._log_error(
                    f"QuestDB: Could not find column {column_name} in pending rows for table {err_table_name}"
                )
                return False

            # Log and persist tracking for future rows
            if is_array_protocol:
                self._log_warn(
                    f"QuestDB: Column {column_name} in table {err_table_name} "
                    f"received array data but column type is {column_type}. "
                    f"Serializing as JSON string."
                )
            else:
                if column_type in ("VARCHAR", "STRING", "DECIMAL"):
                    self.varchar_columns[f"{err_table_name}__{column_name}"] = True
                self._log_warn(
                    f"QuestDB: Column {column_name} in table {err_table_name} "
                    f"expected {column_type} but received {protocol_type}. "
                    f"Value cast applied."
                )

            self._reconnect_and_retry_pending()
            return True

        except Exception as exc:
            self._log_error(f"QuestDB: Error handling ingress error: {exc}")
            return False
