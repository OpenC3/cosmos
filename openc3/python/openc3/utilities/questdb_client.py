# Copyright 2025 OpenC3, Inc.
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
import numbers
import psycopg
import numpy
from questdb.ingress import Sender, IngressError, Protocol, TimestampMicros, TimestampNanos
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.logger import Logger


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

    def __init__(self, logger=None):
        """
        Initialize QuestDB client.

        Args:
            logger: Optional logger instance. If not provided, creates a new one.
        """
        self.logger = logger or Logger()
        self.ingest = None
        self.query = None

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
            raise RuntimeError("Missing env var OPENC3_TSDB_HOSTNAME")
        if ingest_port:
            ingest_port = int(ingest_port)
        else:
            raise RuntimeError("Missing env var OPENC3_TSDB_INGEST_PORT")
        if not username:
            raise RuntimeError("Missing env var OPENC3_TSDB_USERNAME")
        if not password:
            raise RuntimeError("Missing env var OPENC3_TSDB_PASSWORD")

        try:
            if self.ingest:
                self.ingest.close()
            self.ingest = Sender(Protocol.Http, host, ingest_port, username=username, password=password)
            self.ingest.establish()
        except Exception as e:
            raise ConnectionError(f"Failed to connect to QuestDB ingest: {e}")

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
            raise RuntimeError("Missing env var OPENC3_TSDB_HOSTNAME")
        if query_port:
            query_port = int(query_port)
        else:
            raise RuntimeError("Missing env var OPENC3_TSDB_QUERY_PORT")
        if not username:
            raise RuntimeError("Missing env var OPENC3_TSDB_USERNAME")
        if not password:
            raise RuntimeError("Missing env var OPENC3_TSDB_PASSWORD")

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
            raise ConnectionError(f"Failed to connect to QuestDB query: {e}")

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

    @classmethod
    def convert_value(cls, value, item_name=None):
        """
        Convert a value to a QuestDB-compatible format.

        Args:
            value: The value to convert
            item_name: Optional item name for logging

        Returns:
            Converted value or None if value should be skipped
        """
        match value:
            case int():
                if value > (2**63 - 1):  # max int64 value
                    value = 2**63 - 1
                elif value < (-(2**63) + 1):
                    # QuestDB treats int64 min value as NULL, so we set it to -2^63 + 1
                    value = -(2**63) + 1

            case float() | str() | None:
                pass

            case bytes():
                value = base64.b64encode(value).decode("ascii")

            case list():
                # QuestDB 9.0.0 only supports DOUBLE arrays
                if len(value) > 0 and not isinstance(value[0], numbers.Number):
                    # If the list is not numeric, convert to JSON string
                    value = json.dumps(value)
                elif len(value) > 0:
                    value = numpy.array(value, dtype=numpy.float64)

            case dict():
                if value.get("json_class") == "Float":
                    # NaN and Infinity values serialized as dict
                    value = float(value["raw"])
                elif value.get("json_class") == "String" and isinstance(value.get("raw"), list):
                    # Blocks of data serialized as lists
                    value = base64.b64encode(bytes(value["raw"])).decode("ascii")
                else:
                    return None  # Unknown dict format

            case _:
                return None  # Unsupported type

        return value

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
            self.logger.warn(
                f"QuestDB: Target / packet {orig_table_name} changed to {table_name} due to invalid characters"
            )

        # Build column definitions for all packet items
        column_definitions = []

        for item in packet.get("items", []):
            item_name = self.sanitize_column_name(item["name"])

            # Skip standard derived items as they're explicitly created
            if item_name in [
                "PACKET_TIMESECONDS",
                "RECEIVED_TIMESECONDS",
                "PACKET_TIMEFORMATTED",
                "RECEIVED_TIMEFORMATTED",
                "RECEIVED_COUNT",
            ]:
                continue

            # Skip DERIVED items since it's hard to know what type they are
            if item.get("data_type") == "DERIVED":
                continue

            if item.get("array_size"):
                column_type = "array"
                column_definitions.append(f'"{item_name}" {column_type}')
            else:
                column_type = "VARCHAR"  # Default

                if item.get("data_type") in ["INT", "UINT"]:
                    if item.get("bit_size", 32) < 32:
                        column_type = "int"
                    elif item.get("bit_size", 32) <= 64:
                        column_type = "long"
                    else:
                        column_type = "varchar"
                elif item.get("data_type") == "FLOAT":
                    if item.get("bit_size") == 32:
                        column_type = "float"
                    else:
                        column_type = "double"
                elif item.get("data_type") in ["STRING", "BLOCK"]:
                    column_type = "varchar"

                column_definitions.append(f'"{item_name}" {column_type}')

                if item.get("states"):
                    column_definitions.append(f'"{item_name}__C" varchar')
                elif item.get("read_conversion"):
                    rc = item["read_conversion"]
                    if rc.get("converted_type") == "FLOAT":
                        if rc.get("converted_bit_size") == 32:
                            column_definitions.append(f'"{item_name}__C" float')
                        else:
                            column_definitions.append(f'"{item_name}__C" double')
                    elif rc.get("converted_type") in ["INT", "UINT"]:
                        if rc.get("converted_bit_size", 32) < 32:
                            column_definitions.append(f'"{item_name}__C" int')
                        elif rc.get("converted_bit_size", 32) <= 64:
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
                        timestamp timestamp,
                        tag SYMBOL,
                        PACKET_TIMESECONDS timestamp,
                        RECEIVED_TIMESECONDS timestamp,
                        PACKET_TIMEFORMATTED varchar,
                        RECEIVED_TIMEFORMATTED varchar,
                        RECEIVED_COUNT LONG"""

                if columns_sql:
                    sql += f",\n{columns_sql}"

                sql += """
                    ) TIMESTAMP(timestamp)
                        PARTITION BY DAY
                        DEDUP UPSERT KEYS (timestamp, tag)
                """

                self.logger.info(f"QuestDB: Creating table:\n{sql}")
                cur.execute(sql)
        except psycopg.Error as error:
            self.logger.error(f"QuestDB: Error creating table {table_name}: {error}")

        return table_name

    def write_row(self, table_name, columns, timestamp_ns):
        """
        Write a single row to QuestDB.

        Args:
            table_name: Target table name (already sanitized)
            columns: Dict of column_name -> value
            timestamp_ns: Timestamp in nanoseconds

        Returns:
            True if successful, False otherwise
        """
        try:
            self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
            return True
        except IngressError as e:
            self.logger.warn(f"QuestDB: IngressError writing to {table_name}: {e}")
            return False

    def write_row_with_schema_protection(self, table_name, columns, timestamp_ns):
        """
        Write a row with schema protection - adapts data or creates new columns on mismatch.

        This method protects the existing schema by:
        1. Attempting normal write
        2. On cast error, trying to adapt the value
        3. If adaptation fails, writing to a new __MIGRATED column

        Args:
            table_name: Target table name (already sanitized)
            columns: Dict of column_name -> value
            timestamp_ns: Timestamp in nanoseconds

        Returns:
            Tuple of (success: bool, migrated_columns: list)
        """
        migrated_columns = []

        try:
            self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
            return True, migrated_columns
        except IngressError as e:
            error_str = str(e)
            if "cast error from protocol type" not in error_str:
                self.logger.error(f"QuestDB: Non-cast error writing to {table_name}: {e}")
                return False, migrated_columns

            # Parse the error to find the problematic column
            table_match = re.search(r"table:\s+(.+?),", error_str)
            column_match = re.search(r"column:\s+(.+?);", error_str)
            type_match = re.search(r"protocol type:\s+([A-Z]+)\s", error_str)

            if not (table_match and column_match and type_match):
                self.logger.error(f"QuestDB: Could not parse cast error: {e}")
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
                        # Reconnect after error
                        self.connect_ingest()
                        self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
                        return True, migrated_columns
                    except IngressError:
                        pass

                # Adaptation failed - write to new column
                new_col = f"{col_name}__MIGRATED"
                columns[new_col] = columns.pop(col_name)
                migrated_columns.append((col_name, new_col))
                self.logger.warn(f"QuestDB: Schema mismatch, {col_name} -> {new_col}")

                try:
                    self.connect_ingest()
                    self.ingest.row(table_name, columns=columns, at=TimestampNanos(timestamp_ns))
                    return True, migrated_columns
                except IngressError as e2:
                    self.logger.error(f"QuestDB: Failed even with migrated column: {e2}")
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

    def flush(self):
        """Flush pending writes to QuestDB."""
        if self.ingest:
            self.ingest.flush()

    def process_json_data(self, json_data, for_migration=False):
        """
        Process JSON data dict into QuestDB-compatible columns.

        Args:
            json_data: Dict of item_name -> value
            for_migration: If True, uses schema protection for writes

        Returns:
            Dict of sanitized_column_name -> converted_value
        """
        columns = {}
        for orig_item_name, value in json_data.items():
            converted = self.convert_value(value, orig_item_name)
            if converted is None:
                continue

            item_name = self.sanitize_column_name(orig_item_name)

            # Handle timestamp columns specially
            if item_name in ("PACKET_TIMESECONDS", "RECEIVED_TIMESECONDS"):
                columns[item_name] = TimestampMicros(int(converted * 1_000_000))
            else:
                columns[item_name] = converted

        return columns
