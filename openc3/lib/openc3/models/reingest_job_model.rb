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

require 'openc3/models/model'

module OpenC3
  # Tracks one run of OpenC3::ReingestJob. The job updates this record from a
  # background thread; the storage_controller status endpoint reads it.
  # `updated_at` doubles as the heartbeat — if a Running record hasn't been
  # touched in STALE_THRESHOLD_SEC, the status endpoint surfaces it as 'Stale'.
  class ReingestJobModel < Model
    PRIMARY_KEY = 'openc3_reingest_job'
    STALE_THRESHOLD_SEC = 60

    STATES = %w[Queued Running Complete Crashed Stale].freeze
    PHASES = %w[downloading enabling_dedup ingesting dedup_cooldown disabling_dedup].freeze

    attr_accessor :state
    attr_accessor :files
    attr_accessor :bucket
    attr_accessor :path
    attr_accessor :table_names
    attr_accessor :target_version
    attr_accessor :versions_used
    attr_accessor :warnings
    attr_accessor :progress_phase
    attr_accessor :progress_current
    attr_accessor :progress_total
    attr_accessor :packets_written
    attr_accessor :dedup_enabled_by_us
    attr_accessor :dedup_preexisting
    attr_accessor :dedup_disabled_tables
    attr_accessor :dedup_cooldown_seconds
    attr_accessor :dedup_enabled_at
    attr_accessor :dedup_disabled_at
    attr_accessor :error
    attr_accessor :started_at
    attr_accessor :finished_at

    def self.get(name:, scope:)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope:)
      all = super("#{scope}__#{PRIMARY_KEY}")
      all.sort_by { |_key, value| value['updated_at'] }.reverse
    end

    def initialize(
      name:,
      state: 'Queued',
      files: [],
      bucket: nil,
      path: nil,
      table_names: [],
      target_version: 'as_logged',
      versions_used: [],
      warnings: [],
      progress_phase: nil,
      progress_current: 0,
      progress_total: 0,
      packets_written: 0,
      dedup_enabled_by_us: [],
      dedup_preexisting: [],
      dedup_disabled_tables: [],
      dedup_cooldown_seconds: 60,
      dedup_enabled_at: nil,
      dedup_disabled_at: nil,
      error: nil,
      started_at: nil,
      finished_at: nil,
      updated_at: nil,
      plugin: nil,
      scope:
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      @state = state
      @files = files
      @bucket = bucket
      @path = path
      @table_names = table_names
      @target_version = target_version
      @versions_used = versions_used
      @warnings = warnings
      @progress_phase = progress_phase
      @progress_current = progress_current
      @progress_total = progress_total
      @packets_written = packets_written
      @dedup_enabled_by_us = dedup_enabled_by_us
      @dedup_preexisting = dedup_preexisting
      @dedup_disabled_tables = dedup_disabled_tables
      @dedup_cooldown_seconds = dedup_cooldown_seconds
      @dedup_enabled_at = dedup_enabled_at
      @dedup_disabled_at = dedup_disabled_at
      @error = error
      @started_at = started_at
      @finished_at = finished_at
    end

    # True if state is Running but the heartbeat (updated_at) is older than
    # STALE_THRESHOLD_SEC. Callers should surface state as 'Stale' in that case.
    def stale?
      return false unless @state == 'Running'
      return false unless @updated_at
      age_nsec = Time.now.to_nsec_from_epoch - @updated_at.to_i
      age_nsec > STALE_THRESHOLD_SEC * 1_000_000_000
    end

    def as_json(*_a)
      {
        'name' => @name,
        'state' => stale? ? 'Stale' : @state,
        'files' => @files,
        'bucket' => @bucket,
        'path' => @path,
        'table_names' => @table_names,
        'target_version' => @target_version,
        'versions_used' => @versions_used,
        'warnings' => @warnings,
        'progress_phase' => @progress_phase,
        'progress_current' => @progress_current,
        'progress_total' => @progress_total,
        'packets_written' => @packets_written,
        'dedup_enabled_by_us' => @dedup_enabled_by_us,
        'dedup_preexisting' => @dedup_preexisting,
        'dedup_disabled_tables' => @dedup_disabled_tables,
        'dedup_cooldown_seconds' => @dedup_cooldown_seconds,
        'dedup_enabled_at' => @dedup_enabled_at,
        'dedup_disabled_at' => @dedup_disabled_at,
        'error' => @error,
        'started_at' => @started_at,
        'finished_at' => @finished_at,
        'updated_at' => @updated_at,
        'plugin' => @plugin,
        'scope' => @scope,
      }
    end
  end
end
