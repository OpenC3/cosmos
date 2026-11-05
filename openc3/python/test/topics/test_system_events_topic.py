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

import unittest

from openc3.topics.system_events_topic import SystemEventsTopic
from test.test_helper import mock_redis, set_target_db_shard, shard_redis


class TestSystemEventsTopicMultipleDbShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        # INST is installed on db_shard 1 and OTHER_INST on db_shard 2 in another scope
        set_target_db_shard("INST", 1)
        set_target_db_shard("INST2", 0)
        set_target_db_shard("OTHER_INST", 2, scope="OTHER")

    def test_writes_events_to_every_target_db_shard_in_every_scope(self):
        # Each interface microservice reads system events inline from its own db_shard
        SystemEventsTopic.write("setting", {"name": "test"})
        for db_shard in [0, 1, 2]:
            self.assertEqual(shard_redis(db_shard).xlen(SystemEventsTopic.PRIMARY_KEY), 1, db_shard)
        self.assertFalse(shard_redis(3).exists(SystemEventsTopic.PRIMARY_KEY))
