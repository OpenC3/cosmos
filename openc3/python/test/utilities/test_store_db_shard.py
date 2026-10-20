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

from openc3.utilities.store import EphemeralStore, Store
from openc3.utilities.store_queued import EphemeralStoreQueued, StoreQueued
from test.test_helper import mock_redis_db_shards, set_target_db_shard


class TestStoreDbShardInstance(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)

    def test_connects_each_db_shard_to_its_own_shardnum_host(self):
        self.assertEqual(Store.instance(db_shard=0).redis_host, "redis-0")
        self.assertEqual(Store.instance(db_shard=2).redis_host, "redis-2")
        self.assertEqual(EphemeralStore.instance(db_shard=2).redis_host, "redis-ephemeral-2")

    def test_keeps_a_singleton_per_db_shard(self):
        self.assertIs(Store.instance(db_shard=1), Store.instance(db_shard=1))
        self.assertIsNot(Store.instance(db_shard=1), Store.instance(db_shard=0))
        self.assertIsNot(EphemeralStore.instance(db_shard=1), Store.instance(db_shard=1))

    def test_delegates_class_methods_to_db_shard_0(self):
        Store.set("KEY", "zero")
        self.assertEqual(Store.instance(db_shard=0).get("KEY"), b"zero")
        self.assertIsNone(Store.instance(db_shard=1).get("KEY"))


class TestStoreDbShardForTarget(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)

    def test_returns_0_for_a_none_unknown_or_unsharded_target(self):
        Store.hset("DEFAULT__openc3_targets", "PLAIN", json.dumps({"name": "PLAIN"}))
        self.assertEqual(Store.db_shard_for_target(None, scope="DEFAULT"), 0)
        self.assertEqual(Store.db_shard_for_target("UNKNOWN", scope="DEFAULT"), 0)
        self.assertEqual(Store.db_shard_for_target("PLAIN", scope="DEFAULT"), 0)

    def test_reads_the_target_from_db_shard_0_in_the_given_scope(self):
        set_target_db_shard("INST", 2)
        set_target_db_shard("INST", 3, scope="OTHER")
        # A target hash on another db_shard is ignored
        Store.instance(db_shard=2).hset("DEFAULT__openc3_targets", "INST", json.dumps({"db_shard": 5}))
        self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 2)
        self.assertEqual(Store.db_shard_for_target("INST", scope="OTHER"), 3)

    def test_returns_0_when_the_lookup_fails(self):
        Store.hset("DEFAULT__openc3_targets", "BAD", "not json")
        self.assertEqual(Store.db_shard_for_target("BAD", scope="DEFAULT"), 0)

    def test_caches_the_db_shard_for_60_seconds(self):
        set_target_db_shard("INST", 1)
        with patch("time.time", return_value=1000.0):
            self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 1)
        Store.hset("DEFAULT__openc3_targets", "INST", json.dumps({"db_shard": 2}))
        with patch("time.time", return_value=1059.0):
            self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 1)
        with patch("time.time", return_value=1061.0):
            self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 2)


class TestStoreQueuedDbShard(unittest.TestCase):
    def setUp(self):
        mock_redis_db_shards(self)

    def test_keeps_a_singleton_per_db_shard_which_writes_to_that_db_shard(self):
        self.assertIs(StoreQueued.instance(db_shard=1), StoreQueued.instance(db_shard=1))
        self.assertIsNot(StoreQueued.instance(db_shard=1), StoreQueued.instance(db_shard=0))

        StoreQueued.instance(db_shard=1).hset("HASH", "KEY", "one")
        self.assertEqual(Store.instance(db_shard=1).hget("HASH", "KEY"), b"one")
        self.assertIsNone(Store.instance(db_shard=0).hget("HASH", "KEY"))

        EphemeralStoreQueued.instance(db_shard=1).hset("HASH", "KEY", "eph")
        self.assertEqual(EphemeralStore.instance(db_shard=1).hget("HASH", "KEY"), b"eph")
        self.assertEqual(Store.instance(db_shard=1).hget("HASH", "KEY"), b"one")

    def test_processes_queued_writes_on_its_db_shard(self):
        queued = StoreQueued.instance(db_shard=1)
        queued.store_queue.put(("hset", ("HASH", "KEY", "queued"), {}))
        queued.process_queue()
        self.assertEqual(Store.instance(db_shard=1).hget("HASH", "KEY"), b"queued")
        self.assertIsNone(Store.instance(db_shard=0).hget("HASH", "KEY"))
