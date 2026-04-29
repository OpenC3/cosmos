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

# Mixin that provides db_shard-aware Redis operations with hard caching.
# Subclasses must define two class methods:
#   _lookup_db_shard(name, scope) -> int
#   _collect_db_shards(scope) -> set[int]

import json
import time


class DbShardedModel:
    """Mixin providing db_shard-aware Redis operations with hard caching.

    Including classes must define:
      _lookup_db_shard(cls, name, scope) -> int
      _collect_db_shards(cls, scope) -> set[int]
    """

    @classmethod
    def _get_db_shard_cache(cls):
        if not hasattr(cls, "_db_shard_cache") or cls._db_shard_cache is None:
            cls._db_shard_cache = {}
        return cls._db_shard_cache

    @classmethod
    def _db_shard_for_name(cls, name, scope, use_cache=False):
        """Lookup of db_shard for a given name.
        Hard-cached only when use_cache=True (intended for the set/create path
        where the db_shard won't change within the process lifetime)."""
        if use_cache:
            cache = cls._get_db_shard_cache()
            cache_key = f"{scope}__{name}"
            if cache_key in cache:
                return cache[cache_key]

        db_shard = cls._lookup_db_shard(name, scope)

        if use_cache:
            cache[cache_key] = db_shard

        return db_shard

    @classmethod
    def _active_db_shards(cls, scope):
        """Collect all active db_shards (always fresh lookup, no cache)."""
        return cls._collect_db_shards(scope)

    @classmethod
    def _db_sharded_get(cls, key, name, scope):
        """DB_Shard-aware get: looks up the db_shard for name, reads from the correct store instance."""
        db_shard = cls._db_shard_for_name(name, scope)
        json_data = cls.store().instance(db_shard=db_shard).hget(key, name)
        return json.loads(json_data) if json_data else None

    @classmethod
    def _db_sharded_names(cls, key, scope):
        """DB_Shard-aware names: iterates all active db_shards and collects keys."""
        result = []
        for db_shard in cls._active_db_shards(scope):
            keys = cls.store().instance(db_shard=db_shard).hkeys(key)
            result.extend(key.decode() for key in keys)
        return sorted(set(result))

    @classmethod
    def _db_sharded_all(cls, key, scope):
        """DB_Shard-aware all: iterates all active db_shards and collects all values."""
        result = {}
        for db_shard in cls._active_db_shards(scope):
            base = cls.store().instance(db_shard=db_shard).hgetall(key)
            decoded = {k.decode(): v for (k, v) in base.items()}
            for k, value in decoded.items():
                result[k] = json.loads(value)
        return result

    def _db_sharded_create(self, db_shard, update=False, force=False, queued=False, expire_seconds=None):
        """DB_Shard-aware create: writes to the store instance for the given db_shard."""
        db_shard_store = self.__class__.store().instance(db_shard=db_shard)
        if not force:
            existing = db_shard_store.hget(self.primary_key, self.name)
            if existing and not update:
                raise RuntimeError(f"{self.primary_key}:{self.name} already exists at create")
            if not existing and update:
                raise RuntimeError(f"{self.primary_key}:{self.name} doesn't exist at update")
        self.updated_at = time.time() * 1_000_000_000

        if queued:
            store = self.__class__.store_queued().instance(db_shard=db_shard)
            store.hset(self.primary_key, self.name, json.dumps(self.as_json()))
            if expire_seconds is not None:
                store.execute_command("HEXPIRE", self.primary_key, expire_seconds, "FIELDS", 1, self.name)
        else:
            db_shard_store.hset(self.primary_key, self.name, json.dumps(self.as_json()))
            if expire_seconds is not None:
                db_shard_store.execute_command("HEXPIRE", self.primary_key, expire_seconds, "FIELDS", 1, self.name)

    def _db_sharded_destroy(self, db_shard):
        """DB_Shard-aware destroy: deletes from the store instance for the given db_shard."""
        self.destroyed = True
        self.__class__.store().instance(db_shard=db_shard).hdel(self.primary_key, self.name)
