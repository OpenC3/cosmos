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

# Mixin that provides shard-aware Redis operations with hard caching.
# Including classes must define two class methods:
#   _lookup_target_shard(name, scope:) -> Integer
#   _collect_target_shards(scope:) -> Set
module OpenC3
  module ShardedModel
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Lookup of target_shard for a given name.
      # Hard-cached only when use_cache: true (intended for the set/create path
      # where the shard won't change within the process lifetime).
      def _shard_for_name(name, scope:, use_cache: false)
        if use_cache
          cache = (@shard_cache ||= {})
          cache_key = "#{scope}__#{name}"
          cached = cache[cache_key]
          return cached unless cached.nil?
        end

        shard = _lookup_target_shard(name, scope: scope)

        if use_cache
          cache[cache_key] = shard
        end

        shard
      end

      # Collect all active shards (always fresh lookup, no cache).
      def _active_shards(scope:)
        _collect_target_shards(scope: scope)
      end

      # Shard-aware get: looks up the shard for name, reads from the correct store instance.
      def _sharded_get(key, name:, scope:)
        shard = _shard_for_name(name, scope: scope)
        json = store.instance(shard: shard).hget(key, name)
        json ? JSON.parse(json, allow_nan: true, create_additions: true) : nil
      end

      # Shard-aware names: iterates all active shards and collects keys.
      def _sharded_names(key, scope:)
        result = []
        _active_shards(scope: scope).each do |shard|
          result.concat(store.instance(shard: shard).hkeys(key))
        end
        result.uniq.sort
      end

      # Shard-aware all: iterates all active shards and collects all values.
      def _sharded_all(key, scope:)
        result = {}
        _active_shards(scope: scope).each do |shard|
          hash = store.instance(shard: shard).hgetall(key)
          hash.each do |k, value|
            result[k] = JSON.parse(value, allow_nan: true, create_additions: true)
          end
        end
        result
      end
    end

    # Shard-aware create: writes to the store instance for the given shard.
    def _sharded_create(shard, update: false, force: false, queued: false, isoformat: false)
      shard_store = self.class.store.instance(shard: shard)
      unless force
        existing = shard_store.hget(@primary_key, @name)
        if existing
          raise "#{@primary_key}:#{@name} already exists at create" unless update
        else
          raise "#{@primary_key}:#{@name} doesn't exist at update" if update
        end
      end
      @updated_at = isoformat ? Time.now.utc.iso8601 : Time.now.utc.to_nsec_from_epoch

      if queued
        self.class.store_queued.instance(shard: shard).hset(@primary_key, @name, JSON.generate(self.as_json(), allow_nan: true))
      else
        shard_store.hset(@primary_key, @name, JSON.generate(self.as_json(), allow_nan: true))
      end
    end

    # Shard-aware destroy: deletes from the store instance for the given shard.
    def _sharded_destroy(shard)
      @destroyed = true
      self.class.store.instance(shard: shard).hdel(@primary_key, @name)
    end
  end
end
