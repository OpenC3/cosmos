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

# Mixin that provides shard-aware Redis operations with hard caching.
# Subclasses must define two class methods:
#   _lookup_db_shard(name, scope) -> int
#   _collect_db_shards(scope) -> set[int]

import json
import time


class ShardedModel:
    """Mixin providing shard-aware Redis operations with hard caching.

    Including classes must define:
      _lookup_db_shard(cls, name, scope) -> int
      _collect_db_shards(cls, scope) -> set[int]
    """

    @classmethod
    def _get_shard_cache(cls):
        if not hasattr(cls, "_shard_cache") or cls._shard_cache is None:
            cls._shard_cache = {}
        return cls._shard_cache

    @classmethod
    def _shard_for_name(cls, name, scope, use_cache=False):
        """Lookup of db_shard for a given name.
        Hard-cached only when use_cache=True (intended for the set/create path
        where the shard won't change within the process lifetime)."""
        if use_cache:
            cache = cls._get_shard_cache()
            cache_key = f"{scope}__{name}"
            if cache_key in cache:
                return cache[cache_key]

        shard = cls._lookup_db_shard(name, scope)

        if use_cache:
            cache[cache_key] = shard

        return shard

    @classmethod
    def _active_shards(cls, scope):
        """Collect all active shards (always fresh lookup, no cache)."""
        return cls._collect_db_shards(scope)

    @classmethod
    def _sharded_get(cls, key, name, scope):
        """Shard-aware get: looks up the shard for name, reads from the correct store instance."""
        shard = cls._shard_for_name(name, scope)
        json_data = cls.store().instance(shard=shard).hget(key, name)
        return json.loads(json_data) if json_data else None

    @classmethod
    def _sharded_names(cls, key, scope):
        """Shard-aware names: iterates all active shards and collects keys."""
        result = []
        for shard in cls._active_shards(scope):
            keys = cls.store().instance(shard=shard).hkeys(key)
            result.extend(key.decode() for key in keys)
        return sorted(set(result))

    @classmethod
    def _sharded_all(cls, key, scope):
        """Shard-aware all: iterates all active shards and collects all values."""
        result = {}
        for shard in cls._active_shards(scope):
            base = cls.store().instance(shard=shard).hgetall(key)
            decoded = {k.decode(): v for (k, v) in base.items()}
            for k, value in decoded.items():
                result[k] = json.loads(value)
        return result

    def _sharded_create(self, shard, update=False, force=False, queued=False):
        """Shard-aware create: writes to the store instance for the given shard."""
        shard_store = self.__class__.store().instance(shard=shard)
        if not force:
            existing = shard_store.hget(self.primary_key, self.name)
            if existing and not update:
                raise RuntimeError(f"{self.primary_key}:{self.name} already exists at create")
            if not existing and update:
                raise RuntimeError(f"{self.primary_key}:{self.name} doesn't exist at update")
        self.updated_at = time.time() * 1_000_000_000

        if queued:
            self.__class__.store_queued().instance(shard=shard).hset(
                self.primary_key, self.name, json.dumps(self.as_json())
            )
        else:
            shard_store.hset(self.primary_key, self.name, json.dumps(self.as_json()))

    def _sharded_destroy(self, shard):
        """Shard-aware destroy: deletes from the store instance for the given shard."""
        self.destroyed = True
        self.__class__.store().instance(shard=shard).hdel(self.primary_key, self.name)
