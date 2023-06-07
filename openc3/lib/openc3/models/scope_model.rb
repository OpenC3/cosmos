# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/version'
require 'openc3/models/model'
require 'openc3/models/plugin_model'
require 'openc3/models/microservice_model'
require 'openc3/models/setting_model'
require 'openc3/models/trigger_group_model'

module OpenC3
  class ScopeModel < Model
    PRIMARY_KEY = 'openc3_scopes'

    attr_accessor :children

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope: nil)
      super(PRIMARY_KEY, name: name)
    end

    def self.names(scope: nil)
      super(PRIMARY_KEY)
    end

    def self.all(scope: nil)
      super(PRIMARY_KEY)
    end

    def self.from_json(json, scope: nil)
      json = JSON.parse(json, :allow_nan => true, :create_additions => true) if String === json
      raise "json data is nil" if json.nil?

      json.transform_keys!(&:to_sym)
      self.new(**json, scope: scope)
    end

    def self.get_model(name:, scope: nil)
      json = get(name: name)
      if json
        return from_json(json)
      else
        return nil
      end
    end

    def initialize(name:, updated_at: nil, scope: nil)
      super(PRIMARY_KEY, name: name, scope: name, updated_at: updated_at)
      @children = []
    end

    def create(update: false, force: false)
      # Ensure there are no "." in the scope name - prevents gems accidently becoming scope names
      raise "Invalid scope name: #{@name}" if @name !~ /^[a-zA-Z0-9_-]+$/
      @name = @name.upcase
      super(update: update, force: force)
    end

    def destroy
      if @name != 'DEFAULT'
        # Remove all the plugins for this scope
        plugins = PluginModel.get_all_models(scope: @name)
        plugins.each do |plugin_name, plugin|
          plugin.destroy
        end
        super()
      else
        raise "DEFAULT scope cannot be destroyed"
      end
    end

    def as_json(*a)
      { 'name' => @name,
        'updated_at' => @updated_at }
    end

    def deploy_openc3_log_messages_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__OPENC3__LOG"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "text_log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          # The following options are optional (600 and 50_000_000 are the defaults)
          # ["CYCLE_TIME", "600"], # Keep at most 10 minutes per log
          # ["CYCLE_SIZE", "50_000_000"] # Keep at most ~50MB per log
        ],
        topics: ["#{@scope}__openc3_log_messages"],
        parent: parent,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_openc3_notifications_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__NOTIFICATION__LOG"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "text_log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          # The following options are optional (600 and 50_000_000 are the defaults)
          ["CYCLE_TIME", "3600"], # Keep at most 1 hour per log
        ],
        topics: ["#{@scope}__openc3_notifications"],
        parent: parent,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_unknown_commandlog_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__COMMANDLOG__UNKNOWN"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["RAW_OR_DECOM", "RAW"],
          ["CMD_OR_TLM", "CMD"],
          ["CYCLE_TIME", "3600"], # Keep at most 1 hour per log
        ],
        topics: ["#{@scope}__COMMAND__{UNKNOWN}__UNKNOWN"],
        target_names: [],
        parent: parent,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_unknown_packetlog_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__PACKETLOG__UNKNOWN"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["RAW_OR_DECOM", "RAW"],
          ["CMD_OR_TLM", "TLM"],
          ["CYCLE_TIME", "3600"], # Keep at most 1 hour per log
        ],
        topics: ["#{@scope}__TELEMETRY__{UNKNOWN}__UNKNOWN"],
        target_names: [],
        parent: parent,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_periodic_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__PERIODIC__#{@scope}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "periodic_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        parent: parent,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_scopemulti_microservice(gem_path, variables)
      microservice_name = "#{@scope}__SCOPEMULTI__#{@scope}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "multi_microservice.rb", *@children],
        work_dir: '/openc3/lib/openc3/microservices',
        target_names: [],
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy(gem_path, variables)
      seed_database()

      # Create DEFAULT trigger group model
      model = TriggerGroupModel.get(name: 'DEFAULT', scope: @scope)
      unless model
        model = TriggerGroupModel.new(name: 'DEFAULT', scope: @scope)
        model.create()
        model.deploy()
      end

      # Create UNKNOWN target for display of unknown data
      model = TargetModel.new(name: "UNKNOWN", scope: @scope)
      model.create
      # Not deployed - we only want raw packet logging for UNKNOWN
      # TODO: Cleanup support

      @parent = "#{@scope}__SCOPEMULTI__#{@scope}"

      # OpenC3 Log Microservice
      deploy_openc3_log_messages_microservice(gem_path, variables, @parent)

      # Notification Log Microservice
      deploy_openc3_notifications_microservice(gem_path, variables, @parent)

      # UNKNOWN CommandLog Microservice
      deploy_unknown_commandlog_microservice(gem_path, variables, @parent)

      # UNKNOWN PacketLog Microservice
      deploy_unknown_packetlog_microservice(gem_path, variables, @parent)

      # Periodic Microservice
      deploy_periodic_microservice(gem_path, variables, @parent)

      # Multi Microservice to parent other scope microservices
      deploy_scopemulti_microservice(gem_path, variables)
    end

    def undeploy
      model = MicroserviceModel.get_model(name: "#{@scope}__SCOPEMULTI__#{@scope}", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__OPENC3__LOG", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__NOTIFICATION__LOG", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__COMMANDLOG__UNKNOWN", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__PACKETLOG__UNKNOWN", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__PERIODIC__#{@scope}", scope: @scope)
      model.destroy if model
      # Delete the topics we created for the scope
      Topic.del("#{@scope}__COMMAND__{UNKNOWN}__UNKNOWN")
      Topic.del("#{@scope}__TELEMETRY__{UNKNOWN}__UNKNOWN")
      Topic.del("#{@scope}__openc3_targets")
      Topic.del("#{@scope}__CONFIG")
    end

    def seed_database
      setting = SettingModel.get(name: 'source_url')
      SettingModel.set({ name: 'source_url', data: 'https://github.com/OpenC3/cosmos' }, scope: @scope) unless setting
      setting = SettingModel.get(name: 'rubygems_url')
      SettingModel.set({ name: 'rubygems_url', data: 'https://rubygems.org' }, scope: @scope) unless setting
    end
  end
end
