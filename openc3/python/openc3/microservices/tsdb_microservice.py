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

import os
import sys
import json
import traceback
from questdb.ingress import IngressError
from openc3.utilities.thread_manager import ThreadManager
from openc3.utilities.questdb_client import QuestDBClient
from openc3.microservices.microservice import Microservice
from openc3.topics.topic import Topic
from openc3.topics.config_topic import ConfigTopic
from openc3.api.tlm_api import get_tlm, get_all_tlm_names


class TsdbMicroservice(Microservice):
    def __init__(self, *args):
        super().__init__(*args)

        Topic.update_topic_offsets(self.topics)
        config_topic = f"{self.scope}{ConfigTopic.PRIMARY_KEY}"
        self.topic_offset = Topic.update_topic_offsets([config_topic])[0]

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
            self._create_table(target_name, packet_name)

    def _create_table(self, target_name, packet_name):
        """Create a table for a target/packet combination."""
        packet = get_tlm(target_name, packet_name)
        self.questdb.create_table(target_name, packet_name, packet)

    def sync_topics(self):
        """Update local topics based on config events"""
        config = ConfigTopic.read(offset=self.topic_offset, scope=os.environ.get("OPENC3_SCOPE"))
        if not config:
            return

        self.topic_offset = config[0][0]
        config_data = config[0][1]

        if config_data.get(b"type") == b"target":
            kind_bytes = config_data.get(b"kind")
            name_bytes = config_data.get(b"name")
            if not kind_bytes or not name_bytes:
                return
            kind = kind_bytes.decode()
            target_name = name_bytes.decode()

            if kind == "created":
                self.logger.info(f"New target {target_name} created")
                packets = get_all_tlm_names(target_name)
                for packet_name in packets:
                    self._create_table(target_name, packet_name)
                    self.topics.append(f"{os.environ.get('OPENC3_SCOPE')}__DECOM__{{{target_name}}}__{packet_name}")
            elif kind == "deleted":
                self.logger.info(f"Target {target_name} deleted")
                self.topics = [topic for topic in self.topics if f"__{{{target_name}}}__" not in topic]

    def read_topics(self):
        """Read topics and write data to QuestDB"""
        try:
            for _, _, msg_hash, _ in Topic.read_topics(self.topics):
                if self.cancel_thread:
                    break

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

                # Get sanitized table name
                table_name, _ = QuestDBClient.sanitize_table_name(target_name, packet_name)

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

                # Write to QuestDB with packet timestamp and received timestamp
                self.questdb.write_row(table_name, values, timestamp_ns, rx_timestamp_ns)

            # Flush the sender after the full topic read
            self.questdb.flush()

        except IngressError as error:
            # Try to handle the error (may alter schema for real-time ingestion)
            self.questdb.handle_ingress_error(error, table_name, values, timestamp_ns)

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

    def shutdown(self):
        """Graceful shutdown."""
        super().shutdown()
        self.questdb.close()


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    TsdbMicroservice.class_run()
    ThreadManager.instance().shutdown()
    ThreadManager.instance().join()
