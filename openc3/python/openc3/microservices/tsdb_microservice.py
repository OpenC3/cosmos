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
from openc3.utilities.store import EphemeralStore
from openc3.utilities.thread_manager import ThreadManager


class TsdbMicroservice(Microservice):
    TRIM_KEEP_MS = 60000  # 1 minute

    def __init__(self, *args):
        super().__init__(*args)

        Topic.update_topic_offsets(self.topics)
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

        # Use shared QuestDB client
        self.questdb = QuestDBClient(logger=self.logger, name=f"Microservice {self.name}")
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
        self.questdb.create_table(target_name, packet_name, packet, cmd_or_tlm, retain_time=retain_time, scope=self.scope)

    def read_topics(self):
        """Read topics and write data to QuestDB"""
        try:
            for topic, msg_id, msg_hash, redis in Topic.read_topics(self.topics):
                if self.cancel_thread:
                    break

                if topic == self.microservice_topic:
                    self.microservice_cmd(topic, msg_id, msg_hash, redis)
                    continue

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
                table_name, _ = QuestDBClient.sanitize_table_name(target_name, packet_name, cmd_or_tlm, scope=self.scope)

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

            # Flush the sender after the full topic read
            self.questdb.flush()

        except IngressError as error:
            # Cast the value to fit the column type and retry
            self.questdb.handle_ingress_error(error, table_name, values, timestamp_ns)

    def trim_topics(self):
        current_time_ms = int(time.time() * 1000)
        if current_time_ms > self.next_trim_time_ms:
            self.next_trim_time_ms = current_time_ms + self.TRIM_KEEP_MS
            trim_time_ms = current_time_ms - self.TRIM_KEEP_MS
            trim_offset = f"{trim_time_ms}-0"
            redis = EphemeralStore.instance()
            pipeline = redis.pipeline(transaction=False)
            for topic in self.topics:
                pipeline.xtrim(name=topic, minid=trim_offset, approximate=True, limit=0)
            pipeline.execute()

    def run(self):
        """Main run loop"""
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

    def shutdown(self):
        """Graceful shutdown."""
        super().shutdown()
        self.questdb.close()


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    TsdbMicroservice.class_run()
    ThreadManager.instance().shutdown()
    ThreadManager.instance().join()
