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

import time
import json
from openc3.topics.topic import Topic
from openc3.environment import OPENC3_SCOPE


class InterfaceTopic(Topic):
    while_receive_commands = False

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

    @classmethod
    def write_raw(cls, interface_name, data, scope):
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface_name}", {"raw": data}, "*", 100
        )

    @classmethod
    def receive_commands(cls, method, interface, scope):
        InterfaceTopic.while_receive_commands = True
        while InterfaceTopic.while_receive_commands:
            for topic, msg_id, msg_hash, redis in Topic.read_topics(
                InterfaceTopic.topics(interface, scope)
            ):
                result = method(topic, msg_id, msg_hash, redis)
                ack_topic = topic.split("__")
                ack_topic[1] = "ACK" + ack_topic[1]
                ack_topic = ack_topic.join("__")
                Topic.write_topic(ack_topic, {"result": result, "id": msg_id}, "*", 100)

    @classmethod
    def shutdown(cls, interface, scope):
        InterfaceTopic.while_receive_commands = False
        Topic.write_topic(
            f"{{{scope}__CMD}}INTERFACE__{interface.name}",
            {"shutdown": "true"},
            "*",
            100,
        )
        time.sleep(1)  # Give some time for the interface to shutdown
        InterfaceTopic.clear_topics(InterfaceTopic.topics(interface, scope=scope))
