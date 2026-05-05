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
  # Tracks per-version lifecycle facets for a script. The UI surfaces these as
  # three badges (validated, reviewed, executed) that start greyed out and
  # fill in as each facet acquires data.
  #
  # Per-version record shape:
  #   saved_by, saved_at         — base metadata, set on every save
  #   validated: { passed, errors, at, by } | nil
  #   reviewed:  { by, notes, at }          | nil
  #   executions: [ { by, at, disconnect, environment, suite_runner, running_script_id } ]
  #   tainted, tainted_from_version_id, tainted_from_reviewed_by — provenance
  #     flags set when a save overrides a previously reviewed version
  #   restored_from_version_id   — set when this version was created via restore
  #
  # Final execution status (completed / completed_errors / stopped / etc.) is
  # NOT denormalized into the lifecycle — the frontend dereferences the linked
  # running_script_id against ScriptStatusModel to display live status on the
  # executed badge. Avoids cross-process writes from the spawned RunningScript.
  #
  # Stored under key "#{scope}__script-lifecycle", one hash field per script
  # name. The field value is a JSON document holding a `versions` map keyed by
  # S3 VersionId.
  class ScriptLifecycleModel < Model
    PRIMARY_KEY = 'script-lifecycle'

    attr_accessor :versions, :latest_version_id

    def self.get(name:, scope:)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.from_json(json, scope:)
      json = JSON.parse(json, allow_nan: true, create_additions: true) if String === json
      raise "json data is nil" if json.nil?
      self.new(**json.transform_keys(&:to_sym), scope: scope)
    end

    # Returns the model for this script, building an empty one in memory (not
    # yet persisted) if no entry exists.
    def self.get_or_build(name:, scope:)
      existing = get(name: name, scope: scope)
      return from_json(existing, scope: scope) if existing
      self.new(name: name, scope: scope)
    end

    def initialize(
      name:,
      scope:,
      versions: nil,
      latest_version_id: nil,
      updated_at: nil,
      plugin: nil
    )
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, plugin: plugin, scope: scope)
      @versions = versions || {}
      @latest_version_id = latest_version_id
    end

    def as_json(*_a)
      {
        'name' => @name,
        'versions' => @versions,
        'latest_version_id' => @latest_version_id,
        'updated_at' => @updated_at,
        'scope' => @scope
      }
    end

    # Derived primary state used for the UI badge color. Each badge is
    # independently rendered from its own block in the record, but for places
    # that need a single string (logs, list views) we fold the most-advanced
    # facet into a primary state.
    def state_of(version_id)
      rec = @versions[version_id]
      return 'unknown' unless rec
      return 'executed' if rec['executions']&.any?
      return 'reviewed' if rec['reviewed']
      return 'validated' if rec['validated']
      'unknown'
    end

    def latest_state
      state_of(@latest_version_id)
    end

    # Reviewed = read-only. Saving over the latest version requires force_taint.
    def locked_for_review?
      rec = latest_record
      !!(rec && rec['reviewed'])
    end

    def latest_record
      @latest_version_id ? @versions[@latest_version_id] : nil
    end

    # Record a fresh save. New version becomes the latest.
    def record_save(version_id:, username:, timestamp: nil)
      timestamp ||= Time.now.utc.iso8601
      rec = @versions[version_id] ||= {}
      rec['saved_by'] = username
      rec['saved_at'] = timestamp
      @latest_version_id = version_id
      persist
      self
    end

    # Save that overrides a previously reviewed version. Tainted with provenance.
    # Review of a tainted version cleans it (state derives from the reviewed
    # block; the tainted flag is preserved as historical fact).
    def record_taint(version_id:, username:, prev_version_id:, prev_reviewer:, timestamp: nil)
      timestamp ||= Time.now.utc.iso8601
      rec = @versions[version_id] ||= {}
      rec['saved_by'] = username
      rec['saved_at'] = timestamp
      rec['tainted'] = true
      rec['tainted_from_version_id'] = prev_version_id
      rec['tainted_from_reviewed_by'] = prev_reviewer
      @latest_version_id = version_id
      persist
      self
    end

    # Record a syntax + mnemonic check result. Re-validation overwrites the
    # prior validated block; the latest result wins.
    # @param errors [Array<String>] human-readable error lines (empty when passed=true)
    def record_validation(version_id:, passed:, errors: [], username: nil, timestamp: nil)
      return self unless @versions[version_id]
      timestamp ||= Time.now.utc.iso8601
      @versions[version_id]['validated'] = {
        'passed' => passed,
        'errors' => errors || [],
        'at' => timestamp,
        'by' => username
      }
      persist
      self
    end

    # Record sign-off. Latest reviewer wins (reviews can happen multiple times).
    def record_review(version_id:, username:, notes: nil, timestamp: nil)
      return self unless @versions[version_id]
      timestamp ||= Time.now.utc.iso8601
      @versions[version_id]['reviewed'] = {
        'by' => username,
        'notes' => notes,
        'at' => timestamp
      }
      persist
      self
    end

    # Record an execution with the launch settings. Final status is not stored
    # here — the UI dereferences running_script_id against ScriptStatusModel
    # to show live status on the executed badge.
    def record_execution(version_id:, username:, disconnect: false, environment: nil, suite_runner: nil, running_script_id: nil, timestamp: nil)
      return self unless @versions[version_id]
      timestamp ||= Time.now.utc.iso8601
      @versions[version_id]['executions'] ||= []
      @versions[version_id]['executions'] << {
        'by' => username,
        'at' => timestamp,
        'disconnect' => disconnect,
        'environment' => environment,
        'suite_runner' => suite_runner,
        'running_script_id' => running_script_id
      }
      persist
      self
    end

    # Restore: a new version_id created by re-PUTting the body of a prior version.
    def record_restore(version_id:, username:, restored_from_version_id:, timestamp: nil)
      timestamp ||= Time.now.utc.iso8601
      rec = @versions[version_id] ||= {}
      rec['saved_by'] = username
      rec['saved_at'] = timestamp
      rec['restored_from_version_id'] = restored_from_version_id
      @latest_version_id = version_id
      persist
      self
    end

    # Persist current state. Upsert semantics — first call inserts, subsequent
    # calls overwrite.
    def persist
      create(force: true)
    end
  end
end
