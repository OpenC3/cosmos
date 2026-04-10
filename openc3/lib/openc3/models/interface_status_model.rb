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
  # Stores the status about an interface. This class also implements logic
  # to handle status for a router since the functionality is identical
  # (only difference is the Redis key used).
  class InterfaceStatusModel < Model
    INTERFACES_PRIMARY_KEY = 'openc3_interface_status'
    ROUTERS_PRIMARY_KEY = 'openc3_router_status'

    attr_accessor :state
    attr_accessor :clients
    attr_accessor :txsize
    attr_accessor :rxsize
    attr_accessor :txbytes
    attr_accessor :rxbytes
    attr_accessor :txcnt
    attr_accessor :rxcnt

    # Look up the target_shard from the corresponding base model (InterfaceModel or RouterModel).
    # Base models are always stored on shard 0.
    def self._shard_for_name(name, scope:)
      type = _get_type
      if type == 'INTERFACESTATUS'
        json = Store.hget("#{scope}__openc3_interfaces", name)
      else
        json = Store.hget("#{scope}__openc3_routers", name)
      end
      return 0 unless json
      parsed = JSON.parse(json, allow_nan: true, create_additions: true)
      (parsed['target_shard'] || 0).to_i
    end

    # Collect all unique target_shard values from the corresponding base models.
    def self._active_shards(scope:)
      shards = Set.new([0])
      type = _get_type
      if type == 'INTERFACESTATUS'
        hash = Store.hgetall("#{scope}__openc3_interfaces")
      else
        hash = Store.hgetall("#{scope}__openc3_routers")
      end
      hash.each do |_name, json|
        parsed = JSON.parse(json, allow_nan: true, create_additions: true)
        shards << (parsed['target_shard'] || 0).to_i
      end
      shards
    end

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      shard = _shard_for_name(name, scope: scope)
      json = Store.instance(shard: shard).hget("#{scope}__#{_get_key}", name)
      if json
        return JSON.parse(json, allow_nan: true, create_additions: true)
      else
        return nil
      end
    end

    def self.names(scope:)
      result = []
      _active_shards(scope: scope).each do |shard|
        result.concat(Store.instance(shard: shard).hkeys("#{scope}__#{_get_key}"))
      end
      result.uniq.sort
    end

    def self.all(scope:)
      result = {}
      _active_shards(scope: scope).each do |shard|
        hash = Store.instance(shard: shard).hgetall("#{scope}__#{_get_key}")
        hash.each do |key, value|
          result[key] = JSON.parse(value, allow_nan: true, create_additions: true)
        end
      end
      result
    end
    # END NOTE

    # Helper method to return the correct type based on class name
    def self._get_type
      self.name.to_s.split("Model")[0].upcase.split("::")[-1]
    end

    # Helper method to return the correct primary key based on class name
    def self._get_key
      type = _get_type
      case type
      when 'INTERFACESTATUS'
        INTERFACES_PRIMARY_KEY
      when 'ROUTERSTATUS'
        ROUTERS_PRIMARY_KEY
      else
        raise "Unknown type #{type} from class #{self.name}"
      end
    end

    def initialize(
      name:,
      state:,
      clients: 0,
      txsize: 0,
      rxsize: 0,
      txbytes: 0,
      rxbytes: 0,
      txcnt: 0,
      rxcnt: 0,
      updated_at: nil,
      plugin: nil,
      scope:
    )
      if self.class._get_type == 'INTERFACESTATUS'
        super("#{scope}__#{INTERFACES_PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      else
        super("#{scope}__#{ROUTERS_PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      end
      @state = state
      @clients = clients
      @txsize = txsize
      @rxsize = rxsize
      @txbytes = txbytes
      @rxbytes = rxbytes
      @txcnt = txcnt
      @rxcnt = rxcnt
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
        'clients' => @clients,
        'txsize' => @txsize,
        'rxsize' => @rxsize,
        'txbytes' => @txbytes,
        'rxbytes' => @rxbytes,
        'txcnt' => @txcnt,
        'rxcnt' => @rxcnt,
        'plugin' => @plugin,
        'updated_at' => @updated_at
      }
    end
  end
end
