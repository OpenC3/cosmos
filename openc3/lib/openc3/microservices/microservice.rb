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
OpenC3.require_file 'json'
OpenC3.require_file 'redis'
OpenC3.require_file 'fileutils'
OpenC3.require_file 'openc3/utilities/zip'
OpenC3.require_file 'openc3/utilities/store'
OpenC3.require_file 'openc3/utilities/bucket'
OpenC3.require_file 'openc3/utilities/secrets'
OpenC3.require_file 'openc3/utilities/sleeper'
OpenC3.require_file 'openc3/utilities/open_telemetry'
OpenC3.require_file 'openc3/utilities/thread_manager'
OpenC3.require_file 'openc3/models/microservice_model'
OpenC3.require_file 'openc3/models/microservice_status_model'
OpenC3.require_file 'tmpdir'

module OpenC3
  class Microservice
    attr_accessor :microservice_status_thread
    attr_accessor :name
    attr_accessor :state
    attr_accessor :count
    attr_accessor :error
    attr_accessor :custom
    attr_accessor :scope
    attr_accessor :logger
    attr_accessor :secrets

    def self.run(name = nil)
      name = ENV['OPENC3_MICROSERVICE_NAME'] unless name
      microservice = self.new(name)
      thread = Thread.new do
        begin
          MicroserviceStatusModel.set(microservice.as_json(:allow_nan => true), scope: microservice.scope)
          microservice.state = 'RUNNING'
          microservice.run
          microservice.state = 'FINISHED'
        rescue Exception => e
          if SystemExit === e or SignalException === e
            microservice.state = 'KILLED'
          else
            microservice.error = e
            microservice.state = 'DIED_ERROR'
            Logger.fatal("Microservice #{name} dying from exception\n#{e.formatted}")
          end
        ensure
          MicroserviceStatusModel.set(microservice.as_json(:allow_nan => true), scope: microservice.scope)
        end
      end
      ThreadManager.instance.register(thread, shutdown_object: microservice)
      ThreadManager.instance.monitor
      ThreadManager.instance.shutdown
    end

    def as_json(*a)
      {
        'name' => @name,
        'state' => @state,
        'count' => @count,
        'error' => @error.as_json(*a),
        'custom' => @custom.as_json(*a),
        'plugin' => @plugin,
      }
    end

    def initialize(name, is_plugin: false)
      @shutdown_complete = false
      raise "Microservice must be named" unless name

      @name = name
      split_name = name.split("__")
      raise "Name #{name} doesn't match convention of SCOPE__TYPE__NAME" if split_name.length != 3

      @scope = split_name[0]
      $openc3_scope = @scope
      @cancel_thread = false
      @metric = Metric.new(microservice: @name, scope: @scope)
      Logger.scope = @scope
      Logger.microservice_name = @name
      @logger = Logger.new
      @logger.scope = @scope
      @logger.microservice_name = @name
      @secrets = Secrets.getClient

      OpenC3.setup_open_telemetry(@name, false)

      # Create temp folder for this microservice
      @temp_dir = Dir.mktmpdir

      # Get microservice configuration from Redis
      @config = MicroserviceModel.get(name: @name, scope: @scope)
      if @config
        @topics = @config['topics']
        @plugin = @config['plugin']
        if @config['secrets']
          @secrets.setup(@config['secrets'])
        end
      else
        @config = {}
        @plugin = nil
      end
      @logger.info("Microservice initialized with config:\n#{@config}")
      @topics ||= []
      @microservice_topic = "MICROSERVICE__#{@name}"

      # Get configuration for any targets
      @target_names = @config["target_names"]
      @target_names ||= []
      # NOTE: setup_targets doesn't do anything if @target_names is empty
      System.setup_targets(@target_names, @temp_dir, scope: @scope) unless is_plugin

      # Use at_exit to shutdown cleanly no matter how we die
      at_exit do
        shutdown()
      end

      @count = 0
      @error = nil
      @custom = nil
      @state = 'INITIALIZED'
      @work_dir = @config["work_dir"]

      if is_plugin
        cmd_array = @config["cmd"]

        # Get Microservice files from bucket storage
        temp_dir = Dir.mktmpdir
        bucket = ENV['OPENC3_CONFIG_BUCKET']
        client = Bucket.getClient()

        prefix = "#{@scope}/microservices/#{@name}/"
        file_count = 0
        client.list_objects(bucket: bucket, prefix: prefix).each do |object|
          response_target = File.join(temp_dir, object.key.split(prefix)[-1])
          FileUtils.mkdir_p(File.dirname(response_target))
          client.get_object(bucket: bucket, key: object.key, path: response_target)
          file_count += 1
        end

        # Adjust @work_dir to microservice files downloaded if files and a relative path
        if file_count > 0 and @work_dir[0] != '/'
          @work_dir = File.join(temp_dir, @work_dir)
        end

        # Check Syntax on any ruby files
        ruby_filename = nil
        cmd_array.each do |part|
          if /\.rb$/.match?(part)
            ruby_filename = part
            break
          end
        end
        if ruby_filename
          OpenC3.set_working_dir(@work_dir) do
            if File.exist?(ruby_filename)
              # Run ruby syntax so we can log those
              syntax_check, _ = Open3.capture2e("ruby -c #{ruby_filename}")
              if /Syntax OK/.match?(syntax_check)
                @logger.debug("Ruby microservice #{@name} file #{ruby_filename} passed syntax check\n", scope: @scope)
              else
                @logger.error("Ruby microservice #{@name} file #{ruby_filename} failed syntax check\n#{syntax_check}", scope: @scope)
              end
            else
              @logger.error("Ruby microservice #{@name} file #{ruby_filename} does not exist", scope: @scope)
            end
          end
        end
      else
        @microservice_status_sleeper = Sleeper.new
        @microservice_status_period_seconds = 5
        @microservice_status_thread = Thread.new do
          until @cancel_thread
            MicroserviceStatusModel.set(as_json(:allow_nan => true), scope: @scope) unless @cancel_thread
            break if @microservice_status_sleeper.sleep(@microservice_status_period_seconds)
          end
        rescue Exception => e
          @logger.error "#{@name} status thread died: #{e.formatted}"
          raise e
        end
        ThreadManager.instance.register(@microservice_status_thread)
      end
    end

    # Must be implemented by a subclass
    def run
      shutdown()
    end

    def shutdown
      return if @shutdown_complete
      @logger.info("Shutting down microservice: #{@name}")
      @cancel_thread = true
      @microservice_status_sleeper.cancel if @microservice_status_sleeper
      MicroserviceStatusModel.set(as_json(:allow_nan => true), scope: @scope)
      FileUtils.remove_entry_secure(@temp_dir, true)
      @metric.shutdown
      @logger.debug("Shutting down microservice complete: #{@name}")
      @shutdown_complete = true
    end

    def setup_microservice_topic
      @topics.append(@microservice_topic)
      Thread.current[:topic_offsets] ||= {}
      topic_offsets = Thread.current[:topic_offsets]
      topic_offsets[@microservice_topic] = "0-0" # Always get all available
    end

    # Returns if the command was handled
    def microservice_cmd(topic, msg_id, msg_hash, _redis)
      command = msg_hash['command']
      if command == 'ADD_TOPICS'
        topics = JSON.parse(msg_hash['topics'])
        if topics and Array === topics
          topics.each do |new_topic|
            @topics << new_topic unless @topics.include?(new_topic)
          end
        else
          raise "Invalid topics given to microservice_cmd: #{topics}"
        end
        Topic.trim_topic(topic, msg_id)
        return true
      end
      Topic.trim_topic(topic, msg_id)
      return false
    end
  end
end
