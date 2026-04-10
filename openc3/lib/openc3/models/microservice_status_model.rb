# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/model'

module OpenC3
  class MicroserviceStatusModel < Model
    PRIMARY_KEY = 'openc3_microservice_status'

    attr_accessor :state
    attr_accessor :count
    attr_accessor :error
    attr_accessor :custom

    # Look up the target_shard from the corresponding MicroserviceModel.
    # MicroserviceModel data is always stored on shard 0 under a global primary key.
    def self._shard_for_name(name, scope:)
      json = Store.hget('openc3_microservices', name)
      return 0 unless json
      parsed = JSON.parse(json, allow_nan: true, create_additions: true)
      (parsed['target_shard'] || 0).to_i
    end

    # Collect all unique target_shard values from MicroserviceModels for the given scope.
    def self._active_shards(scope:)
      shards = Set.new([0])
      hash = Store.hgetall('openc3_microservices')
      hash.each do |name, json|
        next if scope and name.split("__")[0] != scope
        parsed = JSON.parse(json, allow_nan: true, create_additions: true)
        shards << (parsed['target_shard'] || 0).to_i
      end
      shards
    end

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      shard = _shard_for_name(name, scope: scope)
      json = Store.instance(shard: shard).hget("#{scope}__#{PRIMARY_KEY}", name)
      if json
        return JSON.parse(json, allow_nan: true, create_additions: true)
      else
        return nil
      end
    end

    def self.names(scope:)
      result = []
      _active_shards(scope: scope).each do |shard|
        result.concat(Store.instance(shard: shard).hkeys("#{scope}__#{PRIMARY_KEY}"))
      end
      result.uniq.sort
    end

    def self.all(scope:)
      result = {}
      _active_shards(scope: scope).each do |shard|
        hash = Store.instance(shard: shard).hgetall("#{scope}__#{PRIMARY_KEY}")
        hash.each do |key, value|
          result[key] = JSON.parse(value, allow_nan: true, create_additions: true)
        end
      end
      result
    end

    def initialize(
      name:,
      state: nil,
      count: 0,
      error: nil,
      custom: nil,
      updated_at: nil,
      plugin: nil,
      scope:
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      @state = state
      @count = count
      @error = error
      @custom = custom
    end

    # Override create to write to the correct shard
    def create(update: false, force: false, queued: false, isoformat: false)
      shard = self.class._shard_for_name(@name, scope: @scope)
      shard_store = Store.instance(shard: shard)
      unless force
        existing = shard_store.hget(@primary_key, @name)
        if existing
          raise "#{@primary_key}:#{@name} already exists at create" unless update
        else
          raise "#{@primary_key}:#{@name} doesn't exist at update" if update
        end
      end
      if isoformat
        @updated_at = Time.now.utc.iso8601
      else
        @updated_at = Time.now.utc.to_nsec_from_epoch
      end

      if queued
        StoreQueued.instance(shard: shard).hset(@primary_key, @name, JSON.generate(self.as_json(), allow_nan: true))
      else
        shard_store.hset(@primary_key, @name, JSON.generate(self.as_json(), allow_nan: true))
      end
    end

    # Override destroy to delete from the correct shard
    def destroy
      @destroyed = true
      shard = self.class._shard_for_name(@name, scope: @scope)
      Store.instance(shard: shard).hdel(@primary_key, @name)
    end

    def as_json(*a)
      {
        'name' => @name,
        'state' => @state,
        'count' => @count,
        'error' => @error.as_json(),
        'custom' => @custom.as_json(),
        'plugin' => @plugin,
        'updated_at' => @updated_at
      }
    end
  end
end
