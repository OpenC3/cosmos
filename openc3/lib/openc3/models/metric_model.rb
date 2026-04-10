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
  class MetricModel < EphemeralModel
    include ShardedModel

    PRIMARY_KEY = '__openc3__metric'.freeze

    attr_accessor :values

    # Look up target_shard from the corresponding MicroserviceModel.
    def self._lookup_target_shard(name, scope:)
      json = Store.hget('openc3_microservices', name)
      json ? (JSON.parse(json, allow_nan: true, create_additions: true)['target_shard'] || 0).to_i : 0
    end

    # Collect all unique target_shard values from MicroserviceModels.
    def self._collect_target_shards(scope:)
      shards = Set.new([0])
      Store.hgetall('openc3_microservices').each do |name, json|
        next if scope and name.split("__")[0] != scope
        shards << (JSON.parse(json, allow_nan: true, create_additions: true)['target_shard'] || 0).to_i
      end
      shards
    end

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      _sharded_get("#{scope}#{PRIMARY_KEY}", name: name, scope: scope)
    end

    def self.names(scope:)
      _sharded_names("#{scope}#{PRIMARY_KEY}", scope: scope)
    end

    def self.all(scope:)
      _sharded_all("#{scope}#{PRIMARY_KEY}", scope: scope)
    end

    # Sets (updates) the redis hash of this model
    # Queued defaults to true for MetricModel
    def self.set(json, scope:, queued: true)
      json[:scope] = scope
      json.transform_keys!(&:to_sym)
      self.new(**json).create(force: true, queued: queued)
    end

    def self.destroy(scope:, name:)
      shard = _shard_for_name(name, scope: scope)
      store.instance(shard: shard).hdel("#{scope}#{PRIMARY_KEY}", name)
    end

    def initialize(name:, values: {}, target_shard: 0, scope:)
      super("#{scope}#{PRIMARY_KEY}", name: name, scope: scope)
      @values = values
      @target_shard = target_shard.to_i
    end

    def create(update: false, force: false, queued: false, isoformat: false)
      _sharded_create(@target_shard, update: update, force: force, queued: queued, isoformat: isoformat)
    end

    def destroy
      _sharded_destroy(@target_shard)
    end

    def as_json(*a)
      {
        'name' => @name,
        'updated_at' => @updated_at,
        'values' => @values.as_json(*a)
      }
    end

    def self.redis_extract_p50_and_p99_seconds(value)
      if value
        split_value = value.to_s.split(',')
        p50 = split_value[0].split('=')[-1].to_f / 1_000_000
        p99 = split_value[-1].split('=')[-1].to_f / 1_000_000
        return p50, p99
      else
        return 0.0, 0.0
      end
    end

    def self.redis_metrics
      # This prevents a circular dependency
      require 'openc3/models/scope_model' # NOSONAR
      require 'openc3/models/target_model' # NOSONAR

      shards = Set.new
      OpenC3::ScopeModel.names.each do |scope|
        targets = OpenC3::TargetModel.all(scope: scope)
        targets.each do |_target_name, target_hash|
          shards << target_hash['shard']
        end
      end

      result = {}
      shards.each do |index|
        shard_result = {}
        metrics = OpenC3::Store.instance(shard: index).info("all")
        shard_result["redis_connected_clients_total"] = metrics['connected_clients']
        shard_result["redis_used_memory_rss_total"] = metrics['used_memory_rss']
        shard_result["redis_commands_processed_total"] = metrics['total_commands_processed']
        shard_result["redis_iops"] = metrics['instantaneous_ops_per_sec']
        shard_result["redis_instantaneous_input_kbps"] = metrics['instantaneous_input_kbps']
        shard_result["redis_instantaneous_output_kbps"] = metrics['instantaneous_output_kbps']
        shard_result["redis_hget_p50_seconds"], shard_result["redis_hget_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hget'])
        shard_result["redis_hgetall_p50_seconds"], shard_result["redis_hgetall_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hgetall'])
        shard_result["redis_hset_p50_seconds"], shard_result["redis_hset_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hset'])
        shard_result["redis_xadd_p50_seconds"], shard_result["redis_xadd_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xadd'])
        shard_result["redis_xread_p50_seconds"], shard_result["redis_xread_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xread'])
        shard_result["redis_xrevrange_p50_seconds"], shard_result["redis_xrevrange_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xrevrange'])
        shard_result["redis_xtrim_p50_seconds"], shard_result["redis_xtrim_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xtrim'])

        metrics = OpenC3::EphemeralStore.instance(shard: index).info("all")
        shard_result["redis_ephemeral_connected_clients_total"] = metrics['connected_clients']
        shard_result["redis_ephemeral_used_memory_rss_total"] = metrics['used_memory_rss']
        shard_result["redis_ephemeral_commands_processed_total"] = metrics['total_commands_processed']
        shard_result["redis_ephemeral_iops"] = metrics['instantaneous_ops_per_sec']
        shard_result["redis_ephemeral_instantaneous_input_kbps"] = metrics['instantaneous_input_kbps']
        shard_result["redis_ephemeral_instantaneous_output_kbps"] = metrics['instantaneous_output_kbps']
        shard_result["redis_ephemeral_hget_p50_seconds"], shard_result["redis_ephemeral_hget_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hget'])
        shard_result["redis_ephemeral_hgetall_p50_seconds"], shard_result["redis_ephemeral_hgetall_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hgetall'])
        shard_result["redis_ephemeral_hset_p50_seconds"], shard_result["redis_ephemeral_hset_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hset'])
        shard_result["redis_ephemeral_xadd_p50_seconds"], shard_result["redis_ephemeral_xadd_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xadd'])
        shard_result["redis_ephemeral_xread_p50_seconds"], shard_result["redis_ephemeral_xread_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xread'])
        shard_result["redis_ephemeral_xrevrange_p50_seconds"], shard_result["redis_ephemeral_xrevrange_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xrevrange'])
        shard_result["redis_ephemeral_xtrim_p50_seconds"], shard_result["redis_ephemeral_xtrim_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xtrim'])
        result[index] = shard_result
      end

      return result
    end
  end
end
