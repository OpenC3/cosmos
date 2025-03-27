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
import sys
import time
import json
import threading
import queue
from openc3.microservices.microservice import Microservice
from openc3.system.system import System
from openc3.topics.topic import Topic
from openc3.topics.limits_event_topic import LimitsEventTopic
from openc3.topics.telemetry_decom_topic import TelemetryDecomTopic
from openc3.config.config_parser import ConfigParser
from openc3.utilities.time import to_nsec_from_epoch, from_nsec_from_epoch
from openc3.utilities.thread_manager import ThreadManager
from openc3.microservices.interface_decom_common import (
    handle_build_cmd,
    handle_inject_tlm,
)
from openc3.top_level import kill_thread


class LimitsResponseThread:
    def __init__(self, microservice_name, queue, logger, metric, scope):
        self.microservice_name = microservice_name
        self.queue = queue
        self.logger = logger
        self.metric = metric
        self.scope = scope
        self.count = 0
        self.error_count = 0
        self.metric.set(name="limits_response_total", value=self.count, type="counter")
        self.metric.set(name="limits_response_error_total", value=self.error_count, type="counter")

    def start(self):
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()
        ThreadManager.instance().register(self.thread, stop_object=self)
        return self.thread

    def stop(self):
        if self.thread:
            kill_thread(self, self.thread)
            self.thread = None

    def graceful_kill(self):
        self.queue.put([None, None, None])

    def run(self):
        try:
            while True:
                packet, item, old_limits_state = self.queue.get()
                if packet is None:
                    break

                try:
                    item.limits.response.call(packet, item, old_limits_state)
                except Exception as error:
                    self.error_count += 1
                    self.metric.set(name="limits_response_error_total", value=self.error_count, type="counter")
                    self.logger.error(
                        f"{packet.target_name} {packet.packet_name} {item.name} Limits Response Exception!"
                    )
                    self.logger.error(f"Called with old_state = {old_limits_state}, new_state = {item.limits.state}")
                    self.logger.error(repr(error))

                self.count += 1
                self.metric.set(name="limits_response_total", value=self.count, type="counter")
        except Exception as error:
            self.logger.error(f"{self.microservice_name}: Limits Response thread died: {repr(error)}")
            raise error


class DecomMicroservice(Microservice):
    LIMITS_STATE_INDEX = {
        "RED_LOW": 0,
        "YELLOW_LOW": 1,
        "YELLOW_HIGH": 2,
        "RED_HIGH": 3,
        "GREEN_LOW": 4,
        "GREEN_HIGH": 5,
    }

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
        self.limits_response_queue = queue.Queue()
        self.limits_response_thread = None

    def run(self):
        self.limits_response_thread = LimitsResponseThread(
            microservice_name=self.name,
            queue=self.limits_response_queue,
            logger=self.logger,
            metric=self.metric,
            scope=self.scope,
        )
        self.limits_response_thread.start()

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

        self.limits_response_thread.stop()
        self.limits_response_thread = None

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
        # Processors are user code points which must be rescued
        # so the TelemetryDecomTopic can write the packet
        try:
            packet.process()  # Run processors
        except Exception as error:
            self.error_count += 1
            self.metric.set(name="decom_error_total", value=self.error_count, type="counter")
            self.error = error
            self.logger.error(repr(error))
        # Process all the limits and call the limits_change_callback (as necessary)
        # check_limits also can call user code in the limits response
        # but that is rescued separately in the limits_change_callback
        packet.check_limits(System.limits_set())

        # This is what updates the CVT
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
            if item.limits.values:
                values = item.limits.values[System.limits_set()]
                # Check if the state is RED_LOW, YELLOW_LOW, YELLOW_HIGH, RED_HIGH, GREEN_LOW, GREEN_HIGH
                if DecomMicroservice.LIMITS_STATE_INDEX.get(item.limits.state, None) is not None:
                    # Directly index into the values and return the value
                    message += f" ({values[DecomMicroservice.LIMITS_STATE_INDEX[item.limits.state]]})"
                elif item.limits.state == "GREEN":
                    # If we're green we display the green range (YELLOW_LOW - YELLOW_HIGH)
                    message += f" ({values[1]} to {values[2]})"
                elif item.limits.state == "BLUE":
                    # If we're blue we display the blue range (GREEN_LOW - GREEN_HIGH)
                    message += f" ({values[4]} to {values[5]})"
        else:
            message = f"{packet.target_name} {packet.packet_name} {item.name} is disabled"

        # Include the packet_time in the log json but not the log message
        # Can't use isoformat because it appends "+00:00" instead of "Z"
        time = {"packet_time": packet_time.strftime("%Y-%m-%dT%H:%M:%S.%fZ")}
        if log_change:
            match item.limits.state:
                case "BLUE" | "GREEN" | "GREEN_LOW" | "GREEN_HIGH":
                    # Only print INFO messages if we're changing ... not on initialization
                    if old_limits_state:
                        self.logger.info(message, other=time)
                case "YELLOW" | "YELLOW_LOW" | "YELLOW_HIGH":
                    self.logger.warn(message, other=time, type=self.logger.NOTIFICATION)
                case "RED" | "RED_LOW" | "RED_HIGH":
                    self.logger.error(message, other=time, type=self.logger.ALERT)

        # The openc3_limits_events topic can be listened to for all limits events, it is a continuous stream
        event = {
            "type": "LIMITS_CHANGE",
            "target_name": packet.target_name,
            "packet_name": packet.packet_name,
            "item_name": item.name,
            "old_limits_state": str(old_limits_state),
            "new_limits_state": str(item.limits.state),
            "time_nsec": to_nsec_from_epoch(packet_time),
            "message": str(message),
        }
        LimitsEventTopic.write(event, scope=self.scope)

        if item.limits.response is not None:
            copied_packet = packet.deep_copy()
            copied_item = packet.items[item.name]
            self.limits_response_queue.put([copied_packet, copied_item, old_limits_state])


if os.path.basename(__file__) == os.path.basename(sys.argv[0]):
    DecomMicroservice.class_run()
    ThreadManager.instance().shutdown()
    ThreadManager.instance().join()
