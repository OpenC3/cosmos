# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require 'openc3/microservices/microservice'
require 'openc3/topics/queue_topic'
require 'openc3/models/queue_model'
require 'openc3/utilities/authentication'
require 'openc3/api/api'

module OpenC3
  module Script
    private
    # Override the prompt_for_hazardous method to always return true since there is no user to prompt
    def prompt_for_hazardous(target_name, cmd_name, hazardous_description)
      return true
    end
  end

  # The queue processor runs in a single thread and processes commands via cmd_api.
  class QueueProcessor
    include Api # Provides access to api methods

    attr_accessor :state
    attr_reader :name, :scope

    def initialize(name:, state:, logger:, scope:)
      @name = name
      @logger = logger
      @scope = scope
      @state = state
      @cancel_thread = false
    end

    def run
      while true
        if @state == 'RELEASE'
          process_queued_commands()
        else
          sleep 0.2
        end
        break if @cancel_thread
      end
    end

    def process_queued_commands
      while @state == 'RELEASE'
        begin
          _queue_name, command_data, _timestamp = Store.bzpopmin("#{@scope}:#{@name}", timeout: 0.2)
          if command_data
            command = JSON.parse(command_data)
            # It's important to set queue: false here to avoid infinite recursion when
            # OPENC3_DEFAULT_QUEUE is set because commands would be re-queued to the default queue
            # NOTE: cmd() via script rescues hazardous errors and calls prompt_for_hazardous()
            # but we've overridden it to always return true and go straight to cmd_no_hazardous_check()

            # Support both new format (target_name, cmd_name, cmd_params) and legacy format (command string)
            if command['target_name'] && command['cmd_name']
              # New format: use 3-parameter cmd() method
              if command['cmd_params']
                cmd_params = JSON.parse(command['cmd_params'], allow_nan: true, create_additions: true)
              else
                cmd_params = {}
              end
              cmd(command['target_name'], command['cmd_name'], cmd_params, queue: false, scope: @scope)
            elsif command['value']
              # Legacy format: use single string parameter for backwards compatibility
              cmd(command['value'], queue: false, scope: @scope)
            else
              @logger.error "QueueProcessor: Invalid command format, missing required fields"
            end
          end
        rescue StandardError => e
          @logger.error "QueueProcessor failed to process command from queue #{@name}\n#{e.message}"
        end
        break if @cancel_thread
      end
    end

    def shutdown
      @cancel_thread = true
    end
  end

  # The queue microservice starts a processor then gets the queue entries from redis.
  # It then monitors the QueueTopic for changes.
  class QueueMicroservice < Microservice
    attr_reader :name, :processor, :processor_thread

    def initialize(*args)
      super(*args)
      @queue_name = @name.split('__')[2]

      initial_state = 'HOLD'
      # See if the queue already exists to get its state
      queue = OpenC3::QueueModel.get(name: @queue_name, scope: @scope)
      if queue
        initial_state = queue['state']
      else
        (@config['options'] || []).each do |option|
          case option[0].upcase
          when 'QUEUE_STATE'
            initial_state = option[1]
          else
            @logger.error("Unknown option passed to microservice #{@name}: #{option}")
          end
        end
      end

      @logger.info "Creating QueueMicroservice in scope #{@scope} for queue #{@queue_name} with initial state #{initial_state}"
      @processor = QueueProcessor.new(name: @queue_name, state: initial_state, logger: @logger, scope: @scope)
      @processor_thread = nil
      @read_topic = true
    end

    def run
      @logger.info "QueueMicroservice running"
      @processor_thread = Thread.new { @processor.run }

      # Let the frontend know that the microservice has been deployed and is running
      notification = {
        'kind' => 'deployed',
        # name and updated_at fields are required for Event formatting
        'data' => JSON.generate({
          'name' => @name,
          'updated_at' => Time.now.to_nsec_from_epoch,
        }),
      }
      QueueTopic.write_notification(notification, scope: @scope)

      loop do
        break if @cancel_thread
        block_for_updates()
      end
      @processor.shutdown()
      @processor_thread.join() if @processor_thread
      @logger.info "QueueMicroservice exiting"
    end

    def block_for_updates
      @read_topic = true
      while @read_topic && !@cancel_thread
        begin
          QueueTopic.read_topics(@topics) do |_topic, _msg_id, msg_hash, _redis|
            data = JSON.parse(msg_hash['data']) if msg_hash['data']
            if data['name'] == @queue_name and msg_hash['kind'] == 'updated'
              @processor.state = data['state']
            end
          end
        rescue StandardError => e
          @logger.error "QueueMicroservice failed to read topics #{@topics}\n#{e.formatted}"
        end
      end
    end

    def shutdown
      @read_topic = false
      @processor.shutdown() if @processor
      super
    end
  end
end

if __FILE__ == $0
  OpenC3::QueueMicroservice.run
  OpenC3::ThreadManager.instance.shutdown
  OpenC3::ThreadManager.instance.join
end
