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
require 'openc3/utilities/authentication'
require 'openc3/script'

module OpenC3
  # The queue processor runs in a single thread and processes commands via cmd_api.
  class QueueProcessor
    attr_accessor :state
    attr_reader :name, :queue_name, :scope

    def initialize(name:, logger:, scope:)
      @name = name
      @queue_name = name.split('__')[2]
      @logger = logger
      @scope = scope
      @state = 'HOLD'
      @cancel_thread = false
    end

    def get_token(username)
      if ENV['OPENC3_API_CLIENT'].nil?
        ENV['OPENC3_API_PASSWORD'] ||= ENV['OPENC3_SERVICE_PASSWORD']
        return OpenC3Authentication.new().token
      else
        # Check for offline access token
        model = nil
        model = OpenC3::OfflineAccessModel.get_model(name: username, scope: @scope) if username and username != ''
        if model and model.offline_access_token
          auth = OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
          return auth.get_token_from_refresh_token(model.offline_access_token)
        else
          return nil
        end
      end
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
        queue_name, command_data = Store.blpop("#{@scope}:#{@queue_name}", timeout: 0.2)
        if command_data
          command = JSON.parse(command_data)
          username = command['username']
          token = get_token(username)
          raise "No token available for username: #{username}" unless token
          cmd_no_hazardous_check(command['value'], scope: @scope, token: token)
        end
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
      @processor = QueueProcessor.new(name: @name, logger: @logger, scope: @scope)
      @processor_thread = nil
      @read_topic = true
    end

    def run
      @logger.info "QueueMicroservice running"
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

      @processor_thread = Thread.new { @processor.run }
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
            if msg_hash['kind'] == 'updated'
              queue = JSON.parse(msg_hash['data'])
              @processor.state = queue['state']
            end
          end
        rescue StandardError => e
          @logger.error "QueueMicroservice failed to read topics #{@topics}\n#{e.formatted}"
        end
      end
    end

    def shutdown
      @read_topic = false
      @processor.shutdown()
      super
    end
  end
end

if __FILE__ == $0
  OpenC3::QueueMicroservice.run
  OpenC3::ThreadManager.instance.shutdown
  OpenC3::ThreadManager.instance.join
end