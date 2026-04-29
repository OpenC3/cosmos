# encoding: ascii-8bit

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
# Including classes must define two class methods:
#   _lookup_db_shard(name, scope:) -> Integer
#   _collect_db_shards(scope:) -> Set
module OpenC3
  module DbShardedModel
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Lookup of db_shard for a given name.
      # Hard-cached only when use_cache: true (intended for the set/create path
      # where the db_shard won't change within the process lifetime).
      def _db_shard_for_name(name, scope:, use_cache: false)
        if use_cache
          cache = (@db_shard_cache ||= {})
          cache_key = "#{scope}__#{name}"
          cached = cache[cache_key]
          return cached unless cached.nil?
        end

        db_shard = _lookup_db_shard(name, scope: scope)

        if use_cache
          cache[cache_key] = db_shard
        end

        db_shard
      end

      # Collect all active db_shards (always fresh lookup, no cache).
      def _active_db_shards(scope:)
        _collect_db_shards(scope: scope)
      end

      # DB_Shard-aware get: looks up the db_shard for name, reads from the correct store instance.
      def _db_sharded_get(key, name:, scope:)
        db_shard = _db_shard_for_name(name, scope: scope)
        json = store.instance(db_shard: db_shard).hget(key, name)
        json ? JSON.parse(json, allow_nan: true, create_additions: true) : nil
      end

      # DB_Shard-aware names: iterates all active db_shards and collects keys.
      def _db_sharded_names(key, scope:)
        result = []
        _active_db_shards(scope: scope).each do |db_shard|
          result.concat(store.instance(db_shard: db_shard).hkeys(key))
        end
        result.uniq.sort
      end

      # DB_Shard-aware all: iterates all active db_shards and collects all values.
      def _db_sharded_all(key, scope:)
        result = {}
        _active_db_shards(scope: scope).each do |db_shard|
          hash = store.instance(db_shard: db_shard).hgetall(key)
          hash.each do |k, value|
            result[k] = JSON.parse(value, allow_nan: true, create_additions: true)
          end
        end
        result
      end
    end

    # DB_Shard-aware create: writes to the store instance for the given db_shard.
    def _db_sharded_create(db_shard, update: false, force: false, queued: false, isoformat: false, expire_seconds: nil)
      db_shard_store = self.class.store.instance(db_shard: db_shard)
      unless force
        existing = db_shard_store.hget(@primary_key, @name)
        if existing
          raise RuntimeError.new("#{@primary_key}:#{@name} already exists at create") unless update
        else
          raise RuntimeError.new("#{@primary_key}:#{@name} doesn't exist at update") if update
        end
      end
      @updated_at = isoformat ? Time.now.utc.iso8601 : Time.now.utc.to_nsec_from_epoch

      if queued
        store = self.class.store_queued.instance(db_shard: db_shard)
        store.hset(@primary_key, @name, JSON.generate(self.as_json(), allow_nan: true))
        store.call(:hexpire, @primary_key, expire_seconds, 'FIELDS', 1, @name) if expire_seconds
      else
        db_shard_store.hset(@primary_key, @name, JSON.generate(self.as_json(), allow_nan: true))
        db_shard_store.call(:hexpire, @primary_key, expire_seconds, 'FIELDS', 1, @name) if expire_seconds
      end
    end

    # DB_Shard-aware destroy: deletes from the store instance for the given db_shard.
    def _db_sharded_destroy(db_shard)
      @destroyed = true
      self.class.store.instance(db_shard: db_shard).hdel(@primary_key, @name)
    end
  end
end
