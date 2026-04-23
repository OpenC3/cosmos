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

require 'fileutils'
require 'tmpdir'
require 'openc3/system/system'
require 'openc3/utilities/bucket'
require 'openc3/utilities/bucket_utilities'
require 'openc3/utilities/logger'
require 'openc3/utilities/questdb_client'
require 'openc3/logs/packet_log_reader'
require 'openc3/microservices/decom_common'
require 'openc3/models/reingest_job_model'

module OpenC3
  class ReingestJobError < StandardError; end

  # Replays raw .bin.gz log files from a bucket, decommutating each packet via
  # DecomCommon.decom_and_publish(check_limits: false) so historical data
  # reaches QuestDB without re-firing limits events.
  #
  # Runs synchronously (caller wraps in a Thread). Tracks state in a
  # ReingestJobModel. DEDUP is enabled on affected tables during the job and
  # disabled in an ensure block on completion (or after a cooldown window so
  # in-flight WAL commits are covered).
  #
  # target_version:
  #   - 'as_logged' (default): each file is decoded with the target config hash
  #     that was in effect when the packets were originally logged. Files are
  #     grouped by their embedded target_id and System is rebuilt per group.
  #   - 'current': all files are decoded with the latest target config.
  #   - <hash>: explicit hash, used for every file in the job.
  class ReingestJob
    # How often to persist progress during the ingest pass (write every N packets)
    STATUS_UPDATE_EVERY = 500
    # How often to tick the heartbeat during the cooldown sleep
    HEARTBEAT_INTERVAL_SEC = 10

    # Reingest rebuilds the process-global System singleton. Serialize all
    # reingest jobs running in this process so they don't stomp each other.
    @@run_mutex = Mutex.new

    def initialize(job_id:, files:, path:, bucket:, scope:,
                   target_version: 'as_logged',
                   dedup_cooldown_seconds: ENV.fetch('OPENC3_REINGEST_DEDUP_COOLDOWN', 60).to_i,
                   logger: Logger)
      @job_id = job_id
      @files = files
      @path = path
      @bucket_env = bucket
      @scope = scope
      @target_version = target_version
      @dedup_cooldown_seconds = dedup_cooldown_seconds
      @logger = logger
    end

    def run
      tmp_dir = Dir.mktmpdir
      job = load_job
      dedup_enabled_by_us = []
      @@run_mutex.synchronize do
        begin
          mark(job, state: 'Running', progress_phase: 'downloading',
               started_at: Time.now.utc.iso8601,
               progress_total: @files.length)

          local_files = download_and_uncompress(job, tmp_dir)

          # Pass 1: read raw (no System required) to discover table names and
          # each file's embedded target hash. File hashes are what the "as
          # logged" mode uses to pick the right target_version per file.
          mark(job, progress_phase: 'enabling_dedup', progress_current: 0,
               progress_total: 0)
          table_names, file_versions = discover_tables_and_versions(local_files)
          mark(job, table_names: table_names, progress_total: table_names.length)

          dedup_enabled_by_us, preexisting = enable_dedup(job, table_names)
          mark(job,
               dedup_enabled_by_us: dedup_enabled_by_us,
               dedup_preexisting: preexisting,
               dedup_enabled_at: Time.now.utc.iso8601)

          # Pass 2: group files by the target_version we'll load for them,
          # then ingest each group under its own System instance.
          groups = group_files_by_version(local_files, file_versions)
          mark(job, versions_used: groups.keys,
               progress_phase: 'ingesting', progress_current: 0,
               progress_total: 0, packets_written: 0)
          ingest_all_groups(job, groups)

          mark(job, progress_phase: 'dedup_cooldown')
          cooldown(job)

          mark(job, progress_phase: 'disabling_dedup')
          disabled = disable_dedup(job, dedup_enabled_by_us)
          mark(job, dedup_disabled_tables: disabled,
               dedup_disabled_at: Time.now.utc.iso8601,
               state: 'Complete',
               finished_at: Time.now.utc.iso8601)
        rescue Exception => e
          @logger.error("Reingest job #{@job_id} failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
          # Always try to revert DEDUP even on crash so user tables are not left altered
          disabled_on_crash = []
          begin
            disabled_on_crash = disable_dedup(job, dedup_enabled_by_us)
          rescue => de
            @logger.error("Reingest job #{@job_id} failed to disable DEDUP during crash cleanup: #{de.message}")
          end
          mark(job,
               dedup_disabled_tables: disabled_on_crash,
               dedup_disabled_at: Time.now.utc.iso8601,
               state: 'Crashed',
               error: e.message,
               finished_at: Time.now.utc.iso8601)
        ensure
          FileUtils.remove_entry_secure(tmp_dir, true) if tmp_dir && File.directory?(tmp_dir)
        end
      end
    end

    private

    def load_job
      ReingestJobModel.get_model(name: @job_id, scope: @scope) or
        raise ReingestJobError, "ReingestJobModel #{@job_id} not found in scope #{@scope}"
    end

    # Returns the target name embedded in the reingest path, e.g.
    # "DEFAULT/raw_logs/tlm/INST/20260421/" → "INST". Nil if the path
    # doesn't match the expected raw_logs layout.
    def target_from_path
      parts = @path.to_s.split('/').reject(&:empty?)
      return nil unless parts.length >= 4
      return nil unless parts[1] == 'raw_logs'
      parts[3]
    end

    # Merge attrs into the model and persist. Model#update refreshes updated_at,
    # which doubles as the heartbeat used by the stale-check.
    def mark(job, **attrs)
      attrs.each { |k, v| job.send("#{k}=", v) }
      job.update
    end

    def download_and_uncompress(job, tmp_dir)
      bucket_name = ENV.fetch(@bucket_env) { |name| raise ReingestJobError, "Unknown bucket #{name}" }
      bucket_client = Bucket.getClient()
      local_files = []
      @files.each_with_index do |filename, i|
        key = "#{@path}#{filename}"
        temp_file = File.join(tmp_dir, filename)
        FileUtils.mkdir_p(File.dirname(temp_file))
        bucket_client.get_object(bucket: bucket_name, key: key, path: temp_file)
        if File.extname(filename) == '.gz'
          decompressed = BucketUtilities.uncompress_file(temp_file)
          File.delete(temp_file)
          local_files << decompressed
        else
          local_files << temp_file
        end
        mark(job, progress_current: i + 1)
      end
      local_files
    end

    # Read each file in raw mode (identify_and_define=false) to collect
    # {scope}__TLM__{target}__{packet} table names and the first target
    # declaration hash embedded in each file. Returns [table_names, file_versions]
    # where file_versions maps local_file_path → hex hash (or nil if the file
    # has no hash, which happens for pre-6.x log files).
    def discover_tables_and_versions(local_files)
      table_names = Set.new
      file_versions = {}
      local_files.each do |local_file|
        reader = PacketLogReader.new
        reader.each(local_file, false) do |packet|
          next unless packet.target_name && packet.packet_name
          cmd_or_tlm = packet.cmd_or_tlm == :CMD ? 'CMD' : 'TLM'
          table_names.add("#{@scope}__#{cmd_or_tlm}__#{packet.target_name}__#{packet.packet_name}")
        end
        ids = reader.instance_variable_get(:@target_ids) || []
        file_versions[local_file] = ids.first ? ids.first.unpack1('H*') : nil
      end
      [table_names.to_a, file_versions]
    end

    # Returns a Hash of target_version → [local_file, ...]. The value at key
    # 'current' means "use System with the latest config"; any other value is
    # a specific hash string used as target_version in System.setup_targets.
    def group_files_by_version(local_files, file_versions)
      groups = Hash.new { |h, k| h[k] = [] }
      case @target_version
      when 'current'
        groups['current'] = local_files.dup
      when 'as_logged', nil
        local_files.each do |file|
          version = file_versions[file] || 'current'
          groups[version] << file
        end
      else
        # Caller passed an explicit hash; use it for every file.
        groups[@target_version] = local_files.dup
      end
      groups
    end

    # For each version group, rebuild System under that version and ingest
    # the group's files. `@@run_mutex` in `run` protects other threads from
    # seeing a transient nil @@instance.
    #
    # If the requested target archive (a specific hash) is missing from the
    # config bucket — which happens in dev setups where every `openc3.sh start`
    # regenerates the target archive with a fresh timestamp-appended gem
    # version — we fall back to 'current' and record a warning on the job so
    # the UI can surface it. This matters because the old historical archive
    # the log file references may no longer exist.
    def ingest_all_groups(job, groups)
      target = target_from_path
      packets_written = 0
      last_status_at = 0
      warnings = (job.warnings || []).dup
      groups.each do |version, files|
        if target
          resolved = load_system_with_fallback(target, version, warnings)
          unless resolved
            # Even the 'current' fallback failed; skip this group rather than
            # publish empty json_data for every packet.
            mark(job, warnings: warnings)
            next
          end
        end
        mark(job, warnings: warnings) if warnings.any?
        files.each do |file|
          packets_written, last_status_at = ingest_file(job, file, packets_written, last_status_at)
        end
      end
      mark(job, packets_written: packets_written, warnings: warnings)
    end

    # Returns the target_version that was actually loaded, or nil if even the
    # 'current' fallback failed. Appends human-readable entries to `warnings`
    # for any fallback or failure.
    def load_system_with_fallback(target, version, warnings)
      begin
        load_system(target, version)
        return version
      rescue => e
        if version == 'current'
          # Caller explicitly requested 'current' and that failed; no further
          # fallback exists — propagate so the outer rescue marks Crashed.
          raise
        end
        @logger.warn("Reingest job #{@job_id}: target archive for #{target} version '#{version}' unavailable (#{e.class}: #{e.message}); falling back to 'current'")
        warnings << "Version '#{version}' archive missing; used 'current' instead"
      end

      begin
        load_system(target, 'current')
        'current'
      rescue => e
        @logger.error("Reingest job #{@job_id}: fallback to 'current' also failed: #{e.class}: #{e.message}")
        warnings << "Version '#{version}' archive missing and 'current' also failed (#{e.message})"
        nil
      end
    end

    def load_system(target, version)
      System.reset_instance!
      System.setup_targets([target], Dir.tmpdir, scope: @scope, target_version: version)
    end

    def ingest_file(job, local_file, packets_written, last_status_at)
      reader = PacketLogReader.new
      reader.each(local_file, true) do |packet|
        next unless packet.target_name && packet.packet_name
        packet.stored = true
        DecomCommon.decom_and_publish(
          packet,
          scope: @scope,
          target_names: [packet.target_name],
          logger: @logger,
          name: "REINGEST:#{@job_id}",
          check_limits: false,
        )
        packets_written += 1
        if packets_written - last_status_at >= STATUS_UPDATE_EVERY
          mark(job, packets_written: packets_written)
          last_status_at = packets_written
        end
      end
      [packets_written, last_status_at]
    end

    # Returns [enabled_by_us, preexisting]. Only tables we enable are recorded
    # in enabled_by_us; pre-existing DEDUP tables are left untouched on teardown.
    def enable_dedup(job, table_names)
      enabled_by_us = []
      preexisting = []
      conn = QuestDBClient.connection
      table_names.each_with_index do |table_name, i|
        begin
          already = dedup_already_enabled?(conn, table_name)
          if already
            preexisting << table_name
          else
            conn.exec("ALTER TABLE '#{table_name}' DEDUP ENABLE UPSERT KEYS(PACKET_TIMESECONDS)")
            enabled_by_us << table_name
          end
        rescue => e
          @logger.warn("Failed to enable DEDUP on #{table_name}: #{e.message}")
        end
        mark(job, progress_current: i + 1)
      end
      [enabled_by_us, preexisting]
    end

    # QuestDB exposes per-table dedup status via tables() function.
    # Falls back to false (treat as not-enabled, will issue ALTER) on any error.
    def dedup_already_enabled?(conn, table_name)
      result = conn.exec_params(
        "SELECT dedup FROM tables() WHERE table_name = $1",
        [table_name],
      )
      return false if result.ntuples == 0
      value = result[0]['dedup']
      value == true || value == 't' || value.to_s.downcase == 'true'
    rescue => e
      @logger.warn("Could not query DEDUP status for #{table_name}: #{e.message}")
      false
    end

    # Sleep dedup_cooldown_seconds, ticking the heartbeat so the stale-check
    # doesn't misfire during the wait. This gives the Python TsdbMicroservice
    # and QuestDB WAL time to commit reingested rows while DEDUP is still on.
    def cooldown(job)
      remaining = @dedup_cooldown_seconds
      while remaining > 0
        step = [HEARTBEAT_INTERVAL_SEC, remaining].min
        sleep(step)
        remaining -= step
        mark(job) # heartbeat only
      end
    end

    def disable_dedup(job, tables)
      disabled = []
      conn = QuestDBClient.connection
      tables.each_with_index do |table_name, i|
        begin
          conn.exec("ALTER TABLE '#{table_name}' DEDUP DISABLE")
          disabled << table_name
        rescue => e
          @logger.warn("Failed to disable DEDUP on #{table_name}: #{e.message}")
        end
        mark(job, progress_current: i + 1, progress_total: tables.length)
      end
      disabled
    end
  end
end
