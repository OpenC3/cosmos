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
from unittest.mock import patch

from openc3.utilities.questdb_client import QuestDBClient
from openc3.utilities.store import Store
from test.test_helper import mock_redis_db_shards, set_target_db_shard


class TestQuestDBClientHostnameForDbShard(unittest.TestCase):
    def setUp(self):
        env = patch.dict("os.environ", {"OPENC3_TSDB_HOSTNAME": "tsdb-SHARDNUM"})
        env.start()
        self.addCleanup(env.stop)

    def test_replaces_shardnum_with_the_db_shard(self):
        self.assertEqual(QuestDBClient.hostname_for_db_shard(0), "tsdb-0")
        self.assertEqual(QuestDBClient.hostname_for_db_shard(2), "tsdb-2")

    def test_uses_the_same_host_for_every_db_shard_without_shardnum(self):
        with patch.dict("os.environ", {"OPENC3_TSDB_HOSTNAME": "tsdb"}):
            self.assertEqual(QuestDBClient.hostname_for_db_shard(0), "tsdb")
            self.assertEqual(QuestDBClient.hostname_for_db_shard(2), "tsdb")


class TestQuestDBClientDbShardForTarget(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)

    def test_returns_0_for_no_target(self):
        self.assertEqual(QuestDBClient.db_shard_for_target(None), 0)

    def test_returns_the_db_shard_of_the_target_in_the_given_scope(self):
        set_target_db_shard("INST", 1)
        set_target_db_shard("INST", 3, scope="OTHER")
        self.assertEqual(QuestDBClient.db_shard_for_target("INST"), 1)
        self.assertEqual(QuestDBClient.db_shard_for_target("INST", scope="OTHER"), 3)

    def test_returns_0_for_a_target_which_doesnt_exist_or_cant_be_looked_up(self):
        self.assertEqual(QuestDBClient.db_shard_for_target("MISSING"), 0)
        with patch.object(Store.instance(db_shard=0), "hget", side_effect=RuntimeError("down")):
            self.assertEqual(QuestDBClient.db_shard_for_target("BROKEN"), 0)

    def test_caches_the_db_shard_for_a_minute(self):
        set_target_db_shard("INST", 1)
        with patch("time.time", return_value=1000.0):
            self.assertEqual(QuestDBClient.db_shard_for_target("INST"), 1)
        # Move the target without clearing the cache
        Store.instance(db_shard=0).hset("DEFAULT__openc3_targets", "INST", json.dumps({"db_shard": 2}))
        with patch("time.time", return_value=1059.0):
            self.assertEqual(QuestDBClient.db_shard_for_target("INST"), 1)
        with patch("time.time", return_value=1061.0):
            self.assertEqual(QuestDBClient.db_shard_for_target("INST"), 2)
