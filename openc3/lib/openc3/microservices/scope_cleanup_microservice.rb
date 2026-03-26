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

require 'openc3/models/scope_model'
require 'openc3/models/target_model'
require 'openc3/microservices/cleanup_microservice'

module OpenC3
  class ScopeCleanupMicroservice < CleanupMicroservice
    TSDB_HEALTH_QUERY =
"SELECT
    table_name,
    table_row_count,
    wal_pending_row_count,
    CASE
        WHEN table_suspended THEN 'SUSPENDED'
        WHEN table_memory_pressure_level = 2 THEN 'BACKOFF'
        WHEN table_memory_pressure_level = 1 THEN 'PRESSURE'
        ELSE 'OK'
    END AS status,
    wal_txn - table_txn AS lag_txns,
    table_write_amp_p50 AS write_amp,
    table_merge_rate_p99 AS slowest_merge
FROM tables()
WHERE walEnabled
ORDER BY
    table_suspended DESC,
    table_memory_pressure_level DESC,
    wal_pending_row_count DESC;"

    GROWTH_NUM_SAMPLE_PERIODS = 4

    def initialize(*args)
      super(*args)
      @run_time = nil
      @cleanup_poll_time = nil
      @delta_time = 0.0
      @wal_pending_row_count = {}
      @lag_txns = {}
    end

    def cleanup(areas, bucket)
      current_time = Time.now
      if @run_time
        delta = current_time - @run_time
        if delta > 0.0
          @delta_time += delta
        end
      end
      @run_time = current_time
      if @delta_time > @cleanup_poll_time
        @delta_time = 0.0
        super(areas, bucket)
      end

      # Always check TSDB health across all shards
      if @scope == 'DEFAULT'
        # Collect all unique shard numbers from targets
        shards = Set.new([0]) # Always check shard 0
        begin
          targets = OpenC3::TargetModel.all(scope: @scope)
          targets.each_value { |target| shards << target['shard'].to_i if target['shard'] }
        rescue => e
          @logger.error("QuestDB: Error getting target shards: #{e.formatted}")
        end

        shards.each do |shard|
          begin
            conn = OpenC3::QuestDBClient.connection(shard: shard)
            result = conn.exec(TSDB_HEALTH_QUERY)
            columns = result.fields
            rows = result.values

            table_name_column = columns.index("table_name")
            wal_pending_row_count_column = columns.index("wal_pending_row_count")
            status_column = columns.index("status")
            lag_txns_column = columns.index("lag_txns")

            rows.each do |values|
              table_name = values[table_name_column]
              # Prefix with shard to avoid key collisions across shards
              tracking_key = "s#{shard}__#{table_name}"
              wal_pending_row_count = values[wal_pending_row_count_column].to_i
              status = values[status_column]
              lag_txns = values[lag_txns_column].to_i

              if status != 'OK'
                @logger.error("QuestDB shard #{shard}: #{table_name} in bad state: #{status}")

                if status == 'SUSPENDED'
                  # Try to automatically unsuspend
                  @logger.info("QuestDB shard #{shard}: Attempting to unsuspend: #{table_name}")
                  conn.exec("ALTER TABLE #{table_name} RESUME WAL;")
                end
              end

              @wal_pending_row_count[tracking_key] ||= []
              @wal_pending_row_count[tracking_key] << wal_pending_row_count
              @lag_txns[tracking_key] ||= []
              @lag_txns[tracking_key] << lag_txns

              if @wal_pending_row_count[tracking_key].length > GROWTH_NUM_SAMPLE_PERIODS
                if detect_growth(@wal_pending_row_count[tracking_key], GROWTH_NUM_SAMPLE_PERIODS)
                  # Crossed threshold of sample periods of growth
                  @logger.error("QuestDB shard #{shard}: #{table_name} has growing wal_pending_row_count: #{wal_pending_row_count}")
                end

                # Leave the last GROWTH_NUM_SAMPLE_PERIODS samples
                @wal_pending_row_count[tracking_key] = @wal_pending_row_count[tracking_key][-GROWTH_NUM_SAMPLE_PERIODS..-1]
              end

              if @lag_txns[tracking_key].length > GROWTH_NUM_SAMPLE_PERIODS
                if detect_growth(@lag_txns[tracking_key], GROWTH_NUM_SAMPLE_PERIODS)
                  # Crossed threshold of sample periods of growth
                  @logger.error("QuestDB shard #{shard}: #{table_name} has growing lag_txns: #{lag_txns}")
                end

                # Leave the last GROWTH_NUM_SAMPLE_PERIODS samples
                @lag_txns[tracking_key] = @lag_txns[tracking_key][-GROWTH_NUM_SAMPLE_PERIODS..-1]
              end
            end
          rescue => e
            OpenC3::QuestDBClient.disconnect(shard: shard)
            @logger.error("QuestDB shard #{shard} Error: #{e.formatted}")
          end
        end
      end
    end

    def detect_growth(array, num_samples)
      num_samples.times do |index|
        return false if array[index + 1] <= array[index]
      end
      return true
    end

    def get_areas_and_poll_time
      scope = ScopeModel.get_model(name: @scope)
      areas = [
        ["#{@scope}/text_logs/openc3_log_messages", scope.text_log_retain_time],
        ["#{@scope}/tool_logs/sr", scope.tool_log_retain_time],
      ]

      if @scope == 'DEFAULT'
        areas << ["NOSCOPE/text_logs/openc3_log_messages", scope.text_log_retain_time]
        areas << ["NOSCOPE/tool_logs/sr", scope.tool_log_retain_time]
      end

      @cleanup_poll_time = scope.cleanup_poll_time
      return areas, 60 # Run every 1 minute for TSDB checks
    end
  end
end

if __FILE__ == $0
  OpenC3::ScopeCleanupMicroservice.run
  OpenC3::ThreadManager.instance.shutdown
  OpenC3::ThreadManager.instance.join
end