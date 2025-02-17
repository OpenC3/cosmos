# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
from openc3.topics.topic import Topic
from openc3.system.system import System
from openc3.utilities.json import JsonEncoder
from openc3.environment import OPENC3_SCOPE


class RouterTopic(Topic):
    # Generate a list of topics for this router. This includes the router itself
    # and all the targets which are assigned to this router.
    @classmethod
    def topics(cls, router, scope=OPENC3_SCOPE):
        topics = []
        topics.append(f"{{{scope}__CMD}}ROUTER__{router.name}")
        for target_name in router.tlm_target_names:
            for _, packet in System.telemetry.packets(target_name).items():
                topics.append(f"{scope}__TELEMETRY__{{{packet.target_name}}}__{packet.packet_name}")
        return topics

    @classmethod
    def receive_telemetry(cls, router, scope=OPENC3_SCOPE):
        while True:
            for topic, msg_id, msg_hash, redis in Topic.read_topics(RouterTopic.topics(router, scope)):
                result = yield topic, msg_id, msg_hash, redis
                if "CMD}ROUTER" in topic:
                    ack_topic = topic.split("__")
                    ack_topic[1] = "ACK" + ack_topic[1]
                    ack_topic = "__".join(ack_topic)
                    Topic.write_topic(ack_topic, {"result": result}, msg_id, 100)

    @classmethod
    def route_command(cls, packet, target_names, scope=OPENC3_SCOPE):
        if packet.identified():
            topic = f"{{{scope}__CMD}}TARGET__{packet.target_name}"
            Topic.write_topic(
                topic,
                {
                    "target_name": packet.target_name,
                    "cmd_name": packet.packet_name,
                    "cmd_buffer": json.dumps(packet.buffer_no_copy(), cls=JsonEncoder),
                },
                "*",
                100,
            )
        elif len(target_names) == 1:
            topic = f"{{{scope}__CMD}}TARGET__{target_names[0]}"
            target_name = "UNKNOWN"
            if packet.target_name is not None:
                target_name = packet.target_name
            Topic.write_topic(
                topic,
                {
                    "target_name": target_name,
                    "cmd_name": "UNKNOWN",
                    "cmd_buffer": json.dumps(packet.buffer_no_copy(), cls=JsonEncoder),
                },
                "*",
                100,
            )
        else:
            target_name = "UNKNOWN"
            if packet.target_name is not None:
                target_name = packet.target_name
            packet_name = "UNKNOWN"
            if packet.packet_name is not None:
                packet = packet.packet_name
            raise RuntimeError(f"No route for command: {target_name} {packet_name}")

    @classmethod
    def connect_router(cls, router_name, *router_params, scope=OPENC3_SCOPE):
        if router_params and len(router_params) == 0:
            Topic.write_topic(
                f"{{{scope}__CMD}}ROUTER__{router_name}",
                {"connect": "True", "params": json.dumps(router_params)},
                "*",
                100,
            )
        else:
            Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"connect": "True"}, "*", 100)

    @classmethod
    def disconnect_router(cls, router_name, scope=OPENC3_SCOPE):
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"disconnect": "True"}, "*", 100)

    @classmethod
    def start_raw_logging(cls, router_name, scope=OPENC3_SCOPE):
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"log_stream": "True"}, "*", 100)

    @classmethod
    def stop_raw_logging(cls, router_name, scope=OPENC3_SCOPE):
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"log_stream": "False"}, "*", 100)

    @classmethod
    def shutdown(cls, router, scope=OPENC3_SCOPE):
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router.name}", {"shutdown": "True"}, "*", 100)

    @classmethod
    def router_cmd(cls, router_name, cmd_name, *cmd_params, scope=OPENC3_SCOPE):
        data = {}
        data["cmd_name"] = cmd_name
        data["cmd_params"] = cmd_params
        Topic.write_topic(
            f"{{{scope}__CMD}}ROUTER__{router_name}",
            {"router_cmd": json.dumps(data)},
            "*",
            100,
        )

    @classmethod
    def protocol_cmd(
        cls,
        router_name,
        cmd_name,
        *cmd_params,
        read_write="READ_WRITE",
        index=-1,
        scope=OPENC3_SCOPE,
    ):
        data = {}
        data["cmd_name"] = cmd_name
        data["cmd_params"] = cmd_params
        data["read_write"] = str(read_write).upper()
        data["index"] = index
        Topic.write_topic(
            f"{{{scope}__CMD}}ROUTER__{router_name}",
            {"protocol_cmd": json.dumps(data)},
            "*",
            100,
        )
