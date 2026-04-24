# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import time

from openc3.environment import OPENC3_SCOPE
from openc3.system.system import System
from openc3.topics.topic import Topic
from openc3.utilities.json import JsonDecoder
from openc3.utilities.store import Store


class RouterTopic(Topic):
    COMMAND_ACK_TIMEOUT_S = 30

    @classmethod
    def _db_shard_for_router(cls, router_name, scope):
        """Look up db_shard from RouterModel"""
        json_data = Store.hget(f"{scope}__openc3_routers", router_name)
        return int(json.loads(json_data).get("db_shard", 0) or 0) if json_data else 0

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
    def receive_telemetry(cls, router, scope=OPENC3_SCOPE, db_shard=0):
        db_shard = int(db_shard or 0)
        router_cmd_topic = f"{{{scope}__CMD}}ROUTER__{router.name}"

        target_topics = []
        for target_name in router.tlm_target_names:
            for _, packet in System.telemetry.packets(target_name).items():
                target_topics.append(f"{scope}__TELEMETRY__{{{packet.target_name}}}__{packet.packet_name}")

        # Group telemetry topics by db_shard; include router cmd topic on db_shard
        db_shard_groups = Topic.group_topics_by_db_shard(target_topics, "__TELEMETRY__", scope)
        if db_shard not in db_shard_groups:
            db_shard_groups[db_shard] = []
        db_shard_groups[db_shard].append(router_cmd_topic)

        all_same_db_shard = Topic.all_same_db_shard(db_shard_groups)

        while True:
            if all_same_db_shard:
                # Fast path: everything on one db_shard, single read
                db_shard = next(iter(db_shard_groups), 0)
                for topic, msg_id, msg_hash, redis in Topic.read_topics(db_shard_groups[db_shard], db_shard=db_shard):
                    result = yield topic, msg_id, msg_hash, redis
                    if result is not None and "CMD}ROUTER" in topic:
                        Topic.write_ack(topic, result, msg_id, db_shard=db_shard)
            else:
                timeout_per_db_shard = max(1000 // max(len(db_shard_groups), 1), 100)
                for db_shard, topics in db_shard_groups.items():
                    for topic, msg_id, msg_hash, redis in Topic.read_topics(
                        topics, timeout_ms=timeout_per_db_shard, db_shard=db_shard
                    ):
                        result = yield topic, msg_id, msg_hash, redis
                        if result is not None and "CMD}ROUTER" in topic:
                            Topic.write_ack(topic, result, msg_id, db_shard=db_shard)

    @classmethod
    def route_command(cls, packet, target_names, scope=OPENC3_SCOPE):
        if packet.identified():
            topic = f"{{{scope}__CMD}}TARGET__{packet.target_name}"
            Topic.write_topic(
                topic,
                {
                    "target_name": packet.target_name,
                    "cmd_name": packet.packet_name,
                    "cmd_buffer": bytes(packet.buffer_no_copy()),
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
                    "cmd_buffer": bytes(packet.buffer_no_copy()),
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
        db_shard = cls._db_shard_for_router(router_name, scope)
        if router_params and len(router_params) == 0:
            Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"connect": "True", "params": json.dumps(router_params)}, "*", 100, db_shard=db_shard)
        else:
            Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"connect": "True"}, "*", 100, db_shard=db_shard)

    @classmethod
    def disconnect_router(cls, router_name, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router_name, scope)
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"disconnect": "True"}, "*", 100, db_shard=db_shard)

    @classmethod
    def start_raw_logging(cls, router_name, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router_name, scope)
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"log_stream": "True"}, "*", 100, db_shard=db_shard)

    @classmethod
    def stop_raw_logging(cls, router_name, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router_name, scope)
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"log_stream": "False"}, "*", 100, db_shard=db_shard)

    @classmethod
    def shutdown(cls, router, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router.name, scope)
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router.name}", {"shutdown": "True"}, "*", 100, db_shard=db_shard)

    @classmethod
    def router_cmd(cls, router_name, cmd_name, *cmd_params, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router_name, scope)
        data = {"cmd_name": cmd_name, "cmd_params": cmd_params}
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"router_cmd": json.dumps(data)}, "*", 100, db_shard=db_shard)

    @classmethod
    def protocol_cmd(cls, router_name, cmd_name, *cmd_params, read_write="READ_WRITE", index=-1, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router_name, scope)
        data = {"cmd_name": cmd_name, "cmd_params": cmd_params, "read_write": str(read_write).upper(), "index": index}
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"protocol_cmd": json.dumps(data)}, "*", 100, db_shard=db_shard)

    @classmethod
    def router_target_enable(cls, router_name, target_name, cmd_only=False, tlm_only=False, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router_name, scope)
        data = {"target_name": target_name.upper(), "cmd_only": cmd_only, "tlm_only": tlm_only, "action": "enable"}
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"target_control": json.dumps(data)}, "*", 100, db_shard=db_shard)

    @classmethod
    def router_target_disable(cls, router_name, target_name, cmd_only=False, tlm_only=False, scope=OPENC3_SCOPE):
        db_shard = cls._db_shard_for_router(router_name, scope)
        data = {"target_name": target_name.upper(), "cmd_only": cmd_only, "tlm_only": tlm_only, "action": "disable"}
        Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"target_control": json.dumps(data)}, "*", 100, db_shard=db_shard)

    @classmethod
    def router_details(cls, router_name, scope=OPENC3_SCOPE, timeout=None):
        router_name = router_name.upper()
        db_shard = cls._db_shard_for_router(router_name, scope)

        if timeout is None:
            timeout = cls.COMMAND_ACK_TIMEOUT_S
        ack_topic = f"{{{scope}__ACKCMD}}ROUTER__{router_name}"
        Topic.update_topic_offsets([ack_topic], db_shard=db_shard)

        cmd_id = Topic.write_topic(f"{{{scope}__CMD}}ROUTER__{router_name}", {"router_details": "true"}, "*", 100, db_shard=db_shard)
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            for _, _, msg_hash, _ in Topic.read_topics([ack_topic], db_shard=db_shard):
                if msg_hash[b"id"] == cmd_id:
                    return json.loads(msg_hash[b"result"].decode(), cls=JsonDecoder)
        raise RuntimeError(f"Timeout of {timeout}s waiting for cmd ack")
