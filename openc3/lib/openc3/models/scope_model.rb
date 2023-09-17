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
    attr_accessor :text_log_cycle_time
    attr_accessor :text_log_cycle_size
    attr_accessor :text_log_retain_time
    attr_accessor :tool_log_retain_time
    attr_accessor :cleanup_poll_time

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
      self.new(**json.transform_keys(&:to_sym), scope: scope)
    end

    def self.get_model(name:, scope: nil)
      json = get(name: name)
      if json
        return from_json(json)
      else
        return nil
      end
    end

    def initialize(name:,
      text_log_cycle_time: 600,
      text_log_cycle_size: 50_000_000,
      text_log_retain_time: nil,
      tool_log_retain_time: nil,
      cleanup_poll_time: 900,
      updated_at: nil,
      scope: nil
    )
      super(
        PRIMARY_KEY,
        name: name,
        text_log_cycle_time: text_log_cycle_time,
        text_log_cycle_size: text_log_cycle_size,
        text_log_retain_time: text_log_retain_time,
        tool_log_retain_time: tool_log_retain_time,
        cleanup_poll_time: cleanup_poll_time,
        updated_at: updated_at,
        scope: name
      )
      @text_log_cycle_time = text_log_cycle_time
      @text_log_cycle_size = text_log_cycle_size
      @text_log_retain_time = text_log_retain_time
      @tool_log_retain_time = tool_log_retain_time
      @cleanup_poll_time = cleanup_poll_time
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
        'updated_at' => @updated_at,
        'text_log_cycle_time' => @text_log_cycle_time,
        'text_log_cycle_size' => @text_log_cycle_size,
        'text_log_retain_time' => @text_log_retain_time,
        'tool_log_retain_time' => @tool_log_retain_time,
        'cleanup_poll_time' => @cleanup_poll_time,
       }
    end

    def deploy_openc3_log_messages_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__OPENC3__LOG"
      topics = ["#{@scope}__openc3_log_messages"]
      # Also log the NOSCOPE messages with this microservice for the DEFAULT scope
      if @scope == 'DEFAULT'
        topics << "NOSCOPE__openc3_log_messages"
      end
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "text_log_microservice.rb", microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [
          ["CYCLE_TIME", @text_log_cycle_time],
          ["CYCLE_SIZE", @text_log_cycle_size],
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

    def deploy_scopecleanup_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__SCOPECLEANUP__#{@scope}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "scope_cleanup_microservice.rb", microservice_name],
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

      @parent = "#{@scope}__SCOPEMULTI__#{@scope}"

      # OpenC3 Log Microservice
      deploy_openc3_log_messages_microservice(gem_path, variables, @parent)

      # UNKNOWN CommandLog Microservice
      deploy_unknown_commandlog_microservice(gem_path, variables, @parent)

      # UNKNOWN PacketLog Microservice
      deploy_unknown_packetlog_microservice(gem_path, variables, @parent)

      # Periodic Microservice
      deploy_periodic_microservice(gem_path, variables, @parent)

      # Scope Cleanup Microservice
      deploy_scopecleanup_microservice(gem_path, variables, @parent)

      # Multi Microservice to parent other scope microservices
      deploy_scopemulti_microservice(gem_path, variables)
    end

    def undeploy
      model = MicroserviceModel.get_model(name: "#{@scope}__SCOPEMULTI__#{@scope}", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__SCOPECLEANUP__#{@scope}", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__OPENC3__LOG", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__COMMANDLOG__UNKNOWN", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__PACKETLOG__UNKNOWN", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__PERIODIC__#{@scope}", scope: @scope)
      model.destroy if model
      model = MicroserviceModel.get_model(name: "#{@scope}__TRIGGER_GROUP__DEFAULT", scope: @scope)
      model.destroy if model

      # Delete the topics we created for the scope
      Topic.del("#{@scope}__COMMAND__{UNKNOWN}__UNKNOWN")
      Topic.del("#{@scope}__TELEMETRY__{UNKNOWN}__UNKNOWN")
      Topic.del("#{@scope}__openc3_targets")
      Topic.del("#{@scope}__CONFIG")
      Topic.del("#{@scope}__openc3_autonomic")
      Topic.del("#{@scope}__TRIGGER__GROUP")
    end

    def seed_database
      setting = SettingModel.get(name: 'source_url')
      SettingModel.set({ name: 'source_url', data: 'https://github.com/OpenC3/cosmos' }, scope: @scope) unless setting
      setting = SettingModel.get(name: 'rubygems_url')
      SettingModel.set({ name: 'rubygems_url', data: 'https://rubygems.org' }, scope: @scope) unless setting
    end
  end
end
