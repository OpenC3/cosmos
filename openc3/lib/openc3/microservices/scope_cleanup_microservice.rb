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

      # Always check TSDB health
      if @scope == 'DEFAULT'
        begin
          conn = OpenC3::QuestDBClient.connection
          result = conn.exec(TSDB_HEALTH_QUERY)
          columns = result.fields
          rows = result.values

          table_name_column = columns.index("table_name")
          wal_pending_row_count_column = columns.index("wal_pending_row_count")
          status_column = columns.index("status")
          lag_txns_column = columns.index("lag_txns")

          rows.each do |values|
            table_name = values[table_name_column]
            wal_pending_row_count = values[wal_pending_row_count_column].to_i
            status = values[status_column]
            lag_txns = values[lag_txns_column].to_i

            if status != 'OK'
              @logger.error("QuestDB: #{table_name} in bad state: #{status}")

              if status == 'SUSPENDED'
                # Try to automatically unsuspend
                @logger.info("QuestDB: Attempting to unsuspend: #{table_name}")
                conn.exec("ALTER TABLE #{table_name} RESUME WAL;")
              end
            end

            @wal_pending_row_count[table_name] ||= []
            @wal_pending_row_count[table_name] << wal_pending_row_count
            @lag_txns[table_name] ||= []
            @lag_txns[table_name] << lag_txns

            if @wal_pending_row_count[table_name].length >= 3
              if @wal_pending_row_count[table_name][-1] > @wal_pending_row_count[table_name][-2] and @wal_pending_row_count[table_name][-2] > @wal_pending_row_count[table_name][-3]
                # Two sample periods of growth
                @logger.error("QuestDB: #{table_name} has growing wal_pending_row_count: #{wal_pending_row_count}")
              end

              # Leave the last two samples
              @wal_pending_row_count[table_name] = @wal_pending_row_count[table_name][-2..-1]
            end

            if @lag_txns[table_name].length >= 3
              if @lag_txns[table_name][-1] > @lag_txns[table_name][-2] and @lag_txns[table_name][-2] > @lag_txns[table_name][-3]
                # Two sample periods of growth
                @logger.error("QuestDB: #{table_name} has growing lag_txns: #{lag_txns}")
              end

              # Leave the last two samples
              @lag_txns[table_name] = @lag_txns[table_name][-2..-1]
            end
          end
        rescue => e
          OpenC3::QuestDBClient.disconnect
          @logger.error("QuestDB Error: #{e.formatted}")
        end
      end
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