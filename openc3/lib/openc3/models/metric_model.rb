# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/model'

module OpenC3
  class MetricModel < EphemeralModel
    PRIMARY_KEY = '__openc3__metric'.freeze

    attr_accessor :values

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      super("#{scope}#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope:)
      super("#{scope}#{PRIMARY_KEY}")
    end

    def self.all(scope:)
      super("#{scope}#{PRIMARY_KEY}")
    end

    def self.destroy(scope:, name:)
      EphemeralStore.hdel("#{scope}#{PRIMARY_KEY}", name)
    end

    def initialize(name:, values: {}, scope:)
      super("#{scope}#{PRIMARY_KEY}", name: name, scope: scope)
      @values = values
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
      result = {}

      metrics = OpenC3::Store.info("all")
      result['redis_connected_clients_total'] = metrics['connected_clients']
      result['redis_used_memory_rss_total'] = metrics['used_memory_rss']
      result['redis_commands_processed_total'] = metrics['total_commands_processed']
      result['redis_iops'] = metrics['instantaneous_ops_per_sec']
      result['redis_instantaneous_input_kbps'] = metrics['instantaneous_input_kbps']
      result['redis_instantaneous_output_kbps'] = metrics['instantaneous_output_kbps']
      result['redis_keys_total'] = metrics['keys']
      result['redis_hget_p50_seconds'], result['redis_hget_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hget'])
      result['redis_hgetall_p50_seconds'], result['redis_hgetall_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hgetall'])
      result['redis_hset_p50_seconds'], result['redis_hset_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hset'])
      result['redis_xadd_p50_seconds'], result['redis_xadd_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xadd'])
      result['redis_xread_p50_seconds'], result['redis_xread_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xread'])
      result['redis_xrevrange_p50_seconds'], result['redis_xrevrange_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xrevrange'])
      result['redis_xtrim_p50_seconds'], result['redis_xtrim_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xtrim'])

      metrics = OpenC3::EphemeralStore.info("all")
      result['redis_ephemeral_connected_clients_total'] = metrics['connected_clients']
      result['redis_ephemeral_used_memory_rss_total'] = metrics['used_memory_rss']
      result['redis_ephemeral_commands_processed_total'] = metrics['total_commands_processed']
      result['redis_ephemeral_iops'] = metrics['instantaneous_ops_per_sec']
      result['redis_ephemeral_instantaneous_input_kbps'] = metrics['instantaneous_input_kbps']
      result['redis_ephemeral_instantaneous_output_kbps'] = metrics['instantaneous_output_kbps']
      result['redis_ephemeral_keys_total'] = metrics['keys']
      result['redis_ephemeral_hget_p50_seconds'], result['redis_ephemeral_hget_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hget'])
      result['redis_ephemeral_hgetall_p50_seconds'], result['redis_ephemeral_hgetall_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hgetall'])
      result['redis_ephemeral_hset_p50_seconds'], result['redis_ephemeral_hset_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_hset'])
      result['redis_ephemeral_xadd_p50_seconds'], result['redis_ephemeral_xadd_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xadd'])
      result['redis_ephemeral_xread_p50_seconds'], result['redis_ephemeral_xread_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xread'])
      result['redis_ephemeral_xrevrange_p50_seconds'], result['redis_ephemeral_xrevrange_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xrevrange'])
      result['redis_ephemeral_xtrim_p50_seconds'], result['redis_ephemeral_xtrim_p99_seconds'] = redis_extract_p50_and_p99_seconds(metrics['latency_percentiles_usec_xtrim'])

      return result
    end
  end
end
