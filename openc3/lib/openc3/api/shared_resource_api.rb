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

require 'openc3/models/shared_resource_model'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'get_shared_resources',
                       'get_shared_resource',
                       'switch_shared_resource',
                       'release_shared_resource',
                     ])

    # Members in scopes the user can't access are left out
    # @return [Array<Hash>] The shared resources with members in the scope
    def get_shared_resources(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      records = SharedResourceModel.all.values.select { |record| record['members'][scope] }.sort_by { |record| record['name'] }
      accessible = { scope => true }
      records.map { |record| _shared_resource_for_user(record, accessible, manual: manual, token: token) }
    end

    # Members in scopes the user can't access are left out
    # @param name [String] Shared resource name
    # @return [Hash|nil] The shared resource or nil if it doesn't exist or has no members in the scope
    def get_shared_resource(name, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      record = SharedResourceModel.get(name)
      return nil unless record and record['members'][scope]
      _shared_resource_for_user(record, { scope => true }, manual: manual, token: token)
    end

    # Make a shared resource active in a scope. Its microservices in the
    # currently active scope are stopped before those in the new scope start.
    #
    # @param name [String] Shared resource name
    # @param to_scope [String] Scope to make the resource active in (default is the current scope)
    # @param force [Boolean] Don't wait for the active scope's microservices to stop
    # @return [Hash] The updated shared resource
    def switch_shared_resource(name, to_scope = nil, force: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      to_scope ||= scope
      # Switching affects both scopes so require admin in each
      authorize(permission: 'admin', manual: manual, scope: to_scope, token: token)
      record = SharedResourceModel.get(name)
      raise "Shared resource '#{name.to_s.upcase}' does not exist" unless record
      if record['owner'] and record['owner'] != to_scope
        authorize(permission: 'admin', manual: manual, scope: record['owner'], token: token)
      end
      record = SharedResourceModel.switch(name, to_scope: to_scope, force: force)
      username = user_info(token)['username'] || 'Anonymous'
      Logger.info("User #{username} switched shared resource #{record['name']} to scope #{to_scope}#{force ? ' (forced)' : ''}", scope: to_scope, user: username)
      record
    end

    # Release a shared resource so it is not active in any scope
    #
    # @param name [String] Shared resource name
    # @param force [Boolean] Don't wait for the active scope's microservices to stop
    # @return [Hash] The updated shared resource
    def release_shared_resource(name, force: false, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'admin', manual: manual, scope: scope, token: token)
      record = SharedResourceModel.get(name)
      raise "Shared resource '#{name.to_s.upcase}' does not exist" unless record
      if record['owner'] and record['owner'] != scope
        authorize(permission: 'admin', manual: manual, scope: record['owner'], token: token)
      end
      record = SharedResourceModel.release(name, force: force)
      username = user_info(token)['username'] || 'Anonymous'
      Logger.info("User #{username} released shared resource #{record['name']}#{force ? ' (forced)' : ''}", scope: scope, user: username)
      record
    end

    # Remove the members (and the owner's waiting members) of scopes the user
    # doesn't have system permission in. The owner and state stay so the UI can
    # say where the resource is active.
    # @param accessible [Hash<String, Boolean>] Cache of scope to whether the user can access it
    def _shared_resource_for_user(record, accessible, manual:, token:)
      can_access = lambda do |other_scope|
        unless accessible.key?(other_scope)
          begin
            authorize(permission: 'system', manual: manual, scope: other_scope, token: token)
            accessible[other_scope] = true
          rescue ForbiddenError
            accessible[other_scope] = false
          end
        end
        accessible[other_scope]
      end
      record = record.dup
      record['members'] = record['members'].select { |member_scope, _members| can_access.call(member_scope) }
      record['waiting'] = [] if record['owner'] and record['waiting'] and !can_access.call(record['owner'])
      record
    end
  end
end
