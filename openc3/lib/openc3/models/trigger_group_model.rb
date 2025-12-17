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

require 'openc3/models/model'
require 'openc3/models/microservice_model'
require 'openc3/topics/autonomic_topic'

module OpenC3
  class TriggerGroupError < StandardError; end
  class TriggerGroupInputError < TriggerGroupError; end

  class TriggerGroupModel < Model
    PRIMARY_KEY = '__TRIGGER__GROUP'.freeze

    # @return [GroupModel] Return the object with the name at
    def self.get(name:, scope:)
      json = super("#{scope}#{PRIMARY_KEY}", name: name)
      unless json.nil?
        self.from_json(json, name: name, scope: scope)
      end
    end

    # @return [Array<Hash>] All the Key, Values stored under the name key
    def self.all(scope:)
      super("#{scope}#{PRIMARY_KEY}")
    end

    # @return [Array<String>] All the uuids stored under the name key
    def self.names(scope:)
      super("#{scope}#{PRIMARY_KEY}")
    end

    # Check dependents before delete.
    def self.delete(name:, scope:)
      model = self.get(name: name, scope: scope)
      if model.nil?
        raise TriggerGroupInputError.new "group '#{name}' does not exist"
      end
      triggers = TriggerModel.names(scope: scope, group: name)
      if triggers.empty?
        Store.hdel("#{scope}#{PRIMARY_KEY}", name)
        model.notify(kind: 'deleted')
      else
        raise TriggerGroupError.new "group '#{name}' has dependent triggers: #{triggers}"
      end
    end

    attr_reader :name, :scope, :shard, :updated_at

    def initialize(name:, scope:, shard: 0, updated_at: nil)
      unless name.is_a?(String)
        raise TriggerGroupInputError.new "invalid group name: '#{name}'"
      end
      if name.include?('_')
        raise TriggerGroupInputError.new "group name '#{name}' can not include an underscore"
      end
      super("#{scope}#{PRIMARY_KEY}", name: name, scope: scope)
      @microservice_name = "#{scope}__TRIGGER_GROUP__#{name}"
      @shard = shard.to_i # to_i to handle nil
      @updated_at = updated_at
    end

    def create(update: false)
      super(update: update)
      notify(kind: 'created')
    end

    # @return [String] generated from the TriggerModel
    def to_s
      return "OpenC3::TriggerGroupModel:#{@scope}:#{@name})"
    end

    # @return [Hash] generated from the TriggerGroupModel
    def as_json(*a)
      return {
        'name' => @name,
        'scope' => @scope,
        'shard' => @shard,
        'updated_at' => @updated_at,
      }
    end

    # @return [TriggerGroupModel] Model generated from the passed JSON
    def self.from_json(json, name:, scope:)
      json = JSON.parse(json, allow_nan: true, create_additions: true) if String === json
      raise "json data is nil" if json.nil?
      self.new(**json.transform_keys(&:to_sym), name: name, scope: scope)
    end

    # @return [] update the redis stream / trigger topic that something has changed
    def notify(kind:, error: nil)
      data = as_json()
      data['error'] = error unless error.nil?
      notification = {
        'kind' => kind,
        'type' => 'group',
        'data' => JSON.generate(data, allow_nan: true),
      }
      AutonomicTopic.write_notification(notification, scope: @scope)
    end

    def create_microservice(topics:)
      # reaction Microservice
      microservice = MicroserviceModel.new(
        name: @microservice_name,
        folder_name: nil,
        cmd: ['ruby', "trigger_group_microservice.rb", @microservice_name],
        work_dir: '/openc3-enterprise/lib/openc3-enterprise/microservices',
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
      topics = ["#{@scope}__openc3_autonomic"]
      if MicroserviceModel.get_model(name: @microservice_name, scope: @scope).nil?
        create_microservice(topics: topics)
        notify(kind: 'deployed')
      end
    end

    def undeploy
      if TriggerModel.names(scope: scope, group: name).empty?
        model = MicroserviceModel.get_model(name: @microservice_name, scope: @scope)
        if model
          model.destroy
          notify(kind: 'undeployed')
        end
      end
    end
  end
end
