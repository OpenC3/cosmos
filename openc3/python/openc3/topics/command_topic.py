# Copyright 2024 OpenC3, Inc.
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

import time
import json
from openc3.topics.topic import Topic
from openc3.utilities.store_queued import EphemeralStoreQueued
from openc3.top_level import HazardousError, CriticalCmdError
from openc3.utilities.time import to_nsec_from_epoch
from openc3.utilities.json import JsonEncoder


class CommandTopic(Topic):
    COMMAND_ACK_TIMEOUT_S = 30

    @classmethod
    def write_packet(cls, packet, scope):
        topic = f"{scope}__COMMAND__{{{packet.target_name}}}__{packet.packet_name}"
        msg_hash = {
            "time": to_nsec_from_epoch(packet.packet_time),
            "received_time": to_nsec_from_epoch(packet.received_time),
            "target_name": packet.target_name,
            "packet_name": packet.packet_name,
            "received_count": packet.received_count,
            "stored": str(packet.stored),
            "buffer": bytes(packet.buffer_no_copy()),
        }
        EphemeralStoreQueued.write_topic(topic, msg_hash)

    @classmethod
    def send_command(cls, command, timeout, scope):
        if timeout is None:
            timeout = cls.COMMAND_ACK_TIMEOUT_S
        ack_topic = f"{{{scope}__ACKCMD}}TARGET__{command['target_name']}"
        Topic.update_topic_offsets([ack_topic])
        # Save the existing cmd_params Hash and JSON generate before writing to the topic
        cmd_params = command["cmd_params"]
        command["cmd_params"] = json.dumps(command["cmd_params"], cls=JsonEncoder)
        cmd_id = Topic.write_topic(
            f"{{{scope}__CMD}}TARGET__{command['target_name']}",
            command,
            "*",
            100,
        )
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            for _, _, msg_hash, _ in Topic.read_topics([ack_topic]):
                if msg_hash[b"id"] == cmd_id:
                    result = msg_hash[b"result"].decode()
                    if result == "SUCCESS":
                        return command["target_name"], command["cmd_name"], cmd_params
                    # Check for HazardousError which is a special case
                    elif "HazardousError" in result:
                        cls.raise_hazardous_error(
                            msg_hash,
                            command["target_name"],
                            command["cmd_name"],
                            cmd_params,
                        )
                    elif "CriticalCmdError" in result:
                        cls.raise_critical_cmd_error(
                            msg_hash,
                            command["username"],
                            command["target_name"],
                            command["cmd_name"],
                            cmd_params,
                            command["cmd_string"],
                        )
                    else:
                        raise RuntimeError(result)
        raise RuntimeError(f"Timeout of {timeout}s waiting for cmd ack")

    ###########################################################################
    # PRIVATE implementation details
    ###########################################################################

    @classmethod
    def raise_hazardous_error(cls, msg_hash, target_name, cmd_name, cmd_params):
        _, description, formatted = msg_hash[b"result"].decode().split("\n")
        # Create and populate a new HazardousError and raise it up
        # The _cmd method in script/commands.rb rescues this and calls prompt_for_hazardous
        error = HazardousError()
        error.target_name = target_name
        error.cmd_name = cmd_name
        error.cmd_params = cmd_params
        error.hazardous_description = description
        error.formatted = formatted

        # No Logger.info because the error is already logged by the Logger.info "Ack Received ...
        raise error

    @classmethod
    def raise_critical_cmd_error(cls, msg_hash, username, target_name, cmd_name, cmd_params, cmd_string):
        _, uuid = msg_hash[b"result"].decode().split("\n")
        # Create and populate a new CriticalCmdError and raise it up
        # The _cmd method in script/commands.rb rescues this and calls prompt_for_critical_cmd
        error = CriticalCmdError()
        error.uuid = uuid
        error.username = username
        error.target_name = target_name
        error.cmd_name = cmd_name
        error.cmd_params = cmd_params
        error.cmd_string = cmd_string

        # No Logger.info because the error is already logged by the Logger.info "Ack Received ...
        raise error
