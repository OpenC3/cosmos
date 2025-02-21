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
from openc3.environment import OPENC3_SCOPE


class InterfaceTopic(Topic):
    while_receive_commands = False

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
    def receive_commands(cls, method, interface, scope=OPENC3_SCOPE):
        InterfaceTopic.while_receive_commands = True
        while InterfaceTopic.while_receive_commands:
            for topic, msg_id, msg_hash, redis in Topic.read_topics(InterfaceTopic.topics(interface, scope)):
                result = method(topic, msg_id, msg_hash, redis)
                ack_topic = topic.split("__")
                ack_topic[1] = "ACK" + ack_topic[1]
                ack_topic = "__".join(ack_topic)
                Topic.write_topic(ack_topic, {"result": result, "id": msg_id}, "*", 100)

    @classmethod
    def write_raw(cls, interface_name, data, scope):
        Topic.write_topic(f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"raw": data}, "*", 100)
        # TODO: This should wait for the ack

    @classmethod
    def connect_interface(cls, interface_name, *interface_params, scope=OPENC3_SCOPE):
        if interface_params and len(interface_params) != 0:
            Topic.write_topic(
                f"{{{scope}__CMD}}INTERFACE__{interface_name}",
                {"connect": "true", "params": json.dumps(interface_params)},
                "*",
                100,
            )
        else:
            Topic.write_topic(
                f"{{{scope}__CMD}}INTERFACE__{interface_name}",
                {"connect": "true"},
                "*",
                100,
            )

    @classmethod
    def disconnect_interface(cls, interface_name, scope=OPENC3_SCOPE):
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface_name}",
            {"disconnect": "true"},
            "*",
            100,
        )

    @classmethod
    def start_raw_logging(cls, interface_name, scope=OPENC3_SCOPE):
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface_name}",
            {"log_stream": "true"},
            "*",
            100,
        )

    @classmethod
    def stop_raw_logging(cls, interface_name, scope=OPENC3_SCOPE):
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface_name}",
            {"log_stream": "false"},
            "*",
            100,
        )

    @classmethod
    def shutdown(cls, interface, scope=OPENC3_SCOPE):
        InterfaceTopic.while_receive_commands = False
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface.name}",
            {"shutdown": "true"},
            "*",
            100,
        )

    @classmethod
    def interface_cmd(cls, interface_name, cmd_name, *cmd_params, scope=OPENC3_SCOPE):
        data = {}
        data["cmd_name"] = cmd_name
        data["cmd_params"] = cmd_params
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface_name}",
            {"interface_cmd": json.dumps(data)},
            "*",
            100,
        )

    @classmethod
    def protocol_cmd(
        cls,
        interface_name,
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
            f"{{{scope}__CMD}}INTERFACE__{interface_name}",
            {"protocol_cmd": json.dumps(data)},
            "*",
            100,
        )

    @classmethod
    def inject_tlm(
        cls,
        interface_name,
        target_name,
        packet_name,
        item_hash=None,
        type="CONVERTED",
        scope=OPENC3_SCOPE,
    ):
        data = {}
        data["target_name"] = target_name.upper()
        data["packet_name"] = packet_name.upper()
        data["item_hash"] = item_hash
        data["type"] = type
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface_name}",
            {"inject_tlm": json.dumps(data)},
            "*",
            100,
        )
