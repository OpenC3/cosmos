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
import unittest
from unittest.mock import MagicMock, patch

from openc3.microservices.interface_decom_common import (
    handle_build_cmd,
    handle_get_tlm_buffer,
    handle_inject_tlm_with_ack,
)
from openc3.packets.packet import Packet
from openc3.topics.topic import Topic
from test.test_helper import mock_redis_db_shards, set_target_db_shard


ACK_TOPIC = "{DEFAULT__ACKCMD}TARGET__INST2"


class TestInterfaceDecomCommonDbShard(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)
        # The ack must go to the db_shard of the target where DecomInterfaceTopic waits for it
        set_target_db_shard("INST2", 2)
        self.packet = Packet("INST2", "HEALTH_STATUS")
        self.packet.buffer = b"\x00"
        system = MagicMock()
        system.telemetry.packet.return_value = self.packet
        system.commands.build_cmd.return_value = self.packet
        patcher = patch("openc3.microservices.interface_decom_common.System", system)
        patcher.start()
        self.addCleanup(patcher.stop)

    def ack(self, db_shard):
        _, msg = Topic.get_newest_message(ACK_TOPIC, db_shard=db_shard)
        return msg

    def test_acks_inject_tlm_on_the_db_shard_of_the_target(self):
        inject = json.dumps({"target_name": "INST2", "packet_name": "HEALTH_STATUS", "item_hash": None, "type": "RAW"})
        handle_inject_tlm_with_ack(inject, "1-0", "DEFAULT")
        self.assertEqual(self.ack(2), {b"id": b"1-0", b"result": b"SUCCESS"})
        self.assertIsNone(self.ack(0))

    def test_acks_a_failed_inject_tlm_on_the_db_shard_of_the_target(self):
        inject = json.dumps({"target_name": "INST2", "packet_name": "HEALTH_STATUS", "item_hash": None, "type": "RAW"})
        with patch(
            "openc3.microservices.interface_decom_common.TelemetryTopic.write_packet",
            side_effect=RuntimeError("bad packet"),
        ):
            handle_inject_tlm_with_ack(inject, "1-0", "DEFAULT")
        self.assertEqual(self.ack(2), {b"id": b"1-0", b"result": b"bad packet"})
        self.assertIsNone(self.ack(0))

    def test_acks_build_cmd_on_the_db_shard_of_the_target(self):
        build = json.dumps(
            {"target_name": "INST2", "cmd_name": "ABORT", "cmd_params": {}, "range_check": True, "raw": False}
        )
        handle_build_cmd(build, "2-0", "DEFAULT")
        self.assertEqual(self.ack(2)[b"result"], b"SUCCESS")
        self.assertIsNone(self.ack(0))

    def test_acks_get_tlm_buffer_on_the_db_shard_of_the_target(self):
        handle_get_tlm_buffer(json.dumps({"target_name": "INST2", "packet_name": "HEALTH_STATUS"}), "3-0", "DEFAULT")
        self.assertEqual(self.ack(2)[b"result"], b"SUCCESS")
        self.assertIsNone(self.ack(0))
