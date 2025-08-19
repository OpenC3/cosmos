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

module OpenC3
  class QueueError < StandardError; end

  class QueueModel < Model
    PRIMARY_KEY = 'openc3__queue'.freeze

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

    attr_reader :name, :state, :commands

    def initialize(name:, scope: shard: 0)
      super("#{scope}__#{PRIMARY_KEY}", name: name, scope: scope)
      @microservice_name = "#{scope}__QUEUE__#{name}"
      @state = 'HOLD'
      @commands = []
      @shard = shard
    end

    def create
      super()
      notify(kind: 'created')
    end

    def update
      super()
      notify(kind: 'updated')
    end

    # @return [Hash] generated from the QueueModel
    def as_json(*a)
      return {
        'name' => @name,
        'scope' => @scope,
        'state' => @state,
        'commands' => @commands.as_json(*a),
        'shard' => @shard,
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
        shard: @shard,
        scope: @scope
      )
      microservice.create
    end

    def deploy
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
  end
end