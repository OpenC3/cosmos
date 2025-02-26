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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3'
require 'openc3/models/microservice_model'
require 'openc3/operators/operator'
require 'openc3/utilities/secrets'
require 'redis'
require 'open3'
require 'fileutils'

module OpenC3
  # Creates new OperatorProcess objects based on querying the Redis key value store.
  # Any keys under 'openc3_microservices' will be created into microservices.
  class MicroserviceOperator < Operator
    def initialize
      Logger.microservice_name = "MicroserviceOperator"
      super

      @secrets = Secrets.getClient
      @microservices = {}
      @previous_microservices = {}
      @new_microservices = {}
      @changed_microservices = {}
      @removed_microservices = {}
      @shard = ENV['OPENC3_SHARD'] || 0
      @shard = @shard.to_i
    end

    def convert_microservice_to_process_definition(microservice_name, microservice_config)
      process_definition = ["ruby", "plugin_microservice.rb"]
      work_dir = "/openc3/lib/openc3/microservices"
      env = microservice_config["env"].dup
      if microservice_config["needs_dependencies"]
        env['GEM_HOME'] = '/gems'
        env['PYTHONUSERBASE'] = '/gems/python_packages'
      else
        env['GEM_HOME'] = nil
        env['PYTHONUSERBASE'] = nil
      end
      env['OPENC3_MICROSERVICE_NAME'] = microservice_name
      container = microservice_config["container"]
      scope = microservice_name.split("__")[0]

      # Setup secrets for microservice
      secrets = microservice_config["secrets"]
      if secrets
        secrets.each do |type, secret_name, env_name_or_path, secret_store|
          secret_value = @secrets.get(secret_name, secret_store: secret_store, scope: scope)
          if secret_value
            if type == 'ENV'
              env[env_name_or_path] = secret_value
            elsif type == 'FILE'
              FileUtils.mkdir_p(File.dirname(env_name_or_path))
              File.open(env_name_or_path, 'wb') do |file|
                file.write(secret_value)
              end
            end
          else
            Logger.error("Microservice #{microservice_name} references unknown secret: #{secret_name}")
          end
        end
      end

      return process_definition, work_dir, env, scope, container
    end

    # Handle the detection of a new microservice model
    def handle_new_microservice(microservice_name, microservice_config)
      parent = microservice_config['parent']
      enabled = microservice_config['enabled']
      enabled = true if enabled.nil?
      scope = microservice_name.split("__")[0]

      if enabled
        Logger.info("New microservice detected: #{microservice_name}", scope: scope)
        if parent
          # Respawn parent if it exists and isn't new
          if @microservices[parent] and @previous_microservices[parent]
            @changed_microservices[parent] = @microservices[parent]
          end
        else
          # New process be spawned
          @new_microservices[microservice_name] = microservice_config
        end
      end
    end

    # Handle a change detected in a microservice model
    def handle_changed_microservice(microservice_name, microservice_config)
      parent = microservice_config['parent']
      enabled = microservice_config['enabled']
      enabled = true if enabled.nil?
      scope = microservice_name.split("__")[0]
      previous_parent = @previous_microservices[microservice_name]['parent']
      previous_enabled = @previous_microservices[microservice_name]["enabled"]
      previous_enabled = true if previous_enabled.nil?

      Logger.info("Changed microservice detected: #{microservice_name}\nWas: #{@previous_microservices[microservice_name]}\nIs: #{microservice_config}", scope: scope)

      if parent or previous_parent
        if parent == previous_parent
          # Same Parent - Respawn parent
          @changed_microservices[parent] = @microservices[parent] if @microservices[parent] and @previous_microservices[parent]
        elsif parent and previous_parent
          # Parent changed - Respawn both parents
          @changed_microservices[parent] = @microservices[parent] if @microservices[parent] and @previous_microservices[parent]
          @changed_microservices[previous_parent] = @microservices[previous_parent] if @microservices[previous_parent] and @previous_microservices[previous_parent]
        elsif parent
          # Moved under a parent - Respawn parent and kill standalone (if previously enabled)
          @changed_microservices[parent] = @microservices[parent] if @microservices[parent] and @previous_microservices[parent]
          if previous_enabled
            @removed_microservices[microservice_name] = microservice_config
          end
        else # previous_parent
          # Moved to standalone - Respawn previous parent and make new (if enabled)
          @changed_microservices[previous_parent] = @microservices[previous_parent] if @microservices[previous_parent] and @previous_microservices[previous_parent]
          if enabled
            @new_microservices[microservice_name] = microservice_config
          end
        end
      else
        if previous_enabled
          if enabled
            # Respawn regular microservice
            @changed_microservices[microservice_name] = microservice_config
          else
            # Remove regular microservice
            @removed_microservices[microservice_name] = microservice_config
          end
        else
          # Newly enabled microservice
          @new_microservices[microservice_name] = microservice_config
        end
      end
    end

    # Handle the detection of a removed microservice model
    def handle_removed_microservice(microservice_name, microservice_config)
      previous_parent = @previous_microservices[microservice_name]['parent']
      scope = microservice_name.split("__")[0]

      Logger.info("Removed microservice detected: #{microservice_name}", scope: scope)

      if previous_parent
        # Respawn previous parent
        @changed_microservices[previous_parent] = @microservices[previous_parent] if @microservices[previous_parent] and @previous_microservices[previous_parent]
      else
        previous_enabled = @previous_microservices[microservice_name]["enabled"]
        previous_enabled = true if previous_enabled.nil?
        if previous_enabled
          # Regular process to be removed
          @removed_microservices[microservice_name] = microservice_config
        end
      end
    end

    def update
      @previous_microservices = @microservices.dup
      # Get all the microservice configuration
      @microservices = MicroserviceModel.all

      # Filter to just this shard
      @microservices = @microservices.select do |microservice_name, microservice_config|
        microservice_shard = microservice_config['shard'] || 0
        microservice_shard == @shard
      end

      # Detect new and changed microservices
      @new_microservices = {}
      @changed_microservices = {}
      @removed_microservices = {}
      @microservices.each do |microservice_name, microservice_config|
        if @previous_microservices[microservice_name]
          if @previous_microservices[microservice_name] != microservice_config
            if not microservice_config['ignore_changes']
              handle_changed_microservice(microservice_name, microservice_config)
            end
          end
        else
          handle_new_microservice(microservice_name, microservice_config)
        end
      end

      # Detect removed microservices
      @previous_microservices.each do |microservice_name, microservice_config|
        unless @microservices[microservice_name]
          handle_removed_microservice(microservice_name, microservice_config)
        end
      end

      # Convert to processes
      @mutex.synchronize do
        @new_microservices.each do |microservice_name, microservice_config|
          cmd_array, work_dir, env, scope, container = convert_microservice_to_process_definition(microservice_name, microservice_config)
          if cmd_array
            process = OperatorProcess.new(cmd_array, work_dir: work_dir, env: env, scope: scope, container: container, config: microservice_config)
            @new_processes[microservice_name] = process
            @processes[microservice_name] = process
          end
        end

        @changed_microservices.each do |microservice_name, microservice_config|
          cmd_array, work_dir, env, scope, container = convert_microservice_to_process_definition(microservice_name, microservice_config)
          if cmd_array
            process = @processes[microservice_name]
            if process
              process.process_definition = cmd_array
              process.work_dir = work_dir
              process.new_temp_dir = nil
              process.env = env
              @changed_processes[microservice_name] = process
            else
              # This shouldn't be possible, but still needs to be handled
              Logger.error("Changed microservice #{microservice_name} does not exist. Creating new...", scope: scope)
              process = OperatorProcess.new(cmd_array, work_dir: work_dir, env: env, scope: scope, container: container, config: microservice_config)
              @new_processes[microservice_name] = process
              @processes[microservice_name] = process
            end
          end
        end

        @removed_microservices.each do |microservice_name, _microservice_config|
          process = @processes[microservice_name]
          @processes.delete(microservice_name)
          @removed_processes[microservice_name] = process
        end
      end
    end
  end
end

OpenC3::MicroserviceOperator.run if __FILE__ == $0
