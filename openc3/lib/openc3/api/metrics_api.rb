# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/metric_model'
require 'openc3/utilities/authentication'
require 'openc3/utilities/store'
require 'openc3/utilities/topic_lag_monitor'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'get_metrics',
                     ])

    DELAY_METRICS = {}
    DELAY_METRICS['decom_topic_delta_seconds'] = 0.0
    DELAY_METRICS['interface_topic_delta_seconds'] = 0.0
    DELAY_METRICS['log_topic_delta_seconds'] = 0.0
    DELAY_METRICS['router_topic_delta_seconds'] = 0.0
    DELAY_METRICS['text_log_topic_delta_seconds'] = 0.0
    DELAY_METRICS['tsdb_ingest_topic_delta_seconds'] = 0.0

    DURATION_METRICS = {}
    DURATION_METRICS['decom_duration_seconds'] = 0.0
    DURATION_METRICS['tsdb_ingest_duration_seconds'] = 0.0

    SUM_METRICS = {}
    SUM_METRICS['cleanup_total'] = 0
    SUM_METRICS['cleanup_delete_total'] = 0
    SUM_METRICS['decom_total'] = 0
    SUM_METRICS['decom_error_total'] = 0
    SUM_METRICS['interface_cmd_total'] = 0
    SUM_METRICS['interface_tlm_total'] = 0
    SUM_METRICS['interface_directive_total'] = 0
    SUM_METRICS['log_total'] = 0
    SUM_METRICS['log_error_total'] = 0
    SUM_METRICS['periodic_total'] = 0
    SUM_METRICS['router_cmd_total'] = 0
    SUM_METRICS['router_tlm_total'] = 0
    SUM_METRICS['router_directive_total'] = 0
    SUM_METRICS['text_log_total'] = 0
    SUM_METRICS['text_log_error_total'] = 0
    SUM_METRICS['tsdb_ingest_total'] = 0
    SUM_METRICS['tsdb_ingest_error_total'] = 0

    # Metrics shown per service in Data Flows
    FLOW_METRIC_SUFFIXES = %w(_topic_delta_seconds _duration_seconds _read_queue_bytes _total).freeze

    def get_metrics(detailed: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      return _flow_metrics(scope) if detailed

      sum_metrics = SUM_METRICS.dup
      duration_metrics = DURATION_METRICS.dup
      delay_metrics = DELAY_METRICS.dup

      metrics = MetricModel.all(scope: scope)
      metrics.each do |_microservice_name, metrics|
        next unless metrics and metrics['values']
        metrics['values'].each do |metric_name, data|
          value = data['value']
          if sum_metrics[metric_name]
            sum_metrics[metric_name] += value
          elsif duration_metrics[metric_name]
            previous = duration_metrics[metric_name]
            duration_metrics[metric_name] = value if value > previous
          elsif delay_metrics.include?(metric_name)
            previous = delay_metrics[metric_name]
            delay_metrics[metric_name] = value if value > previous
          else
            # Ignore other metrics for now
          end
        end
      end

      result = delay_metrics
      result.merge!(duration_metrics)
      result.merge!(sum_metrics)

      redis_metrics = MetricModel.redis_metrics
      redis_metrics.each do |_db_shard, values|
        values.each do |key, value|
          existing = result[key]
          result[key] = value if existing.nil? or value > existing
        end
      end

      return result
    end

    # Per service metrics for Data Flows. Reads only what each microservice
    # reported itself so updated_at shows when that service last published;
    # the operator's process metrics would otherwise keep it fresh while the
    # process is alive. Sends just the values Data Flows displays, plus the
    # lag thresholds so its indicators match the falling behind notifications.
    def _flow_metrics(scope)
      services = {}
      MetricModel.all_self_reported(scope: scope).each do |name, entry|
        next unless entry and entry['values']
        values = {}
        entry['values'].each do |metric_name, data|
          next unless data.is_a?(Hash) and metric_name.end_with?(*FLOW_METRIC_SUFFIXES)
          values[metric_name] = { 'value' => data['value'] }
        end
        next if values.empty?
        services[name] = { 'updated_at' => entry['updated_at'], 'values' => values }
      end
      { 'lag_thresholds' => TopicLagMonitor.thresholds, 'services' => services }
    end
  end
end
