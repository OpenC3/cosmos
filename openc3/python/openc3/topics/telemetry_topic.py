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


class TelemetryTopic(Topic):
    @classmethod
    def write_packet(cls, packet, scope):
        msg_hash = {
            "time": packet.packet_time.to_nsec_from_epoch,
            "received_time": packet.received_time.to_nsec_from_epoch,
            "stored": str(packet.stored),
            "target_name": packet.target_name,
            "packet_name": packet.packet_name,
            "received_count": packet.received_count,
            "buffer": packet.buffer(False),
        }
        if packet.extra:
            msg_hash["extra"] = json.dumps(packet.extra.as_json())
        Topic.write_topic(
            f"{scope}__TELEMETRY__{{{packet.target_name}}}__{packet.packet_name}",
            msg_hash,
        )
