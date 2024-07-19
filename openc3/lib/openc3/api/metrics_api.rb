# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/metric_model'
require 'openc3/utilities/authentication'
require 'openc3/utilities/store'

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

    DURATION_METRICS = {}
    DURATION_METRICS['decom_duration_seconds'] = 0.0
    DURATION_METRICS['reducer_minute_processing_sample_seconds'] = 0.0
    DURATION_METRICS['reducer_hour_processing_sample_seconds'] = 0.0
    DURATION_METRICS['reducer_day_processing_sample_seconds'] = 0.0
    DURATION_METRICS['reducer_minute_processing_max_seconds'] = 0.0
    DURATION_METRICS['reducer_hour_processing_max_seconds'] = 0.0
    DURATION_METRICS['reducer_day_processing_max_seconds'] = 0.0

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
    SUM_METRICS['reducer_minute_total'] = 0
    SUM_METRICS['reducer_hour_total'] = 0
    SUM_METRICS['reducer_day_total'] = 0
    SUM_METRICS['reducer_minute_error_total'] = 0
    SUM_METRICS['reducer_hour_error_total'] = 0
    SUM_METRICS['reducer_day_error_total'] = 0
    SUM_METRICS['router_cmd_total'] = 0
    SUM_METRICS['router_tlm_total'] = 0
    SUM_METRICS['router_directive_total'] = 0
    SUM_METRICS['text_log_total'] = 0
    SUM_METRICS['text_log_error_total'] = 0

    def get_metrics(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)

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

      result.merge!(MetricModel.redis_metrics)

      return result
    end
  end
end
