# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import os
import re
import sys
import time
import traceback

from questdb.ingress import IngressError

from openc3.api.cmd_api import get_cmd
from openc3.api.tlm_api import get_tlm
from openc3.microservices.microservice import Microservice
from openc3.topics.config_topic import ConfigTopic
from openc3.topics.topic import Topic
from openc3.utilities.questdb_client import QuestDBClient
from openc3.utilities.store import EphemeralStore, Store
from openc3.utilities.thread_manager import ThreadManager


class TsdbMicroservice(Microservice):
    TRIM_KEEP_MS = 60000  # 1 minute

    # QuestDB returns "table does not exist" when QDB_LINE_AUTO_CREATE_NEW_TABLES=false
    # and an ILP write targets a table we haven't created (e.g. after a DROP from the admin UI).
    MISSING_TABLE_RE = re.compile(r"table\s+does\s+not\s+exist", re.IGNORECASE)
    ERROR_TABLE_NAME_RE = re.compile(r"table[=:\s]+(\w+)")

    def __init__(self, *args):
        super().__init__(*args)

        # Note: topic offsets are initialized after db_shard is determined below
        config_topic = f"{self.scope}{ConfigTopic.PRIMARY_KEY}"
        self.topic_offset = Topic.update_topic_offsets([config_topic])[0]

        # Extract retain time options from microservice config
        self.cmd_decom_retain_time = None
        self.tlm_decom_retain_time = None
        for option in self.config.get("options", []):
            if option[0] == "CMD_DECOM_RETAIN_TIME":
                self.cmd_decom_retain_time = option[1]
            elif option[0] == "TLM_DECOM_RETAIN_TIME":
                self.tlm_decom_retain_time = option[1]

        # Use shared QuestDB client with db_shard from microservice config
        if len(self.topics) <= 0:
            raise RuntimeError("No topics provided")
        topic_parts = self.topics[0].split("__")
        Topic.update_topic_offsets(self.topics, db_shard=self.db_shard)
        self.questdb = QuestDBClient(logger=self.logger, name=f"Microservice {self.name}", db_shard=self.db_shard)
        self.questdb.connect_ingest()
        self.questdb.connect_query()

        # Build the tables
        for topic in self.topics:
            topic_parts = topic.split("__")
            target_name = topic_parts[2].strip("{}")
            packet_name = topic_parts[3]
            if target_name == "UNKNOWN":
                continue
            self._create_table(target_name, packet_name, topic)

        # Setup first trim time
        self.next_trim_time_ms = int(time.time() * 1000) + self.TRIM_KEEP_MS

        # Initialize metrics
        self.ingest_count = 0
        self.error_count = 0
        self.metric.set(name="tsdb_ingest_total", value=self.ingest_count, type="counter")
        self.metric.set(name="tsdb_ingest_error_total", value=self.error_count, type="counter")

    def _create_table(self, target_name, packet_name, topic):
        """Create a table for a target/packet combination."""
        if "__DECOMCMD__" in topic:
            packet = get_cmd(target_name, packet_name)
            cmd_or_tlm = "CMD"
            retain_time = self.cmd_decom_retain_time
        else:
            packet = get_tlm(target_name, packet_name)
            cmd_or_tlm = "TLM"
            retain_time = self.tlm_decom_retain_time
        self.questdb.create_table(
            target_name, packet_name, packet, cmd_or_tlm, retain_time=retain_time, scope=self.scope
        )

    def read_topics(self):
        """Read topics and write data to QuestDB"""
        try:
            start = None
            for topic, msg_id, msg_hash, redis in Topic.read_topics(self.topics, db_shard=self.db_shard):
                if self.cancel_thread:
                    break

                if topic == self.microservice_topic:
                    self.microservice_cmd(topic, msg_id, msg_hash, redis)
                    continue

                if start is None:
                    start = time.time()
                    msgid_seconds_from_epoch = int(msg_id.split("-")[0]) / 1000.0
                    delta = time.time() - msgid_seconds_from_epoch
                    self.metric.set(
                        name="tsdb_ingest_topic_delta_seconds",
                        value=delta,
                        type="gauge",
                        unit="seconds",
                        help="Delta time between data written to stream and tsdb ingest start",
                    )

                target_name_bytes = msg_hash.get(b"target_name")
                packet_name_bytes = msg_hash.get(b"packet_name")
                if not target_name_bytes or not packet_name_bytes:
                    self.logger.warn("QuestDB: Missing target_name or packet_name in message")
                    continue
                target_name = target_name_bytes.decode()
                packet_name = packet_name_bytes.decode()

                try:
                    json_data = json.loads(msg_hash.get(b"json_data", b"{}"))
                except (json.JSONDecodeError, TypeError):
                    self.logger.error(f"Failed to parse json_data for {target_name}.{packet_name}")
                    continue

                # Determine if this is a command or telemetry packet based on topic
                cmd_or_tlm = "CMD" if "__DECOMCMD__" in topic else "TLM"

                # Get sanitized table name
                table_name, _ = QuestDBClient.sanitize_table_name(
                    target_name, packet_name, cmd_or_tlm, scope=self.scope
                )

                # Get packet timestamp (packet_time) and received timestamp (received_time) in nanoseconds
                time_bytes = msg_hash.get(b"time")
                if not time_bytes:
                    self.logger.warn(f"QuestDB: Missing time in message for {target_name}.{packet_name}")
                    continue
                timestamp_ns = int(time_bytes.decode())

                # Get received time directly from message (more efficient than extracting from json_data)
                received_time_bytes = msg_hash.get(b"received_time")
                rx_timestamp_ns = int(received_time_bytes.decode()) if received_time_bytes else None

                # Process JSON data into QuestDB-compatible columns
                values = self.questdb.process_json_data(json_data, table_name)

                if not values:
                    self.logger.warn(f"QuestDB: No valid items found for {target_name} {packet_name}")
                    continue

                # Extract extra field from message hash
                extra_data = msg_hash.get(b"extra")
                if extra_data:
                    values["COSMOS_EXTRA"] = extra_data.decode()

                # Write to QuestDB with packet timestamp and received timestamp
                self.questdb.write_row(table_name, values, timestamp_ns, rx_timestamp_ns)
                self.ingest_count += 1

            # Flush the sender after the full topic read
            self.questdb.flush()
            if start is not None:
                diff = time.time() - start  # seconds as a float
                self.metric.set(name="tsdb_ingest_duration_seconds", value=diff, type="gauge", unit="seconds")
            self.metric.set(name="tsdb_ingest_total", value=self.ingest_count, type="counter")

        except IngressError as error:
            # Cast the value to fit the column type and retry
            self.error_count += 1
            self.metric.set(name="tsdb_ingest_error_total", value=self.error_count, type="counter")
            if self.MISSING_TABLE_RE.search(str(error)):
                # Table was dropped (e.g. via admin UI). Recreate with proper COSMOS schema
                # and replay pending rows. ILP auto-create is disabled to prevent QuestDB
                # from creating a schema-less table with the wrong designated TIMESTAMP.
                self._handle_missing_table(error)
            else:
                # Cast the value to fit the column type and retry
                self.questdb.handle_ingress_error(error)

    def _handle_missing_table(self, error):
        """Recreate a table that ILP rejected because it does not exist."""
        error_message = str(error)
        self.logger.warn(f"QuestDB: Missing table IngressError: {error_message}")

        match = self.ERROR_TABLE_NAME_RE.search(error_message)
        if not match:
            self.logger.error(f"QuestDB: Could not parse table name from error: {error_message}")
            self._reset_after_error()
            return

        table_name = match.group(1)
        parts = table_name.split("__")
        if len(parts) < 4:
            self.logger.error(f"QuestDB: Invalid table name format '{table_name}' in error")
            self._reset_after_error()
            return

        scope, cmd_or_tlm, target_name, packet_name = parts[0], parts[1], parts[2], parts[3]
        try:
            if cmd_or_tlm == "CMD":
                packet = get_cmd(target_name, packet_name)
                retain_time = self.cmd_decom_retain_time
            else:
                packet = get_tlm(target_name, packet_name)
                retain_time = self.tlm_decom_retain_time

            # create_table raises on fatal DDL failure (including connection errors after retry),
            # so if this call returns, the table exists and we can safely replay.
            self.questdb.create_table(
                target_name, packet_name, packet, cmd_or_tlm, retain_time=retain_time, scope=scope
            )
            self.logger.info(f"QuestDB: Recreated missing table {table_name}, replaying pending rows")
            pending_count = len(self.questdb.pending_rows)
            self.questdb._reconnect_and_retry_pending()
            self.questdb.flush()
            self.logger.info(f"QuestDB: Replayed {pending_count} pending rows for {table_name}")
        except Exception as exc:
            self.logger.error(f"QuestDB: Failed to recreate table {table_name}: {exc}\n{traceback.format_exc()}")
            self._reset_after_error()

    def _reset_after_error(self):
        """Discard pending rows and reopen the ILP sender."""
        self.questdb.pending_rows.clear()
        try:
            self.questdb.connect_ingest()
        except Exception:
            self.logger.error(f"QuestDB: Failed to reconnect:\n{traceback.format_exc()}")

    def trim_topics(self):
        current_time_ms = int(time.time() * 1000)
        if current_time_ms > self.next_trim_time_ms:
            self.next_trim_time_ms = current_time_ms + self.TRIM_KEEP_MS
            trim_time_ms = current_time_ms - self.TRIM_KEEP_MS
            trim_offset = f"{trim_time_ms}-0"
            redis = EphemeralStore.instance(db_shard=self.db_shard)
            pipeline = redis.pipeline(transaction=False)
            for topic in self.topics:
                pipeline.xtrim(name=topic, minid=trim_offset, approximate=True, limit=0)
            pipeline.execute()

    def run(self):
        """Main run loop"""
        self.setup_microservice_topic()
        while True:
            if self.cancel_thread:
                break
            try:
                self.read_topics()
                self.trim_topics()
                self.count += 1
            except Exception as error:
                self.error = error
                self.logger.error(f"QuestDB: Microservice error:\n{traceback.format_exc()}")
                self.questdb.pending_rows.clear()
                try:
                    time.sleep(0.1)
                    self.questdb.connect_ingest()
                    self.logger.info("QuestDB: Reconnected after error")
                except Exception:
                    self.logger.error(f"QuestDB: Failed to reconnect:\n{traceback.format_exc()}")

    def shutdown(self):
        """Graceful shutdown."""
        super().shutdown()
        self.questdb.flush()
        self.questdb.close()


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    TsdbMicroservice.class_run()
    ThreadManager.instance().shutdown()
    ThreadManager.instance().join()
