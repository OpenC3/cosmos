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
  # Tracks per-version lifecycle events for a script: when it was saved (and by
  # whom), when its syntax + mnemonic check passed, when it was reviewed/signed
  # off, and each time it was executed (with or without targets connected).
  # Also records taint provenance — when a reviewed version is overridden, the
  # next saved version is marked tainted with a pointer back to the prior
  # reviewed version + reviewer.
  #
  # Stored under key "#{scope}__script-lifecycle", one hash field per script
  # name. The field value is a JSON document that holds a `versions` map keyed
  # by S3 VersionId.
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
    # yet persisted) if no entry exists. Most transition recording flows want
    # this — they don't care whether a row already existed.
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

    # Derived primary state for a single version. A version that has been
    # reviewed counts as 'reviewed' even if executions happened later — those
    # are recorded as orthogonal events.
    def state_of(version_id)
      rec = @versions[version_id]
      return 'unknown' unless rec
      return 'reviewed' if rec['reviewed_at']
      return 'validated' if rec['validated_at']
      'new'
    end

    def latest_state
      state_of(@latest_version_id)
    end

    # True iff saving over this script should be refused unless the caller
    # explicitly opts into tainting. Reviewed = read-only.
    def locked_for_review?
      latest_state == 'reviewed'
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

    # Record a save that overrides a previously reviewed version. The new
    # version is flagged tainted with provenance back to the prior reviewer.
    # Review of a tainted version cleans it (caller invokes record_review
    # later — taint flag is preserved as historical fact, but state derivation
    # treats reviewed as authoritative).
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

    # Record that the syntax + mnemonic check passed for this version. Idempotent.
    def record_validation(version_id:, username: nil, timestamp: nil)
      return self unless @versions[version_id]
      timestamp ||= Time.now.utc.iso8601
      @versions[version_id]['validated_at'] = timestamp
      @versions[version_id]['validated_by'] = username if username
      persist
      self
    end

    # Record sign-off. Latest reviewer wins (reviews can happen multiple times).
    def record_review(version_id:, username:, notes: nil, timestamp: nil)
      return self unless @versions[version_id]
      timestamp ||= Time.now.utc.iso8601
      @versions[version_id]['reviewed_at'] = timestamp
      @versions[version_id]['reviewed_by'] = username
      @versions[version_id]['reviewed_notes'] = notes if notes
      persist
      self
    end

    # Append an execution event. type: 'executed' for connected runs,
    # 'executed_disconnect' for disconnect-mode runs.
    def record_execution(version_id:, username:, disconnect: false, timestamp: nil)
      return self unless @versions[version_id]
      timestamp ||= Time.now.utc.iso8601
      @versions[version_id]['executions'] ||= []
      @versions[version_id]['executions'] << {
        'type' => disconnect ? 'executed_disconnect' : 'executed',
        'username' => username,
        'at' => timestamp
      }
      persist
      self
    end

    # Record a restore operation: a new version_id was created by re-PUTting
    # the body of a prior version. The new version becomes latest.
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

    # Persist the current in-memory state. Upsert semantics — first call is an
    # insert, subsequent calls overwrite.
    def persist
      create(force: true)
    end
  end
end
