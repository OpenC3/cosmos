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

import re
from openc3.topics.topic import Topic
from openc3.system.system import System


class RouterTopic(Topic):
    # Generate a list of topics for this router. This includes the router itself
    # and all the targets which are assigned to this router.
    @classmethod
    def topics(cls, router, scope):
        topics = []
        topics.append(f"{{{scope}__CMD}}ROUTER__{router.name}")
        for target_name in router.tlm_target_names:
            for packet_name, packet in System.telemetry.packets(target_name):
                topics.append(
                    f"{scope}__TELEMETRY__{{{packet.target_name}}}__{packet.packet_name}"
                )
        return topics

    @classmethod
    def receive_telemetry(cls, router, scope):
        while True:
            for topic, msg_id, msg_hash, redis in Topic.read_topics(
                RouterTopic.topics(router, scope)
            ):
                result = yield topic, msg_id, msg_hash, redis
                if re.match(r"CMD}ROUTER", topic):
                    ack_topic = topic.split("__")
                    ack_topic[1] = "ACK" + ack_topic[1]
                    ack_topic = "__".join(ack_topic)
                    Topic.write_topic(ack_topic, {"result": result}, msg_id, 100)
