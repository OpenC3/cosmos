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
require 'openc3/models/db_sharded_model'

module OpenC3
  class MetricModel < EphemeralModel
    include DbShardedModel

    PRIMARY_KEY = '__openc3__metric'.freeze
    METRIC_EXPIRE_SECONDS = 3600 # Expire metrics after 1 hour

    attr_accessor :values
    attr_accessor :db_shard

    # Look up db_shard from the corresponding MicroserviceModel.
    def self._lookup_db_shard(name, scope:)
      json = Store.hget('openc3_microservices', name)
      json ? (JSON.parse(json, allow_nan: true, create_additions: true)['db_shard'] || 0).to_i : 0
    end

    # Collect all unique db_shard values from MicroserviceModels.
    def self._collect_db_shards(scope:)
      db_shards = Set.new([0])
      Store.hgetall('openc3_microservices').each do |name, json|
        next if scope and name.split("__")[0] != scope
        db_shards << (JSON.parse(json, allow_nan: true, create_additions: true)['db_shard'] || 0).to_i
      end
      db_shards
    end

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      _db_sharded_get("#{scope}#{PRIMARY_KEY}", name: name, scope: scope)
    end

    def self.names(scope:)
      _db_sharded_names("#{scope}#{PRIMARY_KEY}", scope: scope)
    end

    def self.all(scope:)
      _db_sharded_all("#{scope}#{PRIMARY_KEY}", scope: scope)
    end

    # Sets (updates) the redis hash of this model
    # Queued defaults to true for MetricModel
    def self.set(json, scope:, queued: true)
      json[:scope] = scope
      json.transform_keys!(&:to_sym)
      self.new(**json).create(force: true, queued: queued, expire_seconds: METRIC_EXPIRE_SECONDS)
    end

    def self.destroy(scope:, name:)
      db_shard = _db_shard_for_name(name, scope: scope)
      store.instance(db_shard: db_shard).hdel("#{scope}#{PRIMARY_KEY}", name)
    end

    def initialize(name:, values: {}, db_shard: 0, scope:)
      super("#{scope}#{PRIMARY_KEY}", name: name, scope: scope)
      @values = values
      @db_shard = db_shard.to_i
    end

    def create(update: false, force: false, queued: false, isoformat: false, expire_seconds: nil)
      _db_sharded_create(@db_shard, update: update, force: force, queued: queued, isoformat: isoformat, expire_seconds: expire_seconds)
    end

    def destroy
      _db_sharded_destroy(@db_shard)
    end

    def as_json(*a)
      {
        'name' => @name,
        'updated_at' => @updated_at,
        'values' => @values.as_json(*a),
        'db_shard' => @db_shard,
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

      db_shards = Set.new
      OpenC3::ScopeModel.names.each do |scope|
        targets = OpenC3::TargetModel.all(scope: scope)
        targets.each do |_target_name, target_hash|
          db_shards << target_hash['db_shard'].to_i
        end
      end

      result = {}
      db_shards.each do |index|
        db_shard_result = {}
        metrics = OpenC3::Store.instance(db_shard: index).info("all")
        db_shard_result["redis_connected_clients_total"] = metrics['connected_clients']
        db_shard_result["redis_used_memory_rss_total"] = metrics['used_memory_rss']
        db_shard_result["redis_commands_processed_total"] = metrics['total_commands_processed']
        db_shard_result["redis_iops"] = metrics['instantaneous_ops_per_sec']
        db_shard_result["redis_instantaneous_input_kbps"] = metrics['instantaneous_input_kbps']
        db_shard_result["redis_instantaneous_output_kbps"] = metrics['instantaneous_output_kbps']
        db_shard_result["redis_instantaneous_eventloop_cps"] = metrics['instantaneous_eventloop_cycles_per_sec']
        db_shard_result["redis_instantaneous_eventloop_duration_usec"] = metrics['instantaneous_eventloop_duration_usec']
        db_shard_result["redis_cpu_sys"] = metrics['used_cpu_sys']
        db_shard_result["redis_cpu_user"] = metrics['used_cpu_user']
        db_shard_result["redis_error_noauth_total"] = metrics['errorstat_NOAUTH'].to_s.split("count=")[-1].to_i
        db_shard_result["redis_error_noperm_total"] = metrics['errorstat_NOPERM'].to_s.split("count=")[-1].to_i
        db_shard_result["redis_hget_p50_seconds"], db_shard_result["redis_hget_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hget'])
        db_shard_result["redis_hgetall_p50_seconds"], db_shard_result["redis_hgetall_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hgetall'])
        db_shard_result["redis_hset_p50_seconds"], db_shard_result["redis_hset_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hset'])
        db_shard_result["redis_xadd_p50_seconds"], db_shard_result["redis_xadd_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xadd'])
        db_shard_result["redis_xread_p50_seconds"], db_shard_result["redis_xread_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xread'])
        db_shard_result["redis_xrevrange_p50_seconds"], db_shard_result["redis_xrevrange_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xrevrange'])
        db_shard_result["redis_xtrim_p50_seconds"], db_shard_result["redis_xtrim_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xtrim'])

        metrics = OpenC3::EphemeralStore.instance(db_shard: index).info("all")
        db_shard_result["redis_ephemeral_connected_clients_total"] = metrics['connected_clients']
        db_shard_result["redis_ephemeral_used_memory_rss_total"] = metrics['used_memory_rss']
        db_shard_result["redis_ephemeral_commands_processed_total"] = metrics['total_commands_processed']
        db_shard_result["redis_ephemeral_iops"] = metrics['instantaneous_ops_per_sec']
        db_shard_result["redis_ephemeral_instantaneous_input_kbps"] = metrics['instantaneous_input_kbps']
        db_shard_result["redis_ephemeral_instantaneous_output_kbps"] = metrics['instantaneous_output_kbps']
        db_shard_result["redis_ephemeral_instantaneous_eventloop_cps"] = metrics['instantaneous_eventloop_cycles_per_sec']
        db_shard_result["redis_ephemeral_instantaneous_eventloop_duration_usec"] = metrics['instantaneous_eventloop_duration_usec']
        db_shard_result["redis_ephemeral_cpu_sys"] = metrics['used_cpu_sys']
        db_shard_result["redis_ephemeral_cpu_user"] = metrics['used_cpu_user']
        db_shard_result["redis_ephemeral_error_noauth_total"] = metrics['errorstat_NOAUTH'].to_s.split("count=")[-1].to_i
        db_shard_result["redis_ephemeral_error_noperm_total"] = metrics['errorstat_NOPERM'].to_s.split("count=")[-1].to_i
        db_shard_result["redis_ephemeral_hget_p50_seconds"], db_shard_result["redis_ephemeral_hget_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hget'])
        db_shard_result["redis_ephemeral_hgetall_p50_seconds"], db_shard_result["redis_ephemeral_hgetall_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hgetall'])
        db_shard_result["redis_ephemeral_hset_p50_seconds"], db_shard_result["redis_ephemeral_hset_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hset'])
        db_shard_result["redis_ephemeral_xadd_p50_seconds"], db_shard_result["redis_ephemeral_xadd_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xadd'])
        db_shard_result["redis_ephemeral_xread_p50_seconds"], db_shard_result["redis_ephemeral_xread_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xread'])
        db_shard_result["redis_ephemeral_xrevrange_p50_seconds"], db_shard_result["redis_ephemeral_xrevrange_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xrevrange'])
        db_shard_result["redis_ephemeral_xtrim_p50_seconds"], db_shard_result["redis_ephemeral_xtrim_p99_seconds"] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xtrim'])
        result[index] = db_shard_result
      end

      return result
    end
  end
end
