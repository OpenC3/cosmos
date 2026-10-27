# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import importlib.util
import queue
import threading
import unittest
from unittest.mock import MagicMock

from openc3.utilities.store_queued import EphemeralStoreQueued, StoreQueued
from test.test_helper import mock_redis


def load_real_store_queued():
    # test_helper monkeypatches StoreQueued to write straight through, so load
    # a private copy of the module to exercise the real queueing behavior
    spec = importlib.util.find_spec("openc3.utilities.store_queued")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.StoreQueued


class TestStoreQueued(unittest.TestCase):
    def setUp(self):
        store_queued_class = load_real_store_queued()
        # Bypass __init__ so no update thread or atexit hook is started
        self.store_queued = store_queued_class.__new__(store_queued_class)
        self.store_queued.is_shutdown = False
        self.store_queued.db_shard = 0
        self.store_queued.store = MagicMock()
        self.store_queued.store_queue = queue.Queue()
        self.store_queued.shutdown_mutex = threading.Lock()
        self.store_queued.update_sleeper = None
        self.store_queued.update_thread = None

    def test_queues_writes_until_processed(self):
        self.store_queued.hset("presence", "key", 10)
        self.store_queued.store.hset.assert_not_called()
        self.assertEqual(self.store_queued.store_queue.qsize(), 1)

        self.store_queued.process_queue()
        self.store_queued.store.hset.assert_called_once_with("presence", "key", 10)

    def test_writes_through_after_shutdown(self):
        self.store_queued.hset("presence", "key1", 10)
        self.store_queued.shutdown()
        # Shutdown drains what was already queued
        self.store_queued.store.hset.assert_called_once_with("presence", "key1", 10)

        # Nothing will drain the queue again, so later writes must not be queued
        self.store_queued.hset("presence", "key2", 20)
        self.store_queued.store.hset.assert_called_with("presence", "key2", 20)
        self.assertTrue(self.store_queued.store_queue.empty())

    def test_shutdown_drains_before_writing_through(self):
        # A direct write during the drain could be overwritten by an older queued
        # write, so the flag must only flip once the queue is empty
        seen = []
        self.store_queued.store.hset.side_effect = lambda *args: seen.append(self.store_queued.is_shutdown)
        self.store_queued.hset("presence", "key1", 10)
        self.store_queued.shutdown()
        self.assertEqual(seen, [False])
        self.assertTrue(self.store_queued.is_shutdown)


class TestStoreQueuedUpdateIntervalAllShards(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_updates_existing_instances_and_later_ones(self):
        existing = StoreQueued.instance(db_shard=0)
        self.assertEqual(existing.update_interval, 1)
        StoreQueued.set_update_interval_all_shards(0.25)
        self.assertEqual(existing.update_interval, 0.25)
        self.assertEqual(StoreQueued.instance(db_shard=1).update_interval, 0.25)
        # Separate setting per class
        self.assertEqual(EphemeralStoreQueued.instance(db_shard=1).update_interval, 1)
        # An explicit interval still wins for a new instance
        self.assertEqual(StoreQueued.instance(update_interval=0.5, db_shard=2).update_interval, 0.5)

    def test_ignores_intervals_of_zero_or_less(self):
        StoreQueued.set_update_interval_all_shards(0.25)
        StoreQueued.set_update_interval_all_shards(0)
        self.assertEqual(StoreQueued.instance().update_interval, 0.25)


if __name__ == "__main__":
    unittest.main()
