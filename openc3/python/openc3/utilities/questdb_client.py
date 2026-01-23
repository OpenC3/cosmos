# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

"""
Shared QuestDB client for connection management, table creation, and data ingestion.
Used by both TsdbMicroservice (real-time) and MigrationMicroservice (historical data).
"""

import os
import re
import json
import base64
import psycopg
import numpy
from questdb.ingress import Sender, IngressError, Protocol, TimestampNanos


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

    # QuestDB name restrictions - characters that need to be replaced
    # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
    TABLE_NAME_INVALID_CHARS = r'[?,\'"\\/:)(+*%~]'
    COLUMN_NAME_INVALID_CHARS = r'[?\.,\'"\\/:)(+\-*%~;]'

    def __init__(self, logger=None, name=None):
        """
        Initialize QuestDB client.

        Args:
            logger: Optional logger instance. If not provided, uses print.
            name: Optional name for error messages (e.g., microservice name)
        """
        self.logger = logger
        self.name = name or "QuestDBClient"
        self.ingest = None
        self.query = None
        # Track columns that need JSON serialization due to type conflicts or DERIVED type
        # Key is "table__column", value is True
        self.json_columns = {}

    def _log_info(self, msg):
        if self.logger:
            self.logger.info(msg)
        else:
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

    def connect_ingest(self):
        """
        Establish HTTP ILP connection for data ingestion.

        Uses environment variables:
        - OPENC3_TSDB_HOSTNAME: QuestDB host
        - OPENC3_TSDB_INGEST_PORT: HTTP ILP port (default 9000)
        - OPENC3_TSDB_USERNAME: Authentication username
        - OPENC3_TSDB_PASSWORD: Authentication password

        Raises:
            RuntimeError: If required environment variables are missing
            ConnectionError: If connection fails
        """
        host = os.environ.get("OPENC3_TSDB_HOSTNAME")
        ingest_port = os.environ.get("OPENC3_TSDB_INGEST_PORT")
        username = os.environ.get("OPENC3_TSDB_USERNAME")
        password = os.environ.get("OPENC3_TSDB_PASSWORD")

        if not host:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_HOSTNAME")
        if ingest_port:
            ingest_port = int(ingest_port)
        else:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_INGEST_PORT")
        if not username:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_USERNAME")
        if not password:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_PASSWORD")

        try:
            if self.ingest:
                self.ingest.close()
            self.ingest = Sender(Protocol.Http, host, ingest_port, username=username, password=password)
            self.ingest.establish()
        except Exception as e:
            raise ConnectionError(f"Failed to connect to QuestDB: {e}")

    def connect_query(self):
        """
        Establish PostgreSQL connection for queries and DDL.

        Uses environment variables:
        - OPENC3_TSDB_HOSTNAME: QuestDB host
        - OPENC3_TSDB_QUERY_PORT: PostgreSQL port (default 8812)
        - OPENC3_TSDB_USERNAME: Authentication username
        - OPENC3_TSDB_PASSWORD: Authentication password

        Raises:
            RuntimeError: If required environment variables are missing
            ConnectionError: If connection fails
        """
        host = os.environ.get("OPENC3_TSDB_HOSTNAME")
        query_port = os.environ.get("OPENC3_TSDB_QUERY_PORT")
        username = os.environ.get("OPENC3_TSDB_USERNAME")
        password = os.environ.get("OPENC3_TSDB_PASSWORD")

        if not host:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_HOSTNAME")
        if query_port:
            query_port = int(query_port)
        else:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_QUERY_PORT")
        if not username:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_USERNAME")
        if not password:
            raise RuntimeError(f"{self.name} missing env var OPENC3_TSDB_PASSWORD")

        try:
            if self.query:
                self.query.close()

            self.query = psycopg.connect(
                host=host,
                port=query_port,
                user=username,
                password=password,
                dbname="qdb",
                autocommit=True,  # Important for QuestDB
            )
        except Exception as e:
            raise ConnectionError(f"Failed to connect to QuestDB: {e}")

    def close(self):
        """Close all connections."""
        if self.ingest:
            try:
                self.ingest.close()
            except Exception:
                pass
            self.ingest = None
        if self.query:
            try:
                self.query.close()
            except Exception:
                pass
            self.query = None

    @classmethod
    def sanitize_table_name(cls, target_name, packet_name):
        """
        Create a valid QuestDB table name from target and packet names.

        Args:
            target_name: Target name
            packet_name: Packet name

        Returns:
            Tuple of (sanitized_table_name, original_table_name)
        """
        orig_table_name = f"{target_name}__{packet_name}"
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

    def create_table(self, target_name, packet_name, packet):
        """
        Create a QuestDB table for a target/packet combination.

        Args:
            target_name: Target name
            packet_name: Packet name
            packet: Packet definition dict with 'items' list

        Returns:
            The sanitized table name that was created
        """
        table_name, orig_table_name = self.sanitize_table_name(target_name, packet_name)

        if table_name != orig_table_name:
            self._log_warn(
                f"QuestDB: Target / packet {orig_table_name} changed to {table_name} due to invalid characters"
            )

        # Build column definitions for all packet items
        column_definitions = []

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

            # DERIVED items have unpredictable types (could be int, float, array, etc.)
            # Create them as VARCHAR and serialize as JSON to avoid type conflicts
            if data_type == "DERIVED":
                column_definitions.append(f'"{item_name}" varchar')
                # Register for JSON serialization
                self.json_columns[f"{table_name}__{item_name}"] = True
                continue

            if item.get("array_size") is not None:
                # Always json encode arrays to avoid QuestDB array type issues
                column_definitions.append(f'"{item_name}" varchar')
                self.json_columns[f"{table_name}__{item_name}"] = True
            else:
                # Determine the QuestDB column type based on item data type
                # Default to VARCHAR for flexibility
                column_type = "VARCHAR"

                # We need to make sure to choose nullable types and choose types that
                # can support the full range of the given type. This is tricky because
                # QuestDB uses the minimum possible value in a given type as NULL.
                # See https://questdb.com/docs/reference/sql/datatypes for more details.
                bit_size = item.get("bit_size", 0)
                if data_type in ["INT", "UINT"]:
                    if bit_size < 32:
                        column_type = "int"
                    elif bit_size < 64:
                        column_type = "long"
                    else:
                        column_type = "varchar"
                elif data_type == "FLOAT":
                    if bit_size == 32:
                        column_type = "float"
                    else:
                        column_type = "double"
                elif data_type in ["STRING", "BLOCK"]:
                    column_type = "varchar"

                column_definitions.append(f'"{item_name}" {column_type}')

                if item.get("states"):
                    column_definitions.append(f'"{item_name}__C" varchar')
                elif item.get("read_conversion"):
                    rc = item.get("read_conversion")
                    converted_type = rc.get("converted_type") if rc else None
                    converted_bit_size = rc.get("converted_bit_size", 0) if rc else 0
                    if converted_type == "FLOAT":
                        if converted_bit_size == 32:
                            column_definitions.append(f'"{item_name}__C" float')
                        else:
                            column_definitions.append(f'"{item_name}__C" double')
                    elif converted_type in ["INT", "UINT"]:
                        if converted_bit_size < 32:
                            column_definitions.append(f'"{item_name}__C" int')
                        elif converted_bit_size <= 64:
                            column_definitions.append(f'"{item_name}__C" long')
                        else:
                            column_definitions.append(f'"{item_name}__C" varchar')
                    else:
                        column_definitions.append(f'"{item_name}__C" varchar')

                if item.get("format_string") or item.get("units"):
                    column_definitions.append(f'"{item_name}__F" varchar')

        columns_sql = ",\n".join(column_definitions)

        try:
            with self.query.cursor() as cur:
                sql = f"""
                    CREATE TABLE IF NOT EXISTS "{table_name}" (
                        timestamp timestamp_ns,
                        rx_timestamp timestamp_ns,
                        tag SYMBOL,
                        RECEIVED_COUNT LONG"""

                if columns_sql:
                    sql += f",\n{columns_sql}"

                sql += """
                    ) TIMESTAMP(timestamp)
                        PARTITION BY DAY
                        DEDUP UPSERT KEYS (timestamp, tag)
                """

                self._log_info(f"QuestDB: Creating table:\n{sql}")
                cur.execute(sql)
        except psycopg.Error as error:
            self._log_error(f"QuestDB: Error creating table {table_name}: {error}")

        return table_name

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

        # Handle various data types for non-DERIVED columns
        match value:
            case int() | float() | str() | None:
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
                elif json_class == "String" and isinstance(raw, list):
                    value = base64.b64encode(bytes(raw)).decode("ascii")
                else:
                    value = json.dumps(value)
                if isinstance(value, list) and all(isinstance(b, int) and 0 <= b <= 255 for b in value):
                    value = base64.b64encode(bytes(value)).decode("ascii")

            case _:
                return None, True  # Skip unsupported types

        return value, False

    # Items that are stored in QuestDB's timestamp/rx_timestamp columns rather than as separate columns
    # These can all be derived from the timestamp and rx_timestamp fields on read
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

            # Skip time-related items - they're stored in timestamp/rx_timestamp columns
            # (received directly from the topic message, not from json_data).
            # These values can be calculated on read. This saves significant storage space.
            # Note: 'TIMESTAMP' is also a reserved item name in Packet.RESERVED_ITEM_NAMES
            # to prevent collisions with the QuestDB table timestamp column.
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
            timestamp_ns: Packet timestamp in nanoseconds
            rx_timestamp_ns: Received timestamp in nanoseconds (optional)
        """
        if rx_timestamp_ns is not None:
            columns["rx_timestamp"] = TimestampNanos(rx_timestamp_ns)
        self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))

    def write_row_with_schema_protection(self, table_name, columns, timestamp_ns, rx_timestamp_ns=None):
        """
        Write a single row with schema protection (for migration).

        Tries to write the row, and if it fails due to schema mismatch,
        adapts the data rather than altering the schema.

        Args:
            table_name: Target table name (already sanitized)
            columns: Dict of column_name -> value
            timestamp_ns: Packet timestamp in nanoseconds
            rx_timestamp_ns: Received timestamp in nanoseconds (optional)

        Returns:
            Tuple of (success: bool, migrated_columns: list)
        """
        try:
            if rx_timestamp_ns is not None:
                columns["rx_timestamp"] = TimestampNanos(rx_timestamp_ns)
            self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
            return True, []
        except IngressError as error:
            return self.handle_ingress_error_with_protection(error, table_name, columns, timestamp_ns)

    def flush(self):
        """Flush pending writes to QuestDB."""
        if self.ingest:
            self.ingest.flush()

    def handle_ingress_error(self, error, table_name, columns, timestamp_ns):
        """
        Handle an IngressError, potentially fixing schema issues.

        For real-time ingestion, this will ALTER the table schema.
        For migration, use handle_ingress_error_with_protection instead.

        Args:
            error: The IngressError
            table_name: Table name
            columns: Column values dict
            timestamp_ns: Timestamp in nanoseconds

        Returns:
            True if error was handled and retry succeeded, False otherwise
        """
        self._log_warn(f"QuestDB: IngressError: {error}\n")

        if "cast error from protocol type" not in str(error):
            self._log_error(f"QuestDB: Error writing to QuestDB: {error}\n")
            return False

        try:
            with self.query.cursor() as cur:
                error_message = str(error)
                table_match = re.search(r"table:\s+(.+?),", error_message)
                column_match = re.search(r"column:\s+(.+?);", error_message)
                type_match = re.search(r"protocol type:\s+([A-Z]+(?:\[\])?)\s", error_message)
                to_type_match = re.search(r"column type:\s+([A-Z]+)", error_message)

                if not (table_match and column_match and type_match):
                    self._log_error("QuestDB: Could not parse table, column, or type from error message")
                    return False

                err_table_name = table_match.group(1)
                column_name = column_match.group(1)
                protocol_type = type_match.group(1)
                column_type = to_type_match.group(1) if to_type_match else ""

                # Check if this is an array-to-scalar/varchar conversion (not fixable via ALTER)
                is_array_protocol = protocol_type.endswith("[]") or protocol_type.upper() == "ARRAY"
                is_array_column = column_type.endswith("[]") or column_type.upper() == "ARRAY"
                if is_array_protocol and not is_array_column:
                    json_key = f"{err_table_name}__{column_name}"
                    self.json_columns[json_key] = True
                    self._log_warn(
                        f"QuestDB: Column {column_name} in table {err_table_name} was created as scalar "
                        f"but received array. Serializing as JSON and retrying."
                    )
                    # Convert the array value to JSON and retry
                    if column_name in columns:
                        value = columns[column_name]
                        if isinstance(value, numpy.ndarray):
                            columns[column_name] = json.dumps(value.tolist())
                        else:
                            columns[column_name] = json.dumps(value)
                        self.connect_ingest()  # reconnect
                        self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
                        return True
                    return False

                # Try to change the column type to fix the error
                # Note: QuestDB only supports DOUBLE[] arrays, convert other array types
                if protocol_type.endswith("[]") or protocol_type.upper() == "ARRAY":
                    new_type = "DOUBLE[]"
                else:
                    new_type = protocol_type.lower()
                alter = f"""ALTER TABLE "{err_table_name}" ALTER COLUMN {column_name} TYPE {new_type}"""
                cur.execute(alter)
                self._log_info(f"QuestDB: {alter}")
                self.connect_ingest()  # reconnect
                # Retry write
                self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
                return True

        except psycopg.Error as psy_error:
            self._log_error(f"QuestDB: Error executing ALTER\n{psy_error}")
            return False

    def handle_ingress_error_with_protection(self, error, table_name, columns, timestamp_ns):
        """
        Handle an IngressError with schema protection (for migration).

        This method protects the existing schema by:
        1. On cast error, trying to adapt the value
        2. If adaptation fails, writing to a new __MIGRATED column

        Args:
            error: The IngressError
            table_name: Table name
            columns: Column values dict (will be modified)
            timestamp_ns: Timestamp in nanoseconds

        Returns:
            Tuple of (success: bool, migrated_columns: list of (old_col, new_col))
        """
        migrated_columns = []
        error_str = str(error)

        if "cast error from protocol type" not in error_str:
            self._log_error(f"QuestDB: Non-cast error writing to {table_name}: {error}")
            return False, migrated_columns

        # Parse the error to find the problematic column
        table_match = re.search(r"table:\s+(.+?),", error_str)
        column_match = re.search(r"column:\s+(.+?);", error_str)
        type_match = re.search(r"protocol type:\s+([A-Z]+)\s", error_str)

        if not (table_match and column_match and type_match):
            self._log_error(f"QuestDB: Could not parse cast error: {error}")
            return False, migrated_columns

        col_name = column_match.group(1)
        expected_type = type_match.group(1).lower()

        # Try to adapt the value
        if col_name in columns:
            original_value = columns[col_name]
            adapted_value = self._try_adapt_value(original_value, expected_type)

            if adapted_value is not None:
                columns[col_name] = adapted_value
                try:
                    self.connect_ingest()
                    self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
                    return True, migrated_columns
                except IngressError:
                    pass

            # Adaptation failed - write to new column
            new_col = f"{col_name}__MIGRATED"
            columns[new_col] = columns.pop(col_name)
            migrated_columns.append((col_name, new_col))
            self._log_warn(f"QuestDB: Schema mismatch, {col_name} -> {new_col}")

            try:
                self.connect_ingest()
                self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
                return True, migrated_columns
            except IngressError as e2:
                self._log_error(f"QuestDB: Failed even with migrated column: {e2}")
                return False, migrated_columns

        return False, migrated_columns

    def _try_adapt_value(self, value, expected_type):
        """
        Try to adapt a value to the expected type.

        Args:
            value: The value to adapt
            expected_type: The expected QuestDB type (lowercase)

        Returns:
            Adapted value or None if adaptation not possible
        """
        try:
            if expected_type in ("int", "long"):
                if isinstance(value, float):
                    return int(value)
                elif isinstance(value, str):
                    return int(float(value))
            elif expected_type in ("float", "double"):
                if isinstance(value, (int, str)):
                    return float(value)
            elif expected_type == "varchar":
                return str(value)
        except (ValueError, TypeError):
            pass
        return None
