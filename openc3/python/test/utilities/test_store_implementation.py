# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import unittest
from unittest.mock import patch

from valkey.backoff import EqualJitterBackoff
from valkey.exceptions import BusyLoadingError, ConnectionError, TimeoutError
from valkey.retry import Retry

from openc3.utilities.store_implementation import EphemeralStore, Store
from test.test_helper import mock_redis, set_target_db_shard


class TestStoreImplementation(unittest.TestCase):
    def test_help(self):
        help(Store)

    def test_build_redis_configures_resilience(self):
        # A transient network blip (the same kind that makes targets reconnect)
        # must be retried inside the client with jittered backoff instead of
        # immediately surfacing a connection error to callers, which would
        # otherwise propagate up and kill the caller.
        with patch("valkey.Valkey") as valkey_new:
            # __new__ bypasses __init__ so we can exercise build_redis in
            # isolation without spinning up the connection pool / singleton.
            store = Store.__new__(Store)
            store.redis_host = "localhost"
            store.redis_port = 6379
            store.build_redis()

        self.assertEqual(valkey_new.call_count, 1)
        _, kwargs = valkey_new.call_args
        # Client retries with equal-jitter backoff on connection/timeout errors
        retry = kwargs["retry"]
        self.assertIsInstance(retry, Retry)
        self.assertEqual(retry._retries, 3)
        self.assertIsInstance(retry._backoff, EqualJitterBackoff)
        self.assertIn(BusyLoadingError, kwargs["retry_on_error"])
        self.assertIn(ConnectionError, kwargs["retry_on_error"])
        self.assertIn(TimeoutError, kwargs["retry_on_error"])
        # Per-retry backoff is bounded so a single retry can't hang forever;
        # the final (3rd) retry tops out at the 5s cap (jittered, so 2.5-5s).
        self.assertEqual(retry._backoff._cap, 5)
        self.assertLessEqual(retry._backoff.compute(3), 5)


class TestMockRedisShards(unittest.TestCase):
    # Each shard must get its own fake so tests can catch a read against the
    # wrong shard instead of silently finding the data in a shared fake
    def test_isolates_each_db_shard(self):
        redis = mock_redis(self)
        Store.instance(db_shard=1).set("key", "shard1")
        self.assertEqual(Store.instance(db_shard=1).get("key"), b"shard1")
        self.assertEqual(EphemeralStore.instance(db_shard=1).get("key"), b"shard1")
        self.assertIsNone(Store.instance(db_shard=0).get("key"))
        self.assertIsNone(Store.instance(db_shard=2).get("key"))
        self.assertIsNone(redis.get("key"))

        Store.set("key", "shard0")
        self.assertEqual(redis.get("key"), b"shard0")
        self.assertEqual(Store.instance(db_shard=1).get("key"), b"shard1")


class TestDbShardForTarget(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_reads_the_db_shard_from_the_target_json(self):
        set_target_db_shard("INST", 1)
        set_target_db_shard("INST2", 0)
        self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 1)
        self.assertEqual(Store.db_shard_for_target("INST2", scope="DEFAULT"), 0)
        # The same target name in another scope is a different target
        self.assertEqual(Store.db_shard_for_target("INST", scope="OTHER"), 0)

    def test_returns_0_for_an_unknown_or_missing_target(self):
        self.assertEqual(Store.db_shard_for_target("NOPE", scope="DEFAULT"), 0)
        self.assertEqual(Store.db_shard_for_target(None, scope="DEFAULT"), 0)

    def test_caches_the_lookup(self):
        set_target_db_shard("INST", 1)
        self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 1)
        # Moving the target isn't seen until the cache times out
        Store.instance(db_shard=0).hset("DEFAULT__openc3_targets", "INST", '{"name": "INST", "db_shard": 2}')
        self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 1)
        with patch("time.time", return_value=Store._db_shard_cache["DEFAULT__INST"][1] + Store.DB_SHARD_CACHE_TIMEOUT):
            self.assertEqual(Store.db_shard_for_target("INST", scope="DEFAULT"), 2)


class TestStoreReadTopics(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        patcher = patch.object(Store, "READ_TOPICS_DEFAULT_COUNT", 2)
        patcher.start()
        self.addCleanup(patcher.stop)
        for i in range(5):
            EphemeralStore.write_topic("TEST__TOPIC", {"i": str(i)})

    def test_caps_read_when_no_count_given(self):
        ids = [msg_id for _, msg_id, _, _ in EphemeralStore.read_topics(["TEST__TOPIC"], ["0-0"])]
        self.assertEqual(len(ids), 2)
        # Continuing from the last offset picks up where the capped read stopped
        ids += [msg_id for _, msg_id, _, _ in EphemeralStore.read_topics(["TEST__TOPIC"], [ids[-1]])]
        self.assertEqual(len(ids), 4)
        self.assertEqual(len(set(ids)), 4)

    def test_honors_explicit_count(self):
        ids = [msg_id for _, msg_id, _, _ in EphemeralStore.read_topics(["TEST__TOPIC"], ["0-0"], None, 4)]
        self.assertEqual(len(ids), 4)
