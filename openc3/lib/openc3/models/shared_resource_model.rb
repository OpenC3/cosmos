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

require 'json'
require 'securerandom'
require 'time'
require 'openc3/utilities/store'
require 'openc3/utilities/logger'

module OpenC3
  # A shared resource is something (typically expensive hardware) that is
  # defined in multiple scopes but may only be active in one scope at a time.
  # Interfaces, routers, microservices, and targets join a shared resource with
  # the SHARED_RESOURCE keyword. All the members in the owning scope run
  # normally. Members in other scopes are installed but dormant: the operator
  # does not spawn their microservices and commands to their targets are
  # rejected.
  #
  # Records live in a single global (not scoped) hash on db_shard 0:
  #   {
  #     'name' => 'CHAMBER',
  #     'owner' => 'DEFAULT',      # Scope currently owning the resource (nil if unowned)
  #     'state' => 'ACTIVE',       # ACTIVE or RELEASING
  #     'to' => nil,               # Scope taking ownership when RELEASING (nil to release)
  #     'waiting' => [],           # Owner's process members ({name, shard}) not yet confirmed stopped when RELEASING
  #     'members' => { 'DEFAULT' => [{ 'type' => 'INTERFACE', 'name' => 'DEFAULT__INTERFACE__INT', 'shard' => 0 }] },
  #     'requested_at' => nil,     # When the RELEASING handoff started
  #     'updated_at' => '...'
  #   }
  #
  # Switching ownership is a handoff: the record goes to RELEASING with a snapshot
  # of the old owner's process members (waiting). The operator for each member's
  # shard stops it and confirms it stopped (acknowledge). Once none are waiting,
  # ownership moves to the new scope. This guarantees the resource's
  # microservices never run in two scopes at the same time.
  class SharedResourceModel
    PRIMARY_KEY = 'openc3_shared_resources'
    LOCK_KEY = 'openc3_shared_resources__lock'
    LOCK_TIMEOUT_MS = 10_000
    LOCK_WAIT_SECONDS = 15.0
    CACHE_TIMEOUT = 1.0
    ACTIVE = 'ACTIVE'
    RELEASING = 'RELEASING'
    # Member types backed by a microservice process
    PROCESS_TYPES = %w(INTERFACE ROUTER MICROSERVICE)
    MEMBER_TYPES = PROCESS_TYPES + ['TARGET']

    @@cache = nil
    @@cache_time = nil
    @@cache_mutex = Mutex.new

    # Shared resources span scopes so they are always stored on db_shard 0
    def self.store
      Store.instance(db_shard: 0)
    end

    # @return [String] Upcased resource name
    def self.validate_name(name)
      name = name.to_s.upcase
      if name !~ /\A[A-Z0-9_]+\z/ or name.include?('__')
        raise "Invalid shared resource name '#{name}'. Must only contain letters, numbers, and single underscores."
      end
      name
    end

    # @return [Hash|nil] The shared resource record
    def self.get(name)
      json = store.hget(PRIMARY_KEY, name.to_s.upcase)
      json ? JSON.parse(json, allow_nan: true) : nil
    end

    # @return [Array<String>] All shared resource names
    def self.names
      store.hkeys(PRIMARY_KEY).sort
    end

    # @return [Hash<String, Hash>] All shared resource records keyed by name
    def self.all
      result = {}
      store.hgetall(PRIMARY_KEY).each do |name, json|
        result[name] = JSON.parse(json, allow_nan: true)
      end
      result
    end

    # Like all but cached for CACHE_TIMEOUT seconds. Used on hot paths like cmd.
    def self.all_cached
      @@cache_mutex.synchronize do
        if @@cache.nil? or @@cache_time.nil? or (Time.now - @@cache_time) > CACHE_TIMEOUT
          @@cache = all()
          @@cache_time = Time.now
        end
        @@cache
      end
    end

    def self.clear_cache
      @@cache_mutex.synchronize do
        @@cache = nil
        @@cache_time = nil
      end
    end

    # Add a member to a shared resource. The first member to create the resource
    # claims ownership for its scope. Later members (in any scope) join without
    # changing ownership, so reinstalling or upgrading a plugin keeps its scope's
    # ownership.
    #
    # @return [Hash] The updated record
    # @param shard [Integer] Operator shard running the member's microservice
    def self.add_member(name, scope:, type:, member_name:, shard: 0)
      name = validate_name(name)
      type = type.to_s.upcase
      raise "Invalid shared resource member type '#{type}'" unless MEMBER_TYPES.include?(type)
      with_lock do
        record = get(name)
        unless record
          record = new_record(name, owner: scope)
          Logger.info("Shared resource #{name} created and is active in scope #{scope}", scope: scope)
        end
        members = (record['members'][scope] ||= [])
        members.reject! { |member| member['type'] == type and member['name'] == member_name }
        member = { 'type' => type, 'name' => member_name }
        member['shard'] = shard.to_i if PROCESS_TYPES.include?(type)
        members << member
        save(record)
        record
      end
    end

    # Remove a member from a shared resource. Ownership is kept even if the owning
    # scope has no members left (it may be mid plugin upgrade). The record is
    # deleted once no scope has any members. A pending handoff still waits for a
    # removed member's process to be confirmed stopped.
    #
    # @return [Hash|nil] The updated record or nil if it was deleted
    def self.remove_member(name, scope:, type:, member_name:)
      name = name.to_s.upcase
      type = type.to_s.upcase
      with_lock do
        record = get(name)
        return nil unless record

        members = record['members'][scope]
        if members
          members.reject! { |member| member['type'] == type and member['name'] == member_name }
          record['members'].delete(scope) if members.empty?
        end
        if record['members'].empty? and (record['waiting'] || []).empty?
          store.hdel(PRIMARY_KEY, name)
          Logger.info("Shared resource #{name} deleted because it has no members", scope: scope)
          return nil
        end
        # Can't switch to a scope that no longer has members
        record['to'] = nil if record['to'] and !record['members'][record['to']]
        save(record)
        record
      end
    end

    # Switch the shared resource to be active in to_scope. If the current owner
    # has running microservices this starts a handoff (RELEASING) which the
    # operator completes once they have stopped.
    #
    # @param force [Boolean] Complete the switch immediately without waiting for
    #   the old owner's microservices to be confirmed stopped
    # @return [Hash] The updated record
    def self.switch(name, to_scope:, force: false)
      name = name.to_s.upcase
      with_lock do
        record = get(name)
        raise "Shared resource '#{name}' does not exist" unless record
        unless record['members'][to_scope]
          raise "Shared resource '#{name}' has no members in scope '#{to_scope}'"
        end
        return record if record['state'] == ACTIVE and record['owner'] == to_scope

        start_release(record, to_scope, force)
        save(record)
        record
      end
    end

    # Release the shared resource so it is not active in any scope
    #
    # @param force (see #switch)
    # @return [Hash] The updated record
    def self.release(name, force: false)
      name = name.to_s.upcase
      with_lock do
        record = get(name)
        raise "Shared resource '#{name}' does not exist" unless record
        return record if record['state'] == ACTIVE and record['owner'].nil?

        start_release(record, nil, force)
        save(record)
        record
      end
    end

    # Called by the operator to confirm that waiting process members have
    # stopped. Completes the handoff once none are waiting.
    #
    # @param member_names [Array<String>] Microservice names confirmed stopped
    # @return [Hash|nil] The updated record or nil if not releasing
    def self.acknowledge(name, member_names)
      with_lock do
        record = get(name)
        return nil unless record and record['state'] == RELEASING

        record['waiting'] = (record['waiting'] || []).reject { |member| member_names.include?(member['name']) }
        if record['waiting'].empty?
          if record['members'].empty?
            # Every member was uninstalled during the handoff
            store.hdel(PRIMARY_KEY, record['name'])
            return nil
          end
          to_scope = record['to']
          to_scope = nil if to_scope and !record['members'][to_scope]
          finish_release(record, to_scope)
        end
        save(record)
        record
      end
    end

    # @return [Boolean] Whether members of the resource in scope may be active
    def self.active?(record, scope)
      return false unless record
      record['state'] == ACTIVE and record['owner'] == scope
    end

    # @return [Array<Hash>] The process (microservice) members in scope
    def self.process_members(record, scope)
      return [] unless scope
      (record['members'][scope] || []).select { |member| PROCESS_TYPES.include?(member['type']) }
    end

    # @return [Hash|nil] Record of the shared resource the member belongs to (if any)
    def self.find_by_member(scope:, type:, member_name:, cached: true)
      records = cached ? all_cached() : all()
      records.each do |_name, record|
        members = record['members'][scope]
        next unless members
        return record if members.any? { |member| member['type'] == type and member['name'] == member_name }
      end
      nil
    end

    # Raise if the member is part of a shared resource that isn't active in scope
    #
    # @param description [String] Description of the member for the error message
    def self.check_active(scope:, type:, member_name:, description:)
      record = find_by_member(scope: scope, type: type, member_name: member_name)
      return if record.nil? or active?(record, scope)
      raise inactive_message(record, description)
    end

    # Raise if commands to the target can't be sent in scope
    def self.check_target_active(target_name, scope:)
      target_name = target_name.to_s.upcase
      check_active(scope: scope, type: 'TARGET', member_name: target_name, description: "Target #{target_name}")
    end

    # Raise if the interface or router isn't running in scope because of its shared resource
    #
    # @param type [String] INTERFACE or ROUTER
    def self.check_interface_active(type, name, scope:)
      name = name.to_s.upcase
      check_active(scope: scope, type: type, member_name: "#{scope}__#{type}__#{name}", description: "#{type.capitalize} #{name}")
    end

    # @return [String] Explanation of why the record isn't active
    def self.inactive_message(record, description)
      if record['state'] == RELEASING
        if record['to']
          "#{description} is part of shared resource #{record['name']} which is switching from scope #{record['owner']} to scope #{record['to']}"
        else
          "#{description} is part of shared resource #{record['name']} which is being released from scope #{record['owner']}"
        end
      elsif record['owner']
        "#{description} is part of shared resource #{record['name']} which is active in scope #{record['owner']}"
      else
        "#{description} is part of shared resource #{record['name']} which is not active in any scope"
      end
    end

    # Private helpers

    def self.new_record(name, owner:)
      {
        'name' => name,
        'owner' => owner,
        'state' => ACTIVE,
        'to' => nil,
        'waiting' => [],
        'members' => {},
        'requested_at' => nil,
        'updated_at' => nil,
      }
    end

    def self.save(record)
      record['updated_at'] = Time.now.utc.iso8601(6)
      store.hset(PRIMARY_KEY, record['name'], JSON.generate(record, allow_nan: true))
    end

    def self.start_release(record, to_scope, force)
      if record['state'] == RELEASING
        waiting = record['waiting'] || []
        unless force
          # Already handing off. Nothing new can start so just change the destination.
          record['to'] = to_scope
          Logger.info("Shared resource #{record['name']} releasing from scope #{record['owner']} now to #{to_scope || 'none'}")
          return
        end
      else
        waiting = process_members(record, record['owner']).map { |member| { 'name' => member['name'], 'shard' => member['shard'].to_i } }
      end
      # Nothing to wait for if the owner has no process members
      if force or waiting.empty?
        if force and !waiting.empty?
          Logger.warn("Shared resource #{record['name']} forced from scope #{record['owner']} to #{to_scope || 'none'} without waiting for its microservices to stop")
        end
        finish_release(record, to_scope)
      else
        record['state'] = RELEASING
        record['to'] = to_scope
        record['waiting'] = waiting
        record['requested_at'] = Time.now.utc.iso8601(6)
        Logger.info("Shared resource #{record['name']} releasing from scope #{record['owner']} to #{to_scope || 'none'}")
      end
    end

    def self.finish_release(record, to_scope)
      previous = record['owner']
      record['owner'] = to_scope
      record['state'] = ACTIVE
      record['to'] = nil
      record['waiting'] = []
      record['requested_at'] = nil
      Logger.info("Shared resource #{record['name']} switched from scope #{previous || 'none'} to #{to_scope || 'none'}")
    end

    # Serialize read-modify-write of the records across processes
    def self.with_lock
      token = SecureRandom.uuid
      start = Time.now
      until store.set(LOCK_KEY, token, nx: true, px: LOCK_TIMEOUT_MS)
        raise "Timeout waiting for shared resource lock" if (Time.now - start) > LOCK_WAIT_SECONDS
        sleep(0.05)
      end
      begin
        yield
      ensure
        store.del(LOCK_KEY) if store.get(LOCK_KEY) == token
        clear_cache()
      end
    end

    private_class_method :new_record, :save, :start_release, :finish_release, :with_lock
  end
end
