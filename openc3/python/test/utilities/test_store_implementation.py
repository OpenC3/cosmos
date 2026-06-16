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

from openc3.utilities.store_implementation import Store


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
