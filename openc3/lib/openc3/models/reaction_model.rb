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

require 'openc3/models/model'
require 'openc3/models/trigger_model'
require 'openc3/models/microservice_model'
require 'openc3/topics/autonomic_topic'

module OpenC3
  class ReactionError < StandardError; end
  class ReactionInputError < ReactionError; end

  class ReactionModel < Model
    PRIMARY_KEY = '__openc3__reaction'.freeze
    SCRIPT_REACTION = 'script'.freeze
    COMMAND_REACTION = 'command'.freeze
    NOTIFY_REACTION = 'notify'.freeze
    ACTION_TYPES = [SCRIPT_REACTION, COMMAND_REACTION, NOTIFY_REACTION]

    def self.create_unique_name(scope:)
      reaction_names = self.names(scope: scope) # comes back sorted
      num = 1 # Users count with 1
      if reaction_names[-1]
        num = reaction_names[-1][5..-1].to_i + 1
      end
      return "REACT#{num}"
    end

    # @return [ReactionModel] Return the object with the name at
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
        raise ReactionInputError.new "reaction '#{name}' does not exist"
      end
      model.triggers.each do | trigger |
        trigger_model = TriggerModel.get(name: trigger['name'], group: trigger['group'], scope: scope)
        trigger_model.update_dependents(dependent: name, remove: true)
        trigger_model.update()
      end
      Store.hdel("#{scope}#{PRIMARY_KEY}", name)
      # No notification as this is only called via reaction_controller which already notifies

      # undeploy only actually runs if no reactions are left
      model.undeploy()
    end

    attr_reader :name, :scope, :snooze, :triggers, :actions, :enabled, :trigger_level, :snoozed_until
    attr_accessor :username, :shard

    def initialize(
      name:,
      scope:,
      snooze:,
      actions:,
      triggers:,
      trigger_level:,
      enabled: true,
      snoozed_until: nil,
      username: nil,
      shard: 0,
      updated_at: nil
    )
      super("#{scope}#{PRIMARY_KEY}", name: name, scope: scope)
      @microservice_name = "#{scope}__OPENC3__REACTION"
      @enabled = enabled
      @snoozed_until = snoozed_until
      @trigger_level = validate_level(trigger_level)
      @snooze = validate_snooze(snooze)
      @actions = validate_actions(actions)
      @triggers = validate_triggers(triggers)
      @username = username
      @shard = shard.to_i # to_i to handle nil
      @updated_at = updated_at
    end

    # Modifiers for the reaction_controller update action
    def trigger_level=(trigger_level)
      @trigger_level = validate_level(trigger_level)
    end
    def snooze=(snooze)
      @snooze = validate_snooze(snooze)
    end
    def actions=(actions)
      @actions = validate_actions(actions)
    end
    def triggers=(triggers)
      @triggers = validate_triggers(triggers)
    end

    def validate_level(level)
      case level
      when 'EDGE', 'LEVEL'
        return level
      else
        raise ReactionInputError.new "invalid trigger level, must be EDGE or LEVEL: #{level}"
      end
    end

    def validate_snooze(snooze)
      Integer(snooze)
    rescue
      raise ReactionInputError.new "invalid snooze value: #{snooze}"
    end

    def validate_triggers(triggers)
      unless triggers.is_a?(Array)
        raise ReactionInputError.new "invalid triggers, must be array of hashes: #{triggers}"
      end
      trigger_hash = Hash.new()
      triggers.each do | trigger |
        unless trigger.is_a?(Hash)
          raise ReactionInputError.new "invalid trigger, must be hash: #{trigger}"
        end
        if trigger['name'].nil? || trigger['group'].nil?
          raise ReactionInputError.new "invalid trigger, must contain 'name' and 'group' keys: #{trigger}"
        end
        trigger_name = trigger['name']
        unless trigger_hash[trigger_name].nil?
          raise ReactionInputError.new "no duplicate triggers allowed: #{triggers}"
        else
          trigger_hash[trigger_name] = 1
        end
      end
      return triggers
    end

    def validate_actions(actions)
      unless actions.is_a?(Array)
        raise ReactionInputError.new "invalid actions, must be array of hashes: #{actions}"
      end
      actions.each do | action |
        unless action.is_a?(Hash)
          raise ReactionInputError.new "invalid action, must be a hash: #{action}"
        end
        action_type = action['type']
        if action_type.nil?
          raise ReactionInputError.new "invalid action, must contain 'type': #{action}"
        elsif action['value'].nil?
          raise ReactionInputError.new "invalid action, must contain 'value': #{action}"
        end
        unless ACTION_TYPES.include?(action_type)
          raise ReactionInputError.new "invalid action type '#{action_type}', must be one of #{ACTION_TYPES}"
        end
      end
      return actions
    end

    def verify_triggers
      trigger_models = []
      @triggers.each do | trigger |
        model = TriggerModel.get(name: trigger['name'], group: trigger['group'], scope: @scope)
        if model.nil?
          raise ReactionInputError.new "failed to find trigger: #{trigger}"
        end
        trigger_models << model
      end
      if trigger_models.empty?
        raise ReactionInputError.new "reaction must contain at least one valid trigger: #{@triggers}"
      end
      trigger_models.each do | trigger_model |
        trigger_model.update_dependents(dependent: @name)
        trigger_model.update()
      end
    end

    def create
      unless Store.hget(@primary_key, @name).nil?
        raise ReactionInputError.new "existing reaction found: #{@name}"
      end
      verify_triggers()
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(, allow_nan: true)))
      notify(kind: 'created')
    end

    def update
      verify_triggers()
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(, allow_nan: true)))
      # No notification as this is only called via reaction_controller which already notifies
    end

    def notify_enable
      @enabled = true
      notify(kind: 'enabled')
      # update() will be called by the reaction_microservice
    end

    def notify_disable
      @enabled = false
      # disabling clears the snooze so when it's enabled it can immediately run
      @snoozed_until = nil
      notify(kind: 'disabled')
      # update() will be called by the reaction_microservice
    end

    def notify_execute
      # Set updated_at because the event is all we get ... no update later
      @updated_at = Time.now.to_nsec_from_epoch
      notify(kind: 'executed')
    end

    def sleep
      if @snooze > 0
        @snoozed_until = Time.now.to_i + @snooze
        @updated_at = Time.now.to_nsec_from_epoch
        Store.hset(@primary_key, @name, JSON.generate(as_json(, allow_nan: true)))
        notify(kind: 'snoozed')
      end
    end

    def awaken
      @snoozed_until = nil
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(, allow_nan: true)))
      notify(kind: 'awakened')
    end

    # @return [Hash] generated from the ReactionModel
    def as_json(*a)
      return {
        'name' => @name,
        'scope' => @scope,
        'enabled' => @enabled,
        'trigger_level' => @trigger_level,
        'snooze' => @snooze,
        'snoozed_until' => @snoozed_until,
        'triggers' => @triggers,
        'actions' => @actions,
        'username' => @username,
        'shard' => @shard,
        'updated_at' => @updated_at
      }
    end

    # @return [ReactionModel] Model generated from the passed JSON
    def self.from_json(json, name:, scope:)
      json = JSON.parse(json, allow_nan: true, create_additions: true) if String === json
      raise "json data is nil" if json.nil?
      self.new(**json.transform_keys(&:to_sym), name: name, scope: scope)
    end

    # @return [] update the redis stream / reaction topic that something has changed
    def notify(kind:)
      notification = {
        'kind' => kind,
        'type' => 'reaction',
        'data' => JSON.generate(as_json(, allow_nan: true)),
      }
      AutonomicTopic.write_notification(notification, scope: @scope)
    end

    def create_microservice(topics:)
      # reaction Microservice
      microservice = MicroserviceModel.new(
        name: @microservice_name,
        folder_name: nil,
        cmd: ['ruby', 'reaction_microservice.rb', @microservice_name],
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
      end
    end

    def undeploy
      return unless ReactionModel.names(scope: @scope).empty?

      model = MicroserviceModel.get_model(name: @microservice_name, scope: @scope)
      if model
        # Let the frontend know that the microservice is shutting down
        # Custom event which matches the 'deployed' event in ReactionMicroservice
        notification = {
          'kind' => 'undeployed',
          'type' => 'reaction',
          # name and updated_at fields are required for Event formatting
          'data' => JSON.generate({
            'name' => @microservice_name,
            'updated_at' => Time.now.to_nsec_from_epoch,
          }),
        }
        AutonomicTopic.write_notification(notification, scope: @scope)
        model.destroy
      end
    end
  end
end
