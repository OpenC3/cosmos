# Copyright 2025 OpenC3, Inc.
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
import time
from openc3.topics.topic import Topic
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.json import JsonEncoder, JsonDecoder


class DecomInterfaceTopic(Topic):
    @classmethod
    def build_cmd(cls, target_name, cmd_name, cmd_params, range_check, raw, timeout=5, scope=OPENC3_SCOPE):
        data = {}
        data["target_name"] = target_name.upper()
        data["cmd_name"] = cmd_name.upper()
        data["cmd_params"] = cmd_params
        data["range_check"] = range_check
        data["raw"] = raw
        # DecomMicroservice is listening to the DECOMINTERFACE topic and is responsible
        # for actually building the command. This was deliberate to allow this to work
        # with or without an interface.
        ack_topic = f"{{{scope}__ACKCMD}}TARGET__{target_name}"
        Topic.update_topic_offsets([ack_topic])
        decom_id = Topic.write_topic(
            f"{scope}__DECOMINTERFACE__{{{target_name}}}",
            {"build_cmd": json.dumps(data, cls=JsonEncoder)},
            "*",
            100,
        )
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            for _topic, _msg_id, msg_hash, _redis in Topic.read_topics([ack_topic]):
                if msg_hash[b"id"] == decom_id:
                    if msg_hash[b"result"] == b"SUCCESS":
                        msg_hash = {k.decode(): v.decode() for (k, v) in msg_hash.items()}
                        msg_hash["buffer"] = json.loads(msg_hash["buffer"], cls=JsonDecoder)
                        return msg_hash
                    else:
                        raise RuntimeError(msg_hash[b"message"])
        raise RuntimeError(f"Timeout of {timeout}s waiting for cmd ack. Does target '{target_name}' exist?")

    @classmethod
    def inject_tlm(
        cls,
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
            f"{scope}__DECOMINTERFACE__{{{target_name}}}",
            {"inject_tlm": json.dumps(data)},
            "*",
            100,
        )
