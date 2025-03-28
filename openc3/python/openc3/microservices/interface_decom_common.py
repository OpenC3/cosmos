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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1963

from datetime import datetime, timezone
import json
from openc3.system.system import System
from openc3.topics.topic import Topic
from openc3.topics.telemetry_topic import TelemetryTopic
from openc3.utilities.time import to_nsec_from_epoch
from openc3.utilities.json import JsonEncoder, JsonDecoder
from openc3.models.target_model import TargetModel

def handle_inject_tlm(inject_tlm_json, scope):
    inject_tlm_hash = json.loads(inject_tlm_json, cls=JsonDecoder)
    target_name = inject_tlm_hash["target_name"]
    packet_name = inject_tlm_hash["packet_name"]
    item_hash = inject_tlm_hash["item_hash"]
    type = str(inject_tlm_hash["type"])
    packet = System.telemetry.packet(target_name, packet_name)
    if item_hash:
        for name, value in item_hash.items():
            packet.write(str(name), value, type)
    packet.received_time = datetime.now(timezone.utc)
    packet.received_count = TargetModel.increment_telemetry_count(packet.target_name, packet.packet_name, 1, scope=scope)
    TelemetryTopic.write_packet(packet, scope)


def handle_build_cmd(build_cmd_json, msg_id, scope):
    build_cmd_hash = json.loads(build_cmd_json, cls=JsonDecoder)
    target_name = build_cmd_hash["target_name"]
    cmd_name = build_cmd_hash["cmd_name"]
    cmd_params = build_cmd_hash["cmd_params"]
    range_check = build_cmd_hash["range_check"]
    raw = build_cmd_hash["raw"]
    ack_topic = f"{{{scope}__ACKCMD}}TARGET__{target_name}"
    try:
        command = System.commands.build_cmd(target_name, cmd_name, cmd_params, range_check, raw)
        msg_hash = {
            "id": msg_id,
            "result": "SUCCESS",
            "time": to_nsec_from_epoch(command.packet_time),
            "received_time": to_nsec_from_epoch(command.received_time),
            "target_name": command.target_name,
            "packet_name": command.packet_name,
            "received_count": command.received_count,
            "buffer": json.dumps(command.buffer_no_copy(), cls=JsonEncoder),
        }
    # If there is an error due to parameter out of range, etc, we rescue it so we can
    # write the ACKCMD}TARGET topic and allow the TelemetryDecomTopic.build_cmd to return
    except RuntimeError as error:
        msg_hash = {"id": msg_id, "result": "ERROR", "message": repr(error)}
    Topic.write_topic(ack_topic, msg_hash)
