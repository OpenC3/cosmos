# Copyright 2023 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
from openc3.topics.topic import Topic
from openc3.environment import OPENC3_SCOPE


class CommandDecomTopic(Topic):
    @classmethod
    def topics(cls, scope):
        Topic.topics(scope, "DECOMCMD")

    @classmethod
    def write_packet(cls, packet, scope):
        topic = f"{scope}__DECOMCMD__{{{packet.target_name}}}__{packet.packet_name}"
        msg_hash = {
            "time": packet.packet_time.to_nsec_from_epoch,
            "target_name": packet.target_name,
            "packet_name": packet.packet_name,
            "stored": str(packet.stored),
            "received_count": packet.received_count,
        }
        json_hash = {}
        for item in packet.sorted_items:
            json_hash[item.name] = packet.read_item(item, "RAW")
            if item.write_conversion or item.states:
                json_hash[item.name + "__C"] = packet.read_item(item, "CONVERTED")
            if item.format_string:
                json_hash[item.name + "__F"] = packet.read_item(item, "FORMATTED")
            if item.units:
                json_hash[item.name + "__U"] = packet.read_item(item, "WITH_UNITS")
        msg_hash["json_data"] = json.dumps(json_hash)
        Topic.write_topic(topic, msg_hash)

    @classmethod
    def get_cmd_item(
        cls, target_name, packet_name, param_name, type="WITH_UNITS", scope=OPENC3_SCOPE
    ):
        msg_id, msg_hash = Topic.get_newest_message(
            f"{scope}__DECOMCMD__{{{target_name}}}__{packet_name}"
        )
        if msg_id:
            # TODO: We now have these reserved items directly on command packets
            # Do we still calculate from msg_hash['time'] or use the times directly?
            #
            # if param_name == 'RECEIVED_TIMESECONDS' || param_name == 'PACKET_TIMESECONDS'
            #   Time.from_nsec_from_epoch(msg_hash['time'].to_i).to_f
            # elsif param_name == 'RECEIVED_TIMEFORMATTED' || param_name == 'PACKET_TIMEFORMATTED'
            #   Time.from_nsec_from_epoch(msg_hash['time'].to_i).formatted
            if param_name == "RECEIVED_COUNT":
                return int(msg_hash["received_count"])
            else:
                json = msg_hash["json_data"]
                hash = json.loads(json)
                # Start from the most complex down to the basic raw value
                value = hash[f"{param_name}__U"]
                if value and type == "WITH_UNITS":
                    return value

                value = hash[f"{param_name}__F"]
                if value and (type == "WITH_UNITS" or type == "FORMATTED"):
                    return value

                value = hash[f"{param_name}__C"]
                if value and (
                    type == "WITH_UNITS" or type == "FORMATTED" or type == "CONVERTED"
                ):
                    return value

                return hash[param_name]
