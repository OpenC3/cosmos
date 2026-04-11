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
require 'openc3/models/sharded_model'

module OpenC3
  class MicroserviceStatusModel < Model
    include ShardedModel

    PRIMARY_KEY = 'openc3_microservice_status'

    attr_accessor :state
    attr_accessor :count
    attr_accessor :error
    attr_accessor :custom

    # Look up db_shard from the corresponding MicroserviceModel.
    def self._lookup_db_shard(name, scope:)
      json = Store.hget('openc3_microservices', name)
      json ? (JSON.parse(json, allow_nan: true, create_additions: true)['db_shard'] || 0).to_i : 0
    end

    # Collect all unique db_shard values from MicroserviceModels.
    def self._collect_db_shards(scope:)
      shards = Set.new([0])
      Store.hgetall('openc3_microservices').each do |name, json|
        next if scope and name.split("__")[0] != scope
        shards << (JSON.parse(json, allow_nan: true, create_additions: true)['db_shard'] || 0).to_i
      end
      shards
    end

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      _sharded_get("#{scope}__#{PRIMARY_KEY}", name: name, scope: scope)
    end

    def self.names(scope:)
      _sharded_names("#{scope}__#{PRIMARY_KEY}", scope: scope)
    end

    def self.all(scope:)
      _sharded_all("#{scope}__#{PRIMARY_KEY}", scope: scope)
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

    def create(update: false, force: false, queued: false, isoformat: false)
      _sharded_create(self.class._shard_for_name(@name, scope: @scope, use_cache: true), update: update, force: force, queued: queued, isoformat: isoformat)
    end

    def destroy
      _sharded_destroy(self.class._shard_for_name(@name, scope: @scope))
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
