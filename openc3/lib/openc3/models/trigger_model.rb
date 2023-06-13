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
require 'openc3/models/target_model'
require 'openc3/models/trigger_group_model'
require 'openc3/models/reaction_model'
require 'openc3/topics/autonomic_topic'

module OpenC3
  class TriggerError < StandardError; end
  class TriggerInputError < TriggerError; end

  # INPUT:
  #  {
  #    "group": "someGroup",
  #    "left": {
  #      "type": "item",
  #      "target": "INST",
  #      "packet": "ADCS",
  #      "item": "POSX",
  #      "valueType": "RAW",
  #    },
  #    "operator": ">",
  #    "right": {
  #      "type": "value",
  #      "value": 690000,
  #    }
  #  }
  class TriggerModel < Model
    PRIMARY_KEY = '__TRIGGERS__'.freeze
    ITEM_TYPE = 'item'.freeze
    LIMIT_TYPE = 'limit'.freeze
    FLOAT_TYPE = 'float'.freeze
    STRING_TYPE = 'string'.freeze
    REGEX_TYPE = 'regex'.freeze
    TRIGGER_TYPE = 'trigger'.freeze

    def self.create_unique_name(group:, scope:)
      trigger_names = self.names(group: group, scope: scope) # comes back sorted
      num = 1 # Users count with 1
      # TODO: Create migration to rename triggers to 'TRIGX'
      if trigger_names[-1]
        num = trigger_names[-1][4..-1].to_i + 1
      end
      return "TRIG#{num}"
    end

    # @return [TriggerModel] Return the object with the name at
    def self.get(name:, group:, scope:)
      json = super("#{scope}#{PRIMARY_KEY}#{group}", name: name)
      unless json.nil?
        self.from_json(json, name: name, scope: scope)
      end
    end

    # @return [Array<Hash>] All the Key, Values stored under the name key
    def self.all(group:, scope:)
      super("#{scope}#{PRIMARY_KEY}#{group}")
    end

    # @return [Array<String>] All the uuids stored under the name key
    def self.names(group:, scope:)
      super("#{scope}#{PRIMARY_KEY}#{group}")
    end

    # Check dependents before delete.
    def self.delete(name:, group:, scope:)
      model = self.get(name: name, group: group, scope: scope)
      if model.nil?
        raise TriggerInputError.new "trigger '#{name}' in group '#{group}' does not exist"
      end
      unless model.dependents.empty?
        raise TriggerError.new "failed to delete #{name} due to dependents: #{model.dependents}"
      end
      model.roots.each do | trigger |
        trigger_model = self.get(name: trigger, group: group, scope: scope)
        trigger_model.update_dependents(dependent: name, remove: true)
        trigger_model.update()
      end
      ReactionModel.all(scope: @scope).each do |reaction|
        pp reaction
        selected = reaction.triggers.select {|trigger| trigger['name'] != name }
        pp selected
        if selected != reaction.triggers
          reaction.triggers = selected
          reaction.update()
        end
      end

      Store.hdel("#{scope}#{PRIMARY_KEY}#{group}", name)
      model.notify(kind: 'deleted')
    end

    attr_reader :name, :scope, :state, :group, :active, :left, :operator, :right, :dependents, :roots

    def initialize(
      name:,
      scope:,
      group:,
      left:,
      operator:,
      right:,
      state: false,
      active: true,
      dependents: nil,
      updated_at: nil
    )
      super("#{scope}#{PRIMARY_KEY}#{group}", name: name, scope: scope)
      @roots = []
      @group = group
      @state = state
      @active = active
      @left = validate_operand(operand: left)
      @operator = validate_operator(operator: operator)
      @right = validate_operand(operand: right, right: true)
      @dependents = dependents
      @updated_at = updated_at
      selected_group = TriggerGroupModel.get(name: @group, scope: @scope)
      if selected_group.nil?
        raise TriggerInputError.new "failed to find group: #{@group}"
      end
    end

    def validate_operand(operand:, right: false)
      return operand if right and @operator.include?('CHANGE')
      unless operand.is_a?(Hash)
        raise TriggerInputError.new "invalid operand: #{operand}"
      end
      operand_types = [ITEM_TYPE, LIMIT_TYPE, FLOAT_TYPE, STRING_TYPE, REGEX_TYPE, TRIGGER_TYPE]
      unless operand_types.include?(operand['type'])
        raise TriggerInputError.new "invalid operand, type '#{operand['type']}' must be one of #{operand_types}"
      end
      if operand[operand['type']].nil?
        raise TriggerInputError.new "invalid operand, type value '#{operand['type']}' must be a key: #{operand}"
      end
      case operand['type']
      when ITEM_TYPE
        # We don't need to check for 'item' because the above check already does it
        if operand['target'].nil? || operand['packet'].nil? || operand['valueType'].nil?
          raise TriggerInputError.new "invalid operand, must contain target, packet, item and valueType: #{operand}"
        end
      when TRIGGER_TYPE
        @roots << operand[operand['type']]
      end
      return operand
    end

    def validate_operator(operator:)
      operators = ['>', '<', '>=', '<=', '==', '!=', 'CHANGES', 'DOES NOT CHANGE']
      trigger_operators = ['AND', 'OR']
      if @roots.empty? && operators.include?(operator)
        return operator
      elsif !@roots.empty? && trigger_operators.include?(operator)
        return operator
      elsif operators.include?(operator)
        raise TriggerInputError.new "invalid operator for triggers: '#{operator}' must be one of #{trigger_operators}"
      else
        raise TriggerInputError.new "invalid operator: '#{operator}' must be one of #{operators}"
      end
    end

    def verify_triggers
      @dependents = [] if @dependents.nil?
      @roots.each do | trigger |
        model = TriggerModel.get(name: trigger, group: @group, scope: @scope)
        if model.nil?
          raise TriggerInputError.new "failed to find dependent trigger: #{trigger}"
        end
        unless model.dependents.include?(@name)
          model.update_dependents(dependent: @name)
          model.update()
        end
      end
    end

    def create
      unless Store.hget(@primary_key, @name).nil?
        raise TriggerInputError.new "existing trigger found: #{@name}"
      end
      verify_triggers()
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(:allow_nan => true)))
      notify(kind: 'created')
    end

    def update
      verify_triggers()
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(:allow_nan => true)))
      notify(kind: 'updated')
    end

    def enable
      @state = true
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(:allow_nan => true)))
      notify(kind: 'enabled')
    end

    def disable
      @state = false
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(:allow_nan => true)))
      notify(kind: 'disabled')
    end

    def activate
      @active = true
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(:allow_nan => true)))
      notify(kind: 'activated')
    end

    def deactivate
      @active = false
      @state = false
      @updated_at = Time.now.to_nsec_from_epoch
      Store.hset(@primary_key, @name, JSON.generate(as_json(:allow_nan => true)))
      notify(kind: 'deactivated')
    end

    # ["#{@scope}__DECOM__{#{@target}}__#{@packet}"]
    def generate_topics
      topics = Hash.new
      if @left['type'] == ITEM_TYPE
        topics["#{@scope}__DECOM__{#{left['target']}}__#{left['packet']}"] = 1
      end
      if @right and @right['type'] == ITEM_TYPE
        topics["#{@scope}__DECOM__{#{right['target']}}__#{right['packet']}"] = 1
      end
      return topics.keys
    end

    def update_dependents(dependent:, remove: false)
      if remove
        @dependents.delete(dependent)
      elsif @dependents.index(dependent).nil?
        @dependents << dependent
      end
    end

    # @return [String] generated from the TriggerModel
    def to_s
      return "OpenC3::TriggerModel:#{@scope}:#{group}:#{@name})"
    end

    # @return [Hash] generated from the TriggerModel
    def as_json(*a)
      return {
        'name' => @name,
        'scope' => @scope,
        'state' => @state,
        'active' => @active,
        'group' => @group,
        'dependents' => @dependents,
        'left' => @left,
        'operator' => @operator,
        'right' => @right,
        'updated_at' => @updated_at,
      }
    end

    # @return [TriggerModel] Model generated from the passed JSON
    def self.from_json(json, name:, scope:)
      json = JSON.parse(json, :allow_nan => true, :create_additions => true) if String === json
      raise "json data is nil" if json.nil?

      json.transform_keys!(&:to_sym)
      self.new(**json, name: name, scope: scope)
    end

    # @return [] update the redis stream / trigger topic that something has changed
    def notify(kind:)
      notification = {
        'kind' => kind,
        'type' => 'trigger',
        'data' => JSON.generate(as_json(:allow_nan => true)),
      }
      AutonomicTopic.write_notification(notification, scope: @scope)
    end
  end
end
