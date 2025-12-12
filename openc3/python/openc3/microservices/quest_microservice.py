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

import os
import re
import sys
import json
import base64
import numbers
import psycopg
import traceback
import numpy
from questdb.ingress import Sender, IngressError, Protocol, TimestampMicros, TimestampNanos
from openc3.utilities.thread_manager import ThreadManager
from openc3.microservices.microservice import Microservice
from openc3.topics.topic import Topic
from openc3.topics.config_topic import ConfigTopic
from openc3.api.tlm_api import get_all_tlm_names


class QuestMicroservice(Microservice):
    def __init__(self, *args):
        super().__init__(*args)

        Topic.update_topic_offsets(self.topics)
        config_topic = f"{self.scope}{ConfigTopic.PRIMARY_KEY}"
        self.topic_offset = Topic.update_topic_offsets([config_topic])[0]

        self.ingest = None
        self.connect_ingest()
        self.query = None
        self.connect_query()

        # Build the tables
        for topic in self.topics:
            topic_parts = topic.split("__")
            target_name = topic_parts[2].strip("{}")
            packet_name = topic_parts[3]
            if target_name == "UNKNOWN":
                continue
            self.create_table(target_name, packet_name)

    def connect_ingest(self):
        host = os.environ.get("OPENC3_TSDB_HOSTNAME")
        ingest_port = os.environ.get("OPENC3_TSDB_INGEST_PORT")
        username = os.environ.get("OPENC3_TSDB_USERNAME")
        password = os.environ.get("OPENC3_TSDB_PASSWORD")

        if not host:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_HOSTNAME")
        if ingest_port:
            ingest_port = int(ingest_port)
        else:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_INGEST_PORT")
        if not username:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_USERNAME")
        if not password:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_PASSWORD")

        try:
            if self.ingest:
                self.ingest.close()
            self.ingest = Sender(Protocol.Http, host, ingest_port, username=username, password=password)
            self.ingest.establish()
        except Exception as e:
            raise ConnectionError(f"Failed to connect to QuestDB: {e}")

    def connect_query(self):
        host = os.environ.get("OPENC3_TSDB_HOSTNAME")
        query_port = os.environ.get("OPENC3_TSDB_QUERY_PORT")
        username = os.environ.get("OPENC3_TSDB_USERNAME")
        password = os.environ.get("OPENC3_TSDB_PASSWORD")

        if not host:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_HOSTNAME")
        if query_port:
            query_port = int(query_port)
        else:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_QUERY_PORT")
        if not username:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_USERNAME")
        if not password:
            raise RuntimeError(f"Microservice {self.name} missing env var OPENC3_TSDB_PASSWORD")

        # Initialize QuestDB connection
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

    def create_table(self, target_name, packet_name):
        orig_table_name = f"{target_name}__{packet_name}"
        # Remove invalid characters from the table name
        # This could potentially result in overlap (TGT?0 == TGT:0 == TGT_0)
        # so warn the user that they chose some really bad tgt / pkt names
        # Replace the following characters with underscore: ?,'"\/:)(+*%~
        # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
        table_name = re.sub(r'[?,\'"\\/:)(+*%~]', "_", orig_table_name)
        if table_name != orig_table_name:
            self.logger.warn(
                f"QuestDB: Target / packet {orig_table_name} changed to {table_name} due to invalid characters"
            )

        try:
            # Open a cursor to perform database operations
            with self.query.cursor() as cur:
                # Execute a command: this creates a new table
                cur.execute(
                    f"""
                    CREATE TABLE IF NOT EXISTS "{table_name}" (
                        timestamp TIMESTAMP,
                        tag SYMBOL,
                        PACKET_TIMESECONDS TIMESTAMP,
                        RECEIVED_TIMESECONDS TIMESTAMP
                    ) TIMESTAMP(timestamp)
                        PARTITION BY DAY
                        DEDUP UPSERT KEYS (timestamp, tag)
                """
                )
        except psycopg.Error as error:
            self.logger.error(f"QuestDB: Error creating table {table_name}: {error}")

    def sync_topics(self):
        """Update local topics based on config events"""
        config = ConfigTopic.read(offset=self.topic_offset, scope=os.environ.get("OPENC3_SCOPE"))
        if not config:
            return

        self.topic_offset = config[0][0]
        config_data = config[0][1]

        if config_data.get(b"type") == b"target":
            kind = config_data.get(b"kind").decode()
            target_name = config_data.get(b"name").decode()

            if kind == "created":
                self.logger.info(f"New target {target_name} created")
                packets = get_all_tlm_names(target_name)
                for packet_name in packets:
                    self.create_table(target_name, packet_name)
                    self.topics.append(f"{os.environ.get("OPENC3_SCOPE")}__DECOM__{{{target_name}}}__{packet_name}")
            elif kind == "deleted":
                self.logger.info(f"Target {target_name} deleted")
                self.topics = [topic for topic in self.topics if f"__{{{target_name}}}__" not in topic]

    def _is_printable(self, value: str) -> bool:
        """Check if a string contains only printable characters"""
        try:
            return all(c.isprintable() or c.isspace() for c in str(value))
        except Exception:
            return False

    def read_topics(self):
        """Read topics and write data to QuestDB"""
        try:
            for _, _, msg_hash, _ in Topic.read_topics(self.topics):
                if self.cancel_thread:
                    break

                target_name = msg_hash.get(b"target_name").decode()
                packet_name = msg_hash.get(b"packet_name").decode()

                try:
                    json_data = json.loads(msg_hash.get(b"json_data", "{}"))
                except (json.JSONDecodeError, TypeError):
                    self.logger.error(f"Failed to parse json_data for {target_name}.{packet_name}")
                    return

                # Replace the following characters with underscore: ?,'"\/:)(+*%~
                # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
                # Warning is generated once in create_table if replacement occurs
                table_name = re.sub(r'[?,\'"\\/:)(+*%~]', "_", f"{target_name}__{packet_name}")

                # This is the PACKET_TIMESECONDS as set in telemetry_decom_topic
                timestamp = int(msg_hash.get(b"time").decode())

                values = {}
                for orig_item_name, value in json_data.items():
                    # Handle various data types
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
                            # QuestDB 9.0.0 only supports DOUBLE arrays: https://questdb.com/docs/concept/array/
                            if not isinstance(value[0], numbers.Number):
                                # If the list is not numeric, convert to JSON string
                                value = json.dumps(value)
                            else:
                                value = numpy.array(value, dtype=numpy.float64)

                        case dict():
                            if value["json_class"] == "Float":
                                # We send over NaN and Infinity values as json serialized like:
                                #   {'json_class': 'Float', 'raw': 'NaN'}
                                value = float(value["raw"])
                            elif value["json_class"] == "String" and isinstance(value["raw"], list):
                                # We send over blocks of data as json serialized strings like:
                                #   {'json_class': 'String', 'raw': [15, 7, 9, 13, 7, 5, 14, 7 ... ]}
                                value = base64.b64encode(bytes(value["raw"])).decode("ascii")
                            else:
                                print(f"QuestDB: Unknown dict with name:{orig_item_name} value:{value}")
                                continue
                            if isinstance(value, list) and all(isinstance(b, int) and 0 <= b <= 255 for b in value):
                                value = base64.b64encode(bytes(value)).decode("ascii")

                        case _:
                            self.logger.warn(f"QuestDB: Unsupported value type for {orig_item_name}: {type(value)}")
                            continue

                    # Replace invalid characters in item names with underscore
                    # See https://questdb.com/docs/reference/api/ilp/advanced-settings/#name-restrictions
                    # NOTE: Semicolon added as it messes up queries
                    item_name = re.sub(r'[?\.,\'"\\/:)(+\-*%~;]', "_", orig_item_name)

                    match item_name:
                        case "PACKET_TIMESECONDS" | "RECEIVED_TIMESECONDS":
                            values[item_name] = TimestampMicros(int(value * 1_000_000))
                        case _:
                            values[item_name] = value

                if not values:
                    self.logger.warn(f"QuestDB: No valid items found for {target_name} {packet_name}")
                    continue

                # Write to QuestDB
                self.ingest.row(table_name, columns=values, at=TimestampNanos(timestamp))

            # Flush the sender after the full topic read
            self.ingest.flush()

        except IngressError as error:
            # First see if it's a cast error we can fix
            if "cast error from protocol type" in str(error):
                try:
                    # Open a cursor to perform database operations
                    with self.query.cursor() as cur:
                        # Extract table, column, and type from the error message

                        # Example error message:
                        # 'error in line 1: table: INST2__HEALTH_STATUS, column: TEMP1STDDEV;
                        # cast error from protocol type: FLOAT to column type: LONG","line":1,"errorId":"a507394ab099-25"'
                        error_message = str(error)
                        table_match = re.search(r"table:\s+(.+?),", error_message)  # .+? is non-greedy
                        column_match = re.search(r"column:\s+(.+?);", error_message)
                        type_match = re.search(r"protocol type:\s+([A-Z]+)\s", error_message)

                        if table_match and column_match and type_match:
                            table_name = table_match.group(1)
                            column_name = column_match.group(1)
                            column_type = type_match.group(1)
                        else:
                            self.logger.error("QuestDB: Could not parse table, column, or type from error message")
                            return

                        # Try to change the column type to fix the error
                        # We put the table in double quotes to handle special characters
                        alter = f"""ALTER TABLE "{table_name}" ALTER COLUMN {column_name} TYPE {column_type}"""
                        cur.execute(alter)
                        self.logger.info(f"QuestDB: {alter}")
                        self.connect_ingest()  # reconnect
                        # Retry write to QuestDB
                        self.ingest.row(table_name, columns=values, at=TimestampNanos(timestamp))
                except psycopg.Error as error:
                    self.logger.error(f"QuestDB: Error {alter}\n{error}")
            else:
                self.error = error
                self.logger.error(f"QuestDB: Error writing to QuestDB: {error}\n")

    def run(self):
        """Main run loop"""
        while True:
            if self.cancel_thread:
                break
            try:
                self.sync_topics()
                self.read_topics()
                self.count += 1
            except Exception as error:
                self.error = error
                self.logger.error(f"QuestDB: Microservice error:\n{traceback.format_exc()}")


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    QuestMicroservice.class_run()
    ThreadManager.instance().shutdown()
    ThreadManager.instance().join()
