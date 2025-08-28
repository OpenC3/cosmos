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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/model'
require 'openc3/models/microservice_model'
require 'openc3/topics/queue_topic'
require 'openc3/utilities/logger'

module OpenC3
  class QueueError < StandardError; end

  class QueueModel < Model
    PRIMARY_KEY = 'openc3__queue'.freeze

    @@class_mutex = Mutex.new

    # NOTE: The following three class methods are used by the ModelController
    # and are reimplemented to enable various Model class methods to work
    def self.get(name:, scope:)
      super("#{scope}__#{PRIMARY_KEY}", name: name)
    end

    def self.names(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end

    def self.all(scope:)
      super("#{scope}__#{PRIMARY_KEY}")
    end
    # END NOTE

    def self.queue_command(name, command:, username:, scope:)
      model = get_model(name: name, scope: scope)
      raise QueueError, "Queue '#{name}' not found in scope '#{scope}'" unless model

      if model.state != 'DISABLE'
        result = Store.zrevrange("#{scope}:#{name}", 0, 0, with_scores: true)
        if result.empty?
          index = 1.0
        else
          index = result[0][1].to_f + 1
        end
        Store.zadd("#{scope}:#{name}", index, { username: username, value: command, timestamp: Time.now.to_nsec_from_epoch }.to_json)
        model.notify(kind: 'command')
      else
        raise QueueError, "Queue '#{name}' is disabled. Command '#{command}' not queued."
      end
    end

    attr_accessor :name, :state

    def initialize(name:, scope:, state: 'HOLD', updated_at: nil)
      super("#{scope}__#{PRIMARY_KEY}", name: name, updated_at: updated_at, scope: scope)
      @microservice_name = "#{scope}__QUEUE__#{name}"
      @state = state
      @instance_mutex = Mutex.new
    end

    def create(update: false, force: false, queued: false)
      super(update: update, force: force, queued: queued)
      if update
        notify(kind: 'updated')
      else
        notify(kind: 'created')
      end
    end

    # @return [Hash] generated from the QueueModel
    def as_json(*a)
      return {
        'name' => @name,
        'scope' => @scope,
        'state' => @state,
        'updated_at' => @updated_at
      }
    end

    # @return [] update the redis stream / queue topic that something has changed
    def notify(kind:)
      notification = {
        'kind' => kind,
        'data' => JSON.generate(as_json(:allow_nan => true)),
      }
      QueueTopic.write_notification(notification, scope: @scope)
    end

    def insert_command(index, command_data)
      unless index
        result = Store.zrevrange("#{scope}:#{name}", 0, 0, with_scores: true)
        if result.empty?
          index = 1.0
        else
          index = result[0][1].to_f + 1
        end
      end
      Store.zadd("#{@scope}:#{@name}", index, command_data.to_json)
      notify(kind: 'command')
    end

    def remove_command(index)
      num_removed = Store.zremrangebyscore("#{@scope}:#{@name}", index, index)
      notify(kind: 'command')
      return (num_removed == 1)
    end

    def update_command(index:, command:, username:)
      # Check if command exists at the given index
      existing = Store.zrangebyscore("#{@scope}:#{@name}", index, index)
      if existing.empty?
        raise QueueError, "No command found at index #{index} in queue '#{@name}'"
      end

      # Remove the existing command and add the new one at the same index
      Store.zremrangebyscore("#{@scope}:#{@name}", index, index)
      command_data = { username: username, value: command, timestamp: Time.now.to_nsec_from_epoch }
      Store.zadd("#{@scope}:#{@name}", index, command_data.to_json)
      notify(kind: 'command')
    end

    def list
      return Store.zrange("#{@scope}:#{@name}", 0, -1, with_scores: true).map do |item|
        result = JSON.parse(item[0])
        result['index'] = item[1].to_f
        result
      end
    end

    def create_microservice(topics:)
      # queue Microservice
      microservice = MicroserviceModel.new(
        name: @microservice_name,
        folder_name: nil,
        cmd: ['ruby', 'queue_microservice.rb', @microservice_name],
        work_dir: '/openc3/lib/openc3/microservices',
        options: [],
        topics: topics,
        target_names: [],
        plugin: nil,
        scope: @scope
      )
      microservice.create
    end

    def deploy()
      topics = ["#{@scope}__#{QueueTopic::PRIMARY_KEY}"]
      if MicroserviceModel.get_model(name: @microservice_name, scope: @scope).nil?
        create_microservice(topics: topics)
      end
    end

    def undeploy
      model = MicroserviceModel.get_model(name: @microservice_name, scope: @scope)
      if model
        # Let the frontend know that the microservice is shutting down
        # Custom event which matches the 'deployed' event in QueueMicroservice
        notification = {
          'kind' => 'undeployed',
          # name and updated_at fields are required for Event formatting
          'data' => JSON.generate({
            'name' => @microservice_name,
            'updated_at' => Time.now.to_nsec_from_epoch,
          }),
        }
        QueueTopic.write_notification(notification, scope: @scope)
        model.destroy
      end
    end

    # Delete the model from the Store
    def destroy
      Store.zremrangebyrank("#{@scope}:#{@name}", 0, -1)
      super()
    end
  end
end