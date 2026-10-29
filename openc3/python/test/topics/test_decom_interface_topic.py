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

from openc3.topics.decom_interface_topic import DecomInterfaceTopic
from test.test_helper import ack_next_message, mock_redis, set_target_db_shard, shard_redis


# The decom microservice for a target reads its DECOMINTERFACE topic from the
# target db_shard and acks on that db_shard
class TestDecomInterfaceTopicMultipleDbShards(unittest.TestCase):
    TOPIC = "DEFAULT__DECOMINTERFACE__{INST}"
    ACK_TOPIC = "{DEFAULT__ACKCMD}TARGET__INST"

    def setUp(self):
        mock_redis(self)
        # INST is installed on db_shard 1
        set_target_db_shard("INST", 1)
        self.shard0 = shard_redis(0)
        self.shard1 = shard_redis(1)

    def test_build_cmd_uses_the_target_db_shard(self):
        responder = ack_next_message(
            self.shard1, self.TOPIC, self.ACK_TOPIC, fields={"buffer": json.dumps({"raw": [1, 2]})}
        )
        result = DecomInterfaceTopic.build_cmd("INST", "ABORT", {}, True, False, timeout=2, scope="DEFAULT")
        responder.join()
        self.assertEqual(result["result"], "SUCCESS")
        self.assertFalse(self.shard0.exists(self.TOPIC))

    def test_get_tlm_buffer_uses_the_target_db_shard(self):
        responder = ack_next_message(
            self.shard1,
            self.TOPIC,
            self.ACK_TOPIC,
            fields={"buffer": json.dumps({"raw": [1, 2]}), "stored": "false"},
        )
        result = DecomInterfaceTopic.get_tlm_buffer("INST", "HEALTH_STATUS", timeout=2, scope="DEFAULT")
        responder.join()
        self.assertEqual(result["result"], "SUCCESS")
        self.assertFalse(self.shard0.exists(self.TOPIC))

    def test_inject_tlm_uses_the_target_db_shard(self):
        responder = ack_next_message(self.shard1, self.TOPIC, self.ACK_TOPIC)
        DecomInterfaceTopic.inject_tlm("INST", "HEALTH_STATUS", {"TEMP1": 1}, timeout=2, scope="DEFAULT")
        responder.join()
        self.assertFalse(self.shard0.exists(self.TOPIC))
