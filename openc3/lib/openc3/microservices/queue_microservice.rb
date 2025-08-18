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
require 'openc3/models/queue_model'

require 'openc3/script'

module OpenC3
  # This should remain a thread safe implementation. This is the in memory
  # cache that should mirror the database. This will update hash
  # variables and will track queue entries and their processing states.
  class QueueBase
    attr_reader :queues

    def initialize(scope:)
      @scope = scope
      @queues_mutex = Mutex.new
      @queues = Hash.new
    end

    # RETURNS an Array of active queue entries
    def get_queued_entries
      data = nil
      @queues_mutex.synchronize do
        data = Marshal.load( Marshal.dump(@queues) )
      end
      ret = Array.new
      return ret unless data
      data.each do |_name, q_hash|
        data = Marshal.load( Marshal.dump(q_hash) )
        queue = QueueModel.from_json(data, name: data['name'], scope: data['scope'])
        ret << queue if queue.enabled && queue.pending?
      end
      return ret
    end

    # RETURNS an Array of queue entries by status
    def get_entries_by_status(status:)
      array_value = nil
      @queues_mutex.synchronize do
        data = Marshal.load( Marshal.dump(@queues) )
      end
      ret = Array.new
      return ret unless data
      data.each do |_name, q_hash|
        queue_data = Marshal.load( Marshal.dump(q_hash) )
        queue = QueueModel.from_json(queue_data, name: queue_data['name'], scope: queue_data['scope'])
        ret << queue if queue.status == status
      end
      return ret
    end

    # Update the memory database with a HASH of queue entries from the external database
    def setup(queues:)
      @queues_mutex.synchronize do
        @queues = Marshal.load( Marshal.dump(queues) )
      end
    end

    # Pulls the latest queue entry from the in memory database to see
    # if the entry should be marked as completed.
    def complete(name:)
      @queues_mutex.synchronize do
        data = Marshal.load( Marshal.dump(@queues[name]) )
        return unless data
        queue = QueueModel.from_json(data, name: data['name'], scope: data['scope'])
        queue.complete()
        @queues[name] = queue.as_json(:allow_nan => true)
      end
    end

    # Pulls the latest queue entry from the in memory database to see
    # if the entry should be marked as failed.
    def fail(name:, message: nil)
      @queues_mutex.synchronize do
        data = Marshal.load( Marshal.dump(@queues[name]) )
        return unless data
        queue = QueueModel.from_json(data, name: data['name'], scope: data['scope'])
        queue.fail(message: message)
        @queues[name] = queue.as_json(:allow_nan => true)
      end
    end

    # Add a queue entry to the in memory database
    def add(queue:)
      queue_name = queue['name']
      @queues_mutex.synchronize do
        @queues[queue_name] = queue
      end
    end

    # Updates a queue entry in the in memory database
    def update(queue:)
      @queues_mutex.synchronize do
        model = QueueModel.from_json(queue, name: queue['name'], scope: queue['scope'])
        model.update()
        @queues[queue['name']] = model.as_json(:allow_nan => true)
      end
    end

    # Removes a queue entry from the in memory database
    def remove(queue:)
      @queues_mutex.synchronize do
        @queues.delete(queue['name'])
        QueueModel.delete(name: queue['name'], scope: queue['scope'])
      end
    end
  end

  # Shared between the main thread and event handling to share resources.
  class QueueShare
    attr_reader :queue_base

    def initialize(scope:)
      @queue_base = QueueBase.new(scope: scope)
    end
  end

  # The queue processor runs in a single thread and processes commands via cmd_api.
  class QueueProcessor
    attr_reader :name, :scope, :share

    def initialize(name:, logger:, scope:, share:)
      @name = name
      @logger = logger
      @scope = scope
      @share = share
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
      @logger.info "QueueProcessor running"
      loop do
        begin
          current_time = Time.now.to_i
          process_queued_entries(current_time: current_time)
        rescue StandardError => e
          @logger.error "QueueProcessor failed to process queue entries.\n#{e.formatted}"
        end
        break if @cancel_thread
        sleep(1)
        break if @cancel_thread
      end
      @logger.info "QueueProcessor exiting"
    end

    def process_queued_entries(current_time:)
      @share.queue_base.get_queued_entries.each do |entry|
        # Check if entry is ready to be processed
        if entry.scheduled_time.nil? || current_time >= entry.scheduled_time
          process_queue_entry(entry: entry)
        end
      end
    end

    def process_queue_entry(entry:)
      @logger.info "QueueProcessor processing entry: #{entry.name}"

      begin
        # Mark entry as processing
        entry.start()
        @share.queue_base.update(queue: entry.as_json(:allow_nan => true))

        # Process the command via cmd_api
        process_command_entry(entry: entry)

        # Mark entry as completed
        @share.queue_base.complete(name: entry.name)
        @logger.info "QueueProcessor completed entry: #{entry.name}"

      rescue StandardError => e
        # Mark entry as failed
        @share.queue_base.fail(name: entry.name, message: e.message)
        @logger.error "QueueProcessor failed to process entry: #{entry.name}\n#{e.formatted}"
      end
    end

    def process_command_entry(entry:)
      username = entry.username
      token = get_token(username)
      raise "No token available for username: #{username}" unless token

      # Make HTTP request to cmd_api to execute the command
      request = Net::HTTP::Post.new(
        "/openc3-api/api/commands/#{entry.data}",
        'Content-Type' => 'application/json',
        'Authorization' => token
      )
      request.body = JSON.generate({
        'scope' => @scope,
        'queue' => entry.name
      })
      hostname = ENV['OPENC3_CMD_API_HOSTNAME'] || 'openc3-cosmos-cmd-tlm-api'
      response = Net::HTTP.new(hostname, 2901).request(request)
      raise "failed to call #{hostname}, for command: #{entry.data}, response code: #{response.code}" if response.code != '200'

      @logger.info "QueueProcessor command entry complete: #{entry.data} => #{response.body}"
    end

    def shutdown
      @cancel_thread = true
    end
  end

  # The queue microservice starts a processor then gets the queue entries from redis.
  # It then monitors the QueueTopic for changes.
  class QueueMicroservice < Microservice
    attr_reader :name, :scope, :share, :processor, :processor_thread
    TOPIC_LOOKUP = {
      'queue' => {
        'created' => :queue_created_event,
        'updated' => :queue_updated_event,
        'deleted' => :queue_deleted_event,
        'enabled' => :queue_enabled_event,
        'disabled' => :queue_disabled_event,
        'completed' => :no_op,
        'failed' => :no_op,
        'started' => :no_op,
      }
    }

    def initialize(*args)
      # The name is passed in via the queue_model as "#{scope}__OPENC3__QUEUE"
      super(*args)
      @share = QueueShare.new(scope: @scope)
      @processor = QueueProcessor.new(name: @name, logger: @logger, scope: @scope, share: @share)
      @processor_thread = nil
      @read_topic = true
    end

    def run
      @logger.info "QueueMicroservice running"
      # Let the frontend know that the microservice has been deployed and is running
      notification = {
        'kind' => 'deployed',
        'type' => 'queue',
        # name and updated_at fields are required for Event formatting
        'data' => JSON.generate({
          'name' => @name,
          'updated_at' => Time.now.to_nsec_from_epoch,
        }),
      }
      QueueTopic.write_notification(notification, scope: @scope)

      @processor_thread = Thread.new { @processor.run }
      loop do
        queues = QueueModel.all(scope: @scope)
        @share.queue_base.setup(queues: queues)
        break if @cancel_thread
        block_for_updates()
        break if @cancel_thread
      end
      @logger.info "QueueMicroservice exiting"
    end

    def block_for_updates
      @read_topic = true
      while @read_topic && !@cancel_thread
        begin
          QueueTopic.read_topics(@topics) do |_topic, _msg_id, msg_hash, _redis|
            @logger.debug "QueueMicroservice block_for_updates: #{msg_hash.to_s}"
            public_send(TOPIC_LOOKUP[msg_hash['type']][msg_hash['kind']], msg_hash)
          end
        rescue StandardError => e
          @logger.error "QueueMicroservice failed to read topics #{@topics}\n#{e.formatted}"
        end
      end
    end

    def no_op(data)
      @logger.debug "QueueMicroservice web socket event: #{data}"
    end

    def queue_updated_event(msg_hash)
      @logger.debug "QueueMicroservice queue updated msg_hash: #{msg_hash}"
      queue = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
      @share.queue_base.update(queue: queue)
      @read_topic = false
    end

    # Add the queue entry to the shared data.
    def queue_created_event(msg_hash)
      @logger.debug "QueueMicroservice queue created msg_hash: #{msg_hash}"
      queue = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
      @share.queue_base.add(queue: queue)
    end

    # Update the queue entry in the shared data.
    def queue_enabled_event(msg_hash)
      @logger.debug "QueueMicroservice queue enabled msg_hash: #{msg_hash}"
      queue = JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true)
      @share.queue_base.update(queue: queue)
    end

    # Update the queue entry in the shared data.
    def queue_disabled_event(msg_hash)
      @logger.debug "QueueMicroservice queue disabled msg_hash: #{msg_hash}"
      @share.queue_base.update(queue: JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true))
    end

    # Remove the queue entry from the shared data
    def queue_deleted_event(msg_hash)
      @logger.debug "QueueMicroservice queue deleted msg_hash: #{msg_hash}"
      @share.queue_base.remove(queue: JSON.parse(msg_hash['data'], :allow_nan => true, :create_additions => true))
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