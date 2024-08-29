# Copyright 2024 OpenC3, Inc.
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
import time
import json
from datetime import datetime, timezone
from openc3.microservices.microservice import Microservice
from openc3.system.system import System
from openc3.topics.topic import Topic
from openc3.topics.limits_event_topic import LimitsEventTopic
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.config.config_parser import ConfigParser
from openc3.utilities.time import to_nsec_from_epoch, from_nsec_from_epoch, formatted
from openc3.microservices.interface_decom_common import (
    handle_build_cmd,
    handle_inject_tlm,
)


class DecomMicroservice(Microservice):
    def __init__(self, *args):
        super().__init__(*args)
        # Should only be one target, but there might be multiple decom microservices for a given target
        # First Decom microservice has no number in the name
        if "__DECOM__" in self.name:
            self.topics.append(f"{self.scope}__DECOMINTERFACE__{{{self.target_names[0]}}}")
        Topic.update_topic_offsets(self.topics)
        System.telemetry.set_limits_change_callback(self.limits_change_callback)
        LimitsEventTopic.sync_system(scope=self.scope)
        self.error_count = 0
        self.metric.set(name="decom_total", value=self.count, type="counter")
        self.metric.set(name="decom_error_total", value=self.error_count, type="counter")

    def run(self):
        self.setup_microservice_topic()
        while True:
            if self.cancel_thread:
                break
            try:
                # OpenC3.in_span("read_topics") do
                for topic, msg_id, msg_hash, redis in Topic.read_topics(self.topics):
                    if self.cancel_thread:
                        break

                    if topic == self.microservice_topic:
                        self.microservice_cmd(topic, msg_id, msg_hash, redis)
                    elif "__DECOMINTERFACE__" in topic:
                        if msg_hash.get(b"inject_tlm"):
                            handle_inject_tlm(msg_hash[b"inject_tlm"], self.scope)
                            continue
                        if msg_hash.get(b"build_cmd"):
                            handle_build_cmd(msg_hash[b"build_cmd"], msg_id, self.scope)
                            continue
                    else:
                        self.decom_packet(topic, msg_id, msg_hash, redis)
                        self.metric.set(name="decom_total", value=self.count, type="counter")
                    self.count += 1
                LimitsEventTopic.sync_system_thread_body(scope=self.scope)
            except Exception as error:
                self.error_count += 1
                self.metric.set(name="decom_error_total", value=self.error_count, type="counter")
                self.error = error
                self.logger.error(f"Decom error {repr(error)}")

    def decom_packet(self, topic, msg_id, msg_hash, _redis):
        # OpenC3.in_span("decom_packet") do
        msgid_seconds_from_epoch = int(msg_id.split("-")[0]) / 1000.0
        delta = time.time() - msgid_seconds_from_epoch
        self.metric.set(
            name="decom_topic_delta_seconds",
            value=delta,
            type="gauge",
            unit="seconds",
            help="Delta time between data written to stream and decom start",
        )

        start = time.time()
        target_name = msg_hash[b"target_name"].decode()
        packet_name = msg_hash[b"packet_name"].decode()

        packet = System.telemetry.packet(target_name, packet_name)
        packet.stored = ConfigParser.handle_true_false(msg_hash[b"stored"].decode())
        # Note: Packet time will be recalculated as part of decom so not setting
        packet.received_time = from_nsec_from_epoch(int(msg_hash[b"received_time"].decode()))
        packet.received_count = int(msg_hash[b"received_count"].decode())
        extra = msg_hash.get(b"extra")
        if extra is not None:
            packet.extra = json.loads(extra)
        packet.buffer = msg_hash[b"buffer"]
        # The Processor and LimitsResponse are user code points which must be rescued
        # so the TelemetryDecomTopic can write the packet
        try:
            packet.process()  # Run processors
            packet.check_limits(
                System.limits_set()
            )  # Process all the limits and call the limits_change_callback (as necessary)
        except Exception as error:
            self.error_count += 1
            self.metric.set(name="decom_error_total", value=self.error_count, type="counter")
            self.error = error
            self.logger.error(repr(error))

        TelemetryDecomTopic.write_packet(packet, scope=self.scope)
        diff = time.time() - start  # seconds as a float
        self.metric.set(name="decom_duration_seconds", value=diff, type="gauge", unit="seconds")

    # Called when an item in any packet changes limits states.
    #
    # @param packet [Packet] Packet which has had an item change limits state
    # @param item [PacketItem] The item which has changed limits state
    # @param old_limits_state [Symbol] The previous state of the item. See
    #   {PacketItemLimits#state}
    # @param value [Object] The current value of the item
    # @param log_change [Boolean] Whether to log this limits change event
    def limits_change_callback(self, packet, item, old_limits_state, value, log_change):
        if self.cancel_thread:
            return
        packet_time = packet.packet_time
        if value:
            message = f"{packet.target_name} {packet.packet_name} {item.name} = {value} is {item.limits.state}"
        else:
            message = f"{packet.target_name} {packet.packet_name} {item.name} is disabled"
        if packet_time:
            message += f" ({formatted(packet.packet_time)})"

        if packet_time:
            time_nsec = to_nsec_from_epoch(packet_time)
        else:
            time_nsec = to_nsec_from_epoch(datetime.now(timezone.utc))
        if log_change:
            match item.limits.state:
                case "BLUE" | "GREEN" | "GREEN_LOW" | "GREEN_HIGH":
                    # Only print INFO messages if we're changing ... not on initialization
                    if old_limits_state:
                        self.logger.info(message)
                case "YELLOW" | "YELLOW_LOW" | "YELLOW_HIGH":
                    self.logger.warn(message, type=self.logger.NOTIFICATION)
                case "RED" | "RED_LOW" | "RED_HIGH":
                    self.logger.error(message, type=self.logger.ALERT)

        # The openc3_limits_events topic can be listened to for all limits events, it is a continuous stream
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": packet.target_name,
            "packet_name": packet.packet_name,
            "item_name": item.name,
            "old_limits_state": str(old_limits_state),
            "new_limits_state": str(item.limits.state),
            "time_nsec": time_nsec,
            "message": str(message),
        }
        LimitsEventTopic.write(event, scope=self.scope)

        if item.limits.response is not None:
            try:
                item.limits.response.call(packet, item, old_limits_state)
            except Exception as error:
                self.error = error
                self.logger.error(f"{packet.target_name} {packet.packet_name} {item.name} Limits Response Exception!")
                self.logger.error(f"Called with old_state = {old_limits_state}, new_state = {item.limits.state}")
                self.logger.error(repr(error))


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    DecomMicroservice.class_run()
