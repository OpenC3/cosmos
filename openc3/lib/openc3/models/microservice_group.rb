# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'securerandom'
require 'openc3/models/microservice_model'
require 'openc3/utilities/store'

module OpenC3
  # Targets that declare MICROSERVICE_GROUP <NAME> keep their own target
  # microservices (DECOM, COMMANDLOG, PACKETLOG, CLEANUP, TSDB) but run them as
  # threads in two shared processes instead of one or more processes per target:
  #
  # - SCOPE__MULTIGROUP__<NAME> runs the Ruby microservices (multi_microservice.rb)
  # - SCOPE__PYMULTIGROUP__<NAME> runs the Python microservices, TSDB and the
  #   decom of Python targets (multi_microservice.py)
  #
  # A target microservice joins a group by naming one of these as its parent.
  # The parents find their children by that when they start, and the operator
  # restarts a parent when a child is added, changed, or removed, so the parents
  # themselves only change when they are first needed or no longer needed.
  class MicroserviceGroup
    RUBY_TYPE = 'MULTIGROUP'
    PYTHON_TYPE = 'PYMULTIGROUP'
    TYPES = [RUBY_TYPE, PYTHON_TYPE]

    LOCK_TIMEOUT_SECONDS = 60
    LOCK_EXPIRE_SECONDS = 120

    def self.microservice_name(type, group, scope:)
      "#{scope}__#{type}__#{group}"
    end

    # @return [Array<Hash>] TargetModel JSON of the other members of the group
    def self.members(group, scope:, exclude: nil)
      TargetModel.all(scope: scope).values.select do |target|
        target['microservice_group'] == group and target['name'] != exclude
      end
    end

    # Raise if the target can't join its group. Called before anything is
    # written so a failed install leaves the group as it was.
    # @param target [TargetModel] Target being deployed
    def self.validate_member(target)
      group = target.microservice_group
      unless target.target_microservices.empty?
        raise "Target #{target.name} cannot use both MICROSERVICE_GROUP and TARGET_MICROSERVICE"
      end

      members(group, scope: target.scope, exclude: target.name).each do |member|
        if member['db_shard'].to_i != target.db_shard
          raise "Target #{target.name} has DB_SHARD #{target.db_shard} but microservice group #{group} uses DB_SHARD #{member['db_shard'].to_i} (target #{member['name']})"
        end
        if member['shard'].to_i != target.shard
          raise "Target #{target.name} has SHARD #{target.shard} but microservice group #{group} uses SHARD #{member['shard'].to_i} (target #{member['name']})"
        end
        # The Python process can only use one plugin's Python packages
        if target.language == 'python' and member['language'] == 'python' and member['plugin'] != target.plugin
          raise "Target #{target.name} uses Python decom but microservice group #{group} already has Python decom target #{member['name']} from another plugin (#{member['plugin']})"
        end
      end
    end

    # Create, update, or remove the group's parent microservices so that each
    # one exists only while it has children. Called after a member's
    # microservices are deployed or removed.
    def self.update(group, scope:)
      with_lock(group, scope: scope) do
        microservices = MicroserviceModel.all(scope: scope)
        TYPES.each do |type|
          name = microservice_name(type, group, scope: scope)
          children = microservices.values.select { |config| config['parent'] == name }.sort_by { |config| config['name'] }
          existing = microservices[name]
          if children.empty?
            if existing
              MicroserviceModel.get_model(name: name, scope: scope)&.destroy
              Logger.info "Removed microservice #{name} for microservice group #{group}"
            end
            next
          end
          model = build_model(type, name, children, scope: scope)
          if existing
            next if same_config?(existing, model.as_json)

            model.update
            Logger.info "Updated microservice #{name} for microservice group #{group}"
          else
            model.create
            Logger.info "Configured microservice #{name} for microservice group #{group}"
          end
        end
      end
    end

    # The parent takes its settings from its children. They all have the same
    # shard and db_shard (see validate_member).
    def self.build_model(type, name, children, scope:)
      needs_dependencies = children.any? { |child| child['needs_dependencies'] }
      if type == RUBY_TYPE
        cmd = ['ruby', 'multi_microservice.rb']
        work_dir = '/openc3/lib/openc3/microservices'
        plugin = nil
      else
        cmd = [ENV['OPENC3_PYTHON_BIN'] || '/openc3/python/.venv/bin/python', 'multi_microservice.py']
        work_dir = '/openc3/python/openc3/microservices'
        # The operator picks the Python virtual environment by plugin, so use
        # the plugin of the Python decom targets (all one plugin, see
        # validate_member). Other parents have no plugin so that removing one
        # member's plugin doesn't remove the parent of the other members.
        plugin = children.find { |child| child['cmd'].include?('decom_microservice.py') }&.dig('plugin')
      end
      MicroserviceModel.new(name: name, cmd: cmd, work_dir: work_dir, plugin: plugin,
                            needs_dependencies: needs_dependencies, shard: children[0]['shard'].to_i,
                            db_shard: children[0]['db_shard'].to_i, scope: scope)
    end

    # Ignore updated_at which changes on every write
    def self.same_config?(existing, desired)
      strip = ->(config) { JSON.parse(JSON.generate(config, allow_nan: true), allow_nan: true).reject { |key, _| key == 'updated_at' } }
      strip.call(existing) == strip.call(desired)
    end

    # Serialize updates of one group. Concurrent plugin installs would otherwise
    # each read, modify, and write the same parent models.
    def self.with_lock(group, scope:)
      key = "#{scope}__microservice_group_lock__#{group}"
      token = SecureRandom.uuid
      deadline = Time.now + LOCK_TIMEOUT_SECONDS
      until Store.set(key, token, nx: true, ex: LOCK_EXPIRE_SECONDS)
        raise "Timeout waiting for microservice group #{group} lock" if Time.now > deadline

        sleep 0.1
      end
      begin
        yield
      ensure
        # Only release the lock if it's still ours (it may have expired)
        Store.del(key) if Store.get(key) == token
      end
    end
  end
end
