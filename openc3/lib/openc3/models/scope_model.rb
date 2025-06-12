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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "openc3/version"
require "openc3/models/model"
require "openc3/models/plugin_model"
require "openc3/models/microservice_model"
require "openc3/models/setting_model"
require "openc3/models/trigger_group_model"
require "openc3/topics/system_events_topic"

begin
  require "openc3-enterprise/models/cmd_authority_model"
  require "openc3-enterprise/models/critical_cmd_model"
  module OpenC3
    class ScopeModel < Model
      ENTERPRISE = true
    end
  end
rescue LoadError
  module OpenC3
    class ScopeModel < Model
      ENTERPRISE = false
    end
  end
end

module OpenC3
  class ScopeModel < Model
    PRIMARY_KEY = "openc3_scopes"

    attr_accessor :children
    attr_accessor :text_log_cycle_time
    attr_accessor :text_log_cycle_size
    attr_accessor :text_log_retain_time
    attr_accessor :tool_log_retain_time
    attr_accessor :cleanup_poll_time
    attr_accessor :command_authority
    attr_accessor :critical_commanding
    attr_accessor :shard

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    #
    # The scope keyword is given to support the ModelController method signature
    # even though it is not used
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
      json = JSON.parse(json, allow_nan: true, create_additions: true) if String === json
      raise "json data is nil" if json.nil?
      new(**json.transform_keys(&:to_sym))
    end

    def self.get_model(name:, scope: nil)
      json = get(name: name)
      if json
        from_json(json)
      else
        nil
      end
    end

    def initialize(name:,
      text_log_cycle_time: 600,
      text_log_cycle_size: 50_000_000,
      text_log_retain_time: nil,
      tool_log_retain_time: nil,
      cleanup_poll_time: 600,
      command_authority: false,
      critical_commanding: "OFF",
      shard: 0,
      updated_at: nil)
      super(
        PRIMARY_KEY,
        name: name,
        updated_at: updated_at,
        # This sets the @scope variable which is sort of redundant for the ScopeModel
        # (since its the same as @name) but every model has a @scope
        scope: name
      )
      @text_log_cycle_time = text_log_cycle_time
      @text_log_cycle_size = text_log_cycle_size
      @text_log_retain_time = text_log_retain_time
      @tool_log_retain_time = tool_log_retain_time
      @cleanup_poll_time = cleanup_poll_time
      @command_authority = command_authority
      @critical_commanding = critical_commanding.to_s.upcase
      @critical_commanding = "OFF" if @critical_commanding.length == 0
      if !["OFF", "NORMAL", "ALL"].include?(@critical_commanding)
        raise "Invalid value for critical_commanding: #{@critical_commanding}"
      end
      @shard = shard.to_i # to_i to handle nil
      @children = []
    end

    def create(update: false, force: false, queued: false)
      # Ensure there are no "." in the scope name - prevents gems accidentally becoming scope names
      raise "Invalid scope name: #{@name}" if !/^[a-zA-Z0-9_-]+$/.match?(@name)
      @name = @name.upcase
      @scope = @name # Ensure @scope matches @name
      # Ensure the various cycle and retain times are integers
      @text_log_cycle_time = @text_log_cycle_time.to_i
      @text_log_cycle_size = @text_log_cycle_size.to_i
      @text_log_retain_time = @text_log_retain_time.to_i if @text_log_retain_time
      @tool_log_retain_time = @tool_log_retain_time.to_i if @tool_log_retain_time
      @cleanup_poll_time = @cleanup_poll_time.to_i
      super

      if ENTERPRISE
        # If we're updating the scope and disabling command_authority
        # then we clear out all the existing values so it comes up fresh
        if update and @command_authority == false
          CmdAuthorityModel.names(scope: @name).each do |auth_name|
            model = CmdAuthorityModel.get_model(name: auth_name, scope: @name)
            model.destroy if model
          end
        end

        # If we're updating the scope and disabling critical_commanding
        # then we clear out all the pending critical commands
        if update and @critical_commanding == "OFF"
          CriticalCmdModel.names(scope: @name).each do |name|
            model = CriticalCmdModel.get_model(name: name, scope: @name)
            model.destroy if model
          end
        end
      end

      SystemEventsTopic.write(:scope, as_json)
    end

    def destroy
      if @name != "DEFAULT"
        # Remove all the plugins for this scope
        plugins = PluginModel.get_all_models(scope: @name)
        plugins.each do |_plugin_name, plugin|
          plugin.destroy
        end
        super
      else
        raise "DEFAULT scope cannot be destroyed"
      end
    end

    def as_json(*_a)
      {"name" => @name,
       "updated_at" => @updated_at,
       "text_log_cycle_time" => @text_log_cycle_time,
       "text_log_cycle_size" => @text_log_cycle_size,
       "text_log_retain_time" => @text_log_retain_time,
       "tool_log_retain_time" => @tool_log_retain_time,
       "cleanup_poll_time" => @cleanup_poll_time,
       "command_authority" => @command_authority,
       "critical_commanding" => @critical_commanding,
       "shard" => @shard}
    end

    def deploy_openc3_log_messages_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__OPENC3__LOG"
      topics = ["#{@scope}__openc3_log_messages"]
      # Also log the NOSCOPE messages with this microservice for the DEFAULT scope
      if @scope == "DEFAULT"
        topics << "NOSCOPE__openc3_log_messages"
      end
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "text_log_microservice.rb", microservice_name],
        work_dir: "/openc3/lib/openc3/microservices",
        options: [
          ["CYCLE_TIME", @text_log_cycle_time],
          ["CYCLE_SIZE", @text_log_cycle_size]
        ],
        topics: topics,
        parent: parent,
        shard: @shard,
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
        work_dir: "/openc3/lib/openc3/microservices",
        options: [
          ["RAW_OR_DECOM", "RAW"],
          ["CMD_OR_TLM", "CMD"],
          ["CYCLE_TIME", "3600"] # Keep at most 1 hour per log
        ],
        topics: ["#{@scope}__COMMAND__{UNKNOWN}__UNKNOWN"],
        target_names: [],
        parent: parent,
        shard: @shard,
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
        work_dir: "/openc3/lib/openc3/microservices",
        options: [
          ["RAW_OR_DECOM", "RAW"],
          ["CMD_OR_TLM", "TLM"],
          ["CYCLE_TIME", "3600"] # Keep at most 1 hour per log
        ],
        topics: ["#{@scope}__TELEMETRY__{UNKNOWN}__UNKNOWN"],
        target_names: [],
        parent: parent,
        shard: @shard,
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
        work_dir: "/openc3/lib/openc3/microservices",
        parent: parent,
        shard: @shard,
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
        work_dir: "/openc3/lib/openc3/microservices",
        parent: parent,
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      @children << microservice_name if parent
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy_critical_cmd_microservice(gem_path, variables, parent)
      microservice_name = "#{@scope}__CRITICALCMD__#{@scope}"
      microservice = MicroserviceModel.new(
        name: microservice_name,
        cmd: ["ruby", "critical_cmd_microservice.rb", microservice_name],
        work_dir: "/openc3-enterprise/lib/openc3-enterprise/microservices",
        parent: parent,
        shard: @shard,
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
        work_dir: "/openc3/lib/openc3/microservices",
        target_names: [],
        shard: @shard,
        scope: @scope
      )
      microservice.create
      microservice.deploy(gem_path, variables)
      Logger.info "Configured microservice #{microservice_name}"
    end

    def deploy(gem_path, variables)
      seed_database

      if ENTERPRISE
        # Create DEFAULT trigger group model
        model = TriggerGroupModel.get(name: "DEFAULT", scope: @scope)
        unless model
          model = TriggerGroupModel.new(name: "DEFAULT", shard: @shard, scope: @scope)
          model.create
          model.deploy
        end
      end

      # Create UNKNOWN target for display of unknown data
      model = TargetModel.new(name: "UNKNOWN", shard: @shard, scope: @scope)
      model.create

      @parent = "#{@scope}__SCOPEMULTI__#{@scope}"

      # OpenC3 Log Microservice
      deploy_openc3_log_messages_microservice(gem_path, variables, @parent)

      # UNKNOWN CommandLog Microservice
      deploy_unknown_commandlog_microservice(gem_path, variables, @parent)

      # UNKNOWN PacketLog Microservice
      deploy_unknown_packetlog_microservice(gem_path, variables, @parent)

      # Only DEFAULT scope
      if @scope == "DEFAULT"
        # Periodic Microservice
        deploy_periodic_microservice(gem_path, variables, @parent)
      end

      # Scope Cleanup Microservice
      deploy_scopecleanup_microservice(gem_path, variables, @parent)

      if ENTERPRISE
        # Critical Cmd Microservice
        deploy_critical_cmd_microservice(gem_path, variables, @parent)
      end

      # Multi Microservice to parent other scope microservices
      deploy_scopemulti_microservice(gem_path, variables)
    end

    def undeploy
      # Delete UNKNOWN target
      target = TargetModel.get_model(name: "UNKNOWN", scope: @scope)
      target.destroy

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
      if ENTERPRISE
        model = MicroserviceModel.get_model(name: "#{@scope}__TRIGGER_GROUP__DEFAULT", scope: @scope)
        model.destroy if model
        model = MicroserviceModel.get_model(name: "#{@scope}__CRITICALCMD__#{@scope}", scope: @scope)
        model.destroy if model

        Topic.del("#{@scope}__openc3_autonomic")
        Topic.del("#{@scope}__TRIGGER__GROUP")
      end

      # Delete the topics we created for the scope
      Topic.del("#{@scope}__COMMAND__{UNKNOWN}__UNKNOWN")
      Topic.del("#{@scope}__TELEMETRY__{UNKNOWN}__UNKNOWN")
      Topic.del("#{@scope}__openc3_targets")
      Topic.del("#{@scope}__CONFIG")
    end

    def seed_database
      setting = SettingModel.get(name: "source_url")
      SettingModel.set({name: "source_url", data: "https://github.com/OpenC3/cosmos"}, scope: @scope) unless setting
      setting = SettingModel.get(name: "rubygems_url")
      SettingModel.set({name: "rubygems_url", data: ENV["RUBYGEMS_URL"] || "https://rubygems.org"}, scope: @scope) unless setting
      setting = SettingModel.get(name: "pypi_url")
      SettingModel.set({name: "pypi_url", data: ENV["PYPI_URL"] || "https://pypi.org"}, scope: @scope) unless setting
      # Set the news feed to true by default, don't bother checking if it's already set
      SettingModel.set({name: "news_feed", data: true}, scope: @scope)

      setting = SettingModel.get(name: "system_health")
      system_health_data = {
        "cpu" => {
          "redThreshold" => 90.0,
          "yellowThreshold" => 80.0,
          "snoozeMinutes" => 15,
          "lastTriggerTimeRed" => nil,  # timestamp or nil
          "lastTriggerTimeYellow" => nil,  # timestamp or nil
          "sustainedSeconds" => 15
        },
        "memory" => {
          "redThreshold" => 90.0,
          "yellowThreshold" => 80.0,
          "snoozeMinutes" => 15,
          "lastTriggerTimeRed" => nil,  # timestamp or nil
          "lastTriggerTimeYellow" => nil,  # timestamp or nil
          "sustainedSeconds" => 15
        },
        "disk" => {
          "redThreshold" => 90.0,
          "yellowThreshold" => 80.0,
          "snoozeMinutes" => 720,  # 12 hours
          "lastTriggerTimeRed" => nil,  # timestamp or nil
          "lastTriggerTimeYellow" => nil,  # timestamp or nil
          "sustainedSeconds" => 60
        },
        "global" => {
          "enableAlerts" => true
        }
      }
      SettingModel.set({name: "system_health", data: system_health_data}, scope: "DEFAULT") unless setting
    end
  end
end
