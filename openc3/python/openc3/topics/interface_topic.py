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
from openc3.topics.topic import Topic
from openc3.utilities.json import JsonDecoder
from openc3.utilities.store import Store


class InterfaceTopic(Topic):
    COMMAND_ACK_TIMEOUT_S = 30
    while_receive_commands = False

    @classmethod
    def _shard_for_interface(cls, interface_name, scope):
        """Look up db_shard from InterfaceModel stored on shard 0."""
        json_data = Store.hget(f"{scope}__openc3_interfaces", interface_name)
        return int(json.loads(json_data).get("db_shard", 0) or 0) if json_data else 0

    # Generate a list of topics for this interface. This includes the interface itself
    # and all the targets which are assigned to this interface.
    @classmethod
    def topics(cls, interface, scope=OPENC3_SCOPE):
        topics = []
        topics.append(f"{{{scope}__CMD}}INTERFACE__{interface.name}")
        for target_name in interface.cmd_target_names:
            topics.append(f"{{{scope}__CMD}}TARGET__{target_name}")
        topics.append("OPENC3__SYSTEM__EVENTS")  # Add System Events
        return topics

    @classmethod
    def receive_commands(cls, method, interface, scope=OPENC3_SCOPE, db_shard=0):
        db_shard = int(db_shard or 0)
        interface_cmd_topic = f"{{{scope}__CMD}}INTERFACE__{interface.name}"
        system_events_topic = "OPENC3__SYSTEM__EVENTS"

        target_topics = []
        for target_name in interface.cmd_target_names:
            target_topics.append(f"{{{scope}__CMD}}TARGET__{target_name}")

        # Group target command topics by shard; include interface cmd and system events on db_shard
        shard_groups = Topic.group_topics_by_shard(target_topics, "CMD}TARGET__", scope)
        if db_shard not in shard_groups:
            shard_groups[db_shard] = []
        shard_groups[db_shard].append(interface_cmd_topic)
        shard_groups[db_shard].append(system_events_topic)

        all_same_shard = Topic.all_same_shard(shard_groups)

        InterfaceTopic.while_receive_commands = True
        while InterfaceTopic.while_receive_commands:
            if all_same_shard:
                # Fast path: everything on one shard, single read
                shard = next(iter(shard_groups), 0)
                for topic, msg_id, msg_hash, redis in Topic.read_topics(shard_groups[shard], shard=shard):
                    result = method(topic, msg_id, msg_hash, redis)
                    if result is not None:
                        Topic.write_ack(topic, result, msg_id, shard=shard)
            else:
                timeout_per_shard = max(1000 // max(len(shard_groups), 1), 100)
                for shard, topics in shard_groups.items():
                    for topic, msg_id, msg_hash, redis in Topic.read_topics(
                        topics, timeout_ms=timeout_per_shard, shard=shard
                    ):
                        result = method(topic, msg_id, msg_hash, redis)
                        if result is not None:
                            Topic.write_ack(topic, result, msg_id, shard=shard)

    @classmethod
    def write_raw(cls, interface_name, data, scope, timeout=None):
        interface_name = interface_name.upper()
        shard = cls._shard_for_interface(interface_name, scope)

        if timeout is None:
            timeout = cls.COMMAND_ACK_TIMEOUT_S
        ack_topic = f"{{{scope}__ACKCMD}}INTERFACE__{interface_name}"
        Topic.update_topic_offsets([ack_topic], shard=shard)

        cmd_id = Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"raw": data}, "*", 100, shard=shard)
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            for _, _, msg_hash, _ in Topic.read_topics([ack_topic], shard=shard):
                if msg_hash[b"id"] == cmd_id:
                    result = msg_hash[b"result"].decode()
                    if result == "SUCCESS":
                        return
                    else:
                        raise RuntimeError(result)
        raise RuntimeError(f"Timeout of {timeout}s waiting for cmd ack")

    @classmethod
    def connect_interface(cls, interface_name, *interface_params, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        if interface_params and len(interface_params) != 0:
            Topic.write_topic(
                f"{{{scope}__CMD}}INTERFACE__{interface_name}",
                {"connect": "true", "params": json.dumps(interface_params)},
                "*",
                100,
                shard=shard,
            )
        else:
            Topic.write_topic(
                f"{{{scope}__CMD}}INTERFACE__{interface_name}",
                {"connect": "true"},
                "*",
                100,
                shard=shard,
            )

    @classmethod
    def disconnect_interface(cls, interface_name, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"disconnect": "true"}, "*", 100, shard=shard)

    @classmethod
    def start_raw_logging(cls, interface_name, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"log_stream": "true"}, "*", 100, shard=shard)

    @classmethod
    def stop_raw_logging(cls, interface_name, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"log_stream": "false"}, "*", 100, shard=shard)

    @classmethod
    def shutdown(cls, interface, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface.name, scope)
        InterfaceTopic.while_receive_commands = False
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface.name}", {"shutdown": "true"}, "*", 100, shard=shard)

    @classmethod
    def interface_cmd(cls, interface_name, cmd_name, *cmd_params, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        data = {"cmd_name": cmd_name, "cmd_params": cmd_params}
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"interface_cmd": json.dumps(data)}, "*", 100, shard=shard)

    @classmethod
    def protocol_cmd(cls, interface_name, cmd_name, *cmd_params, read_write="READ_WRITE", index=-1, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        data = {"cmd_name": cmd_name, "cmd_params": cmd_params, "read_write": str(read_write).upper(), "index": index}
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"protocol_cmd": json.dumps(data)}, "*", 100, shard=shard)

    @classmethod
    def inject_tlm(cls, interface_name, target_name, packet_name, item_hash=None, type="CONVERTED", scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        data = {"target_name": target_name.upper(), "packet_name": packet_name.upper(), "item_hash": item_hash, "type": type}
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"inject_tlm": json.dumps(data)}, "*", 100, shard=shard)

    @classmethod
    def interface_target_enable(cls, interface_name, target_name, cmd_only=False, tlm_only=False, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        data = {"target_name": target_name.upper(), "cmd_only": cmd_only, "tlm_only": tlm_only, "action": "enable"}
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"target_control": json.dumps(data)}, "*", 100, shard=shard)

    @classmethod
    def interface_target_disable(cls, interface_name, target_name, cmd_only=False, tlm_only=False, scope=OPENC3_SCOPE):
        shard = cls._shard_for_interface(interface_name, scope)
        data = {"target_name": target_name.upper(), "cmd_only": cmd_only, "tlm_only": tlm_only, "action": "disable"}
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"target_control": json.dumps(data)}, "*", 100, shard=shard)

    @classmethod
    def interface_details(cls, interface_name, scope=OPENC3_SCOPE, timeout=None):
        interface_name = interface_name.upper()
        shard = cls._shard_for_interface(interface_name, scope)

        if timeout is None:
            timeout = cls.COMMAND_ACK_TIMEOUT_S
        ack_topic = f"{{{scope}__ACKCMD}}INTERFACE__{interface_name}"
        Topic.update_topic_offsets([ack_topic], shard=shard)

        cmd_id = Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"interface_details": "true"}, "*", 100, shard=shard)
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            for _, _, msg_hash, _ in Topic.read_topics([ack_topic], shard=shard):
                if msg_hash[b"id"] == cmd_id:
                    return json.loads(msg_hash[b"result"].decode(), cls=JsonDecoder)
        raise RuntimeError(f"Timeout of {timeout}s waiting for cmd ack")
