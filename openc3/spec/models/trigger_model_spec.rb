# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/target_model'
require 'openc3/models/trigger_group_model'
require 'openc3/models/trigger_model'

module OpenC3
  describe TriggerModel do
    TMO_GROUP = 'ALPHA'.freeze

    def generate_trigger(
      name: 'TRIG1',
      left: {'type' => 'float', 'float' => '9000'},
      operator: '>',
      right: {'type' => 'float', 'float' => '42'},
      group: TMO_GROUP
    )
      return TriggerModel.new(
        name: name,
        scope: $openc3_scope,
        group: group,
        left: left,
        operator: operator,
        right: right,
        dependents: []
      )
    end

    def generate_trigger_dependent_model
      generate_trigger(name: 'left').create()
      generate_trigger(name: 'right').create()
      trigger = generate_trigger(
        name: 'TRIG1',
        left: {'type' => 'trigger', 'trigger' => 'left'},
        operator: 'AND',
        right: {'type' => 'trigger', 'trigger' => 'right'}
      )
      trigger.create()
      return trigger
    end

    def generate_trigger_group_model(name: TMO_GROUP)
      return TriggerGroupModel.new(name: name, scope: $openc3_scope)
    end

    # Defaults to a real item in the INST target seeded below, so tests only have
    # to spell out the field they are actually exercising
    def item_operand(target: 'INST', packet: 'HEALTH_STATUS', item: 'TEMP1', value_type: 'CONVERTED')
      return {'type' => 'item', 'target' => target, 'packet' => packet, 'item' => item, 'valueType' => value_type}
    end

    # Throwaway right operand for tests which only care about the left one
    FLOAT_ZERO = {'type' => 'float', 'float' => '0'}.freeze

    before(:each) do
      mock_redis()
      # Seed the INST target so item operands reference telemetry that actually exists
      setup_system()
      target = TargetModel.new(folder_name: 'INST', name: 'INST', scope: $openc3_scope)
      target.create
      target.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      generate_trigger_group_model().create()
    end

    describe "self.create_unique_name" do
      it "creates a unique name using a count" do
        name = TriggerModel.create_unique_name(group: TMO_GROUP, scope: $openc3_scope)
        expect(name).to eql 'TRIG1' # By default it creates TRIG1
        generate_trigger(name: 'TRIG9').create()
        name = TriggerModel.create_unique_name(group: TMO_GROUP, scope: $openc3_scope)
        expect(name).to eql 'TRIG10' # Previous is 9 so now 10
      end

      it "handles more than 10 triggers correctly" do
        (1..11).each { |i| generate_trigger(name: "TRIG#{i}").create() }
        name = TriggerModel.create_unique_name(group: TMO_GROUP, scope: $openc3_scope)
        expect(name).to eql 'TRIG12'
      end

      it "handles custom named triggers mixed with auto-generated" do
        generate_trigger(name: 'TRIG1').create()
        generate_trigger(name: 'MyCustomTrig').create()
        generate_trigger(name: 'TRIG5').create()
        name = TriggerModel.create_unique_name(group: TMO_GROUP, scope: $openc3_scope)
        expect(name).to eql 'TRIG6' # Max numeric is 5, so next is 6
      end
    end

    describe "self.all" do
      it "returns all trigger models" do
        generate_trigger().create()
        all = TriggerModel.all(group: TMO_GROUP, scope: $openc3_scope)
        expect(all.empty?).to be_falsey()
        expect(all['TRIG1'].empty?).to be_falsey()
        expect(all['TRIG1']['scope']).to eql($openc3_scope)
        expect(all['TRIG1']['name']).to eql('TRIG1')
        expect(all['TRIG1']['group']).to eql(TMO_GROUP)
        expect(all['TRIG1']['left']).to_not be_nil()
        expect(all['TRIG1']['state']).to be_falsey()
        expect(all['TRIG1']['enabled']).to be_truthy()
        expect(all['TRIG1']['operator']).to eql('>')
        expect(all['TRIG1']['right']).to_not be_nil()
        expect(all['TRIG1']['dependents']).to be_truthy()
        # scope separation returns no trigger models
        all = TriggerModel.all(group: TMO_GROUP, scope: 'TRIG1')
        expect(all.empty?).to be_truthy()
      end
    end

    describe "self.names" do
      it "returns trigger names" do
        generate_trigger().create()
        all = TriggerModel.names(scope: $openc3_scope, group: TMO_GROUP)
        expect(all.empty?).to be_falsey()
        expect(all[0]).to eql('TRIG1')
      end
    end

    describe "self.get" do
      it "returns a single trigger model" do
        generate_trigger().create()
        trigger = TriggerModel.get(name: 'TRIG1', scope: $openc3_scope, group: TMO_GROUP)
        expect(trigger.name).to eql('TRIG1')
        expect(trigger.scope).to eql($openc3_scope)
        expect(trigger.group).to eql(TMO_GROUP)
        expect(trigger.left).to have_key('float')
        expect(trigger.operator).to eql('>')
        expect(trigger.right).to have_key('type')
        expect(trigger.enabled).to be_truthy()
        expect(trigger.state).to be_falsey()
        expect(trigger.dependents.empty?).to be_truthy()
        expect(trigger.roots.empty?).to be_truthy()
      end
    end

    describe "self.delete" do
      it "raises if the trigger does not exist" do
        expect { TriggerModel.delete(name: 'TRIG1', scope: $openc3_scope, group: TMO_GROUP) }.to raise_error("trigger ALPHA:TRIG1 does not exist")
      end

      it "delete a trigger" do
        generate_trigger().create()
        TriggerModel.delete(name: 'TRIG1', scope: $openc3_scope, group: TMO_GROUP)
        all = TriggerModel.all(group: TMO_GROUP, scope: $openc3_scope)
        expect(all.empty?).to be_truthy()
      end
    end

    describe "instance attr_reader" do
      it "OpenC3::TriggerModel" do
        model = generate_trigger()
        expect(model.name).to eql('TRIG1')
        expect(model.scope).to eql($openc3_scope)
        expect(model.group).to eql(TMO_GROUP)
        expect(model.left).to have_key('float')
        expect(model.operator).to eql('>')
        expect(model.right).to have_key('type')
        expect(model.enabled).to be_truthy()
        expect(model.state).to be_falsey()
        expect(model.dependents.empty?).to be_truthy()
        expect(model.roots).to_not be_nil()
      end
    end

    describe "initialize" do
      it "raises with an invalid group" do
        expect { generate_trigger(group: 'NOPE') }.to raise_error("failed to find group: 'NOPE'")
      end

      it "raises with a duplicate name" do
        generate_trigger().create
        expect { generate_trigger().create }.to raise_error("existing trigger found: 'TRIG1'")
      end
    end

    describe "update" do
      it "updates values" do
        model = generate_trigger()
        model.create
        model = TriggerModel.get(name: 'TRIG1', scope: $openc3_scope, group: TMO_GROUP)
        expect(model.left).to eql({'type' => 'float', 'float' => '9000'})
        expect(model.operator).to eql '>'
        expect(model.right).to eql({'type' => 'float', 'float' => '42'})

        update = {
          group: TMO_GROUP,
          left: {'type' => 'string', 'string' => 'ONE'},
          operator: '!=',
          right: {'type' => 'string', 'string' => 'TWO'}
        }
        model = TriggerModel.from_json(update, name: 'TRIG1', scope: $openc3_scope)
        model.update
        model = TriggerModel.get(name: 'TRIG1', scope: $openc3_scope, group: TMO_GROUP)
        expect(model.left).to eql({'type' => 'string', 'string' => 'ONE'})
        expect(model.operator).to eql '!='
        expect(model.right).to eql({'type' => 'string', 'string' => 'TWO'})
      end
    end

    describe "destroy" do
      it "remove an instance of a trigger" do
        generate_trigger().create()
        model = TriggerModel.get(name: 'TRIG1', scope: $openc3_scope, group: TMO_GROUP)
        model.destroy()
        all = TriggerModel.all(group: TMO_GROUP, scope: $openc3_scope)
        expect(all.empty?).to be_truthy()
      end
    end

    describe "disable" do
      it "changes enabled and state to and false" do
        model = generate_trigger()
        model.create()
        model.state = true
        model.disable()
        expect(model.enabled).to be_falsey()
        expect(model.state).to be_falsey()
      end
    end

    describe "state=" do
      it "changes state" do
        model = generate_trigger()
        model.state = false
        expect(model.state).to be_falsey()
        model.state = true
        expect(model.state).to be_truthy()
      end
    end


    describe "instance as_json" do
      it "encodes all the input parameters" do
        json = generate_trigger().as_json()
        expect(json['name']).to eql('TRIG1')
        expect(json['scope']).to eql($openc3_scope)
        expect(json['enabled']).to be_truthy()
        expect(json['state']).to be_falsey()
        expect(json['group']).to eql(TMO_GROUP)
        expect(json['left']).to_not be_nil()
        expect(json['operator']).to eql('>')
        expect(json['right']).to_not be_nil()
        expect(json['dependents']).to_not be_nil()
        expect(json['label']).to be_nil()
      end
    end

    describe "label" do
      it "defaults to nil" do
        model = generate_trigger()
        expect(model.label).to be_nil()
        expect(model.as_json()['label']).to be_nil()
      end

      it "persists through create and reload" do
        model = generate_trigger()
        model.label = 'My Trigger'
        model.create()
        loaded = TriggerModel.get(name: 'TRIG1', group: TMO_GROUP, scope: $openc3_scope)
        expect(loaded.label).to eql('My Trigger')
      end

      it "can be updated and cleared" do
        model = generate_trigger()
        model.create()
        model.label = 'Updated Label'
        model.update()
        loaded = TriggerModel.get(name: 'TRIG1', group: TMO_GROUP, scope: $openc3_scope)
        expect(loaded.label).to eql('Updated Label')
        loaded.label = nil
        loaded.update()
        cleared = TriggerModel.get(name: 'TRIG1', group: TMO_GROUP, scope: $openc3_scope)
        expect(cleared.label).to be_nil()
      end
    end

    describe "trigger operand validation" do
      it "allows nil right when operator is CHANGE oriented" do
        ['CHANGES', 'DOES NOT CHANGE'].each_with_index do |operator, index|
          generate_trigger(
            name: "TRIG#{index}",
            left: item_operand,
            operator: operator,
            right: nil,
          ).create()
        end
      end

      it "allows omitting right entirely when operator is CHANGE oriented" do
        # Simulates strong params filtering nil right from controller payload
        json = {
          'group' => TMO_GROUP,
          'left' => item_operand,
          'operator' => 'DOES NOT CHANGE',
          'label' => nil,
        }
        model = TriggerModel.from_json(json, name: 'TRIG3', scope: $openc3_scope)
        expect(model.right).to be_nil
        model.create()

        json['operator'] = 'CHANGES'
        model = TriggerModel.from_json(json, name: 'TRIG4', scope: $openc3_scope)
        expect(model.right).to be_nil
        model.create()
      end

      it "raises when right is omitted and operator requires it" do
        json = {
          'group' => TMO_GROUP,
          'left' => {'type' => 'item', 'target' => 'TGT', 'packet' => 'PKT', 'item' => 'ITEM', 'valueType' => 'CONVERTED'},
          'operator' => '>',
        }
        expect {
          TriggerModel.from_json(json, name: 'TRIG5', scope: $openc3_scope)
        }.to raise_error(TriggerInputError, /invalid operand/)
      end

      it "raises when given a bad operand" do
        expect {
          generate_trigger(
            left: 'LEFT',
            operator: 'AND',
            right: {'type' => 'trigger', 'trigger' => 'bar'}
          ).create()
        }.to raise_error("invalid operand: LEFT")
      end

      it "raises when operand does not include type value" do
        expect {
          generate_trigger(
            # If type is trigger we must have a trigger key
            left: {'type' => 'trigger', 'value' => 10},
            operator: 'AND',
            right: {'type' => 'trigger', 'trigger' => 'bar'}
          ).create()
        }.to raise_error(TriggerInputError, /invalid operand, type value 'trigger' must be a key/)
      end

      it "raises when references an invalid type" do
        expect {
          generate_trigger(
            left: {'type' => 'right', 'trigger' => 'foo'},
            operator: 'AND',
            right: {'type' => 'trigger', 'trigger' => 'bar'}
          )
        }.to raise_error(/invalid operand, type 'right' must be/)
      end

      # Structural checks which run in initialize. These intentionally use a target
      # that does not exist: they must fail before any item lookup is attempted.
      [
        ['target is missing',
         {'type' => 'item', 'packet' => 'PKT', 'item' => 'ITEM', 'valueType' => 'CONVERTED'},
         /invalid operand, must contain target, packet, item and valueType/],
        ['item is missing',
         {'type' => 'item', 'target' => 'TGT', 'packet' => 'PKT', 'valueType' => 'CONVERTED'},
         /invalid operand, type value 'item' must be a key/],
        ['valueType is missing',
         {'type' => 'item', 'target' => 'TGT', 'packet' => 'PKT', 'item' => 'ITEM'},
         /invalid operand, must contain target, packet, item and valueType/],
      ].each do |description, left, message|
        it "raises when the ITEM operand #{description}" do
          expect {
            generate_trigger(left: left, operator: '>', right: FLOAT_ZERO).create()
          }.to raise_error(TriggerInputError, message)
        end
      end

      # Value checks which only run on create/update via validate_item_operands
      [
        ['the item does not exist',   {item: 'NONEXISTENT'},   /invalid left trigger.*NONEXISTENT.*does not exist/],
        ['the packet does not exist', {packet: 'NONEXISTENT'}, /invalid left trigger.*NONEXISTENT.*does not exist/],
        ['the target does not exist', {target: 'NOPE'},        /invalid left trigger.*does not exist/],
        ['valueType is invalid',      {value_type: 'NOPE'},    /invalid left operand, valueType 'NOPE' must be one of/],
      ].each do |description, overrides, message|
        it "raises when #{description}" do
          expect {
            generate_trigger(left: item_operand(**overrides), operator: '>', right: FLOAT_ZERO).create()
          }.to raise_error(TriggerInputError, message)
        end
      end

      it "allows all the supported valueTypes" do
        TriggerModel::ITEM_VALUE_TYPES.each_with_index do |value_type, index|
          generate_trigger(
            name: "TRIG#{index}",
            left: item_operand(value_type: value_type),
            operator: '>',
            right: FLOAT_ZERO
          ).create()
        end
      end

      it "raises when the right item operand does not exist" do
        expect {
          generate_trigger(
            left: item_operand,
            operator: '>',
            right: item_operand(item: 'NONEXISTENT')
          ).create()
        }.to raise_error(TriggerInputError, /invalid right trigger.*NONEXISTENT.*does not exist/)
      end

      it "does not raise on from_json when a referenced item no longer exists" do
        # An existing trigger must still deserialize if its target is removed, otherwise
        # the TriggerGroupMicroservice fails to load every trigger in the group
        json = {
          'group' => TMO_GROUP,
          'left' => item_operand(target: 'GONE', packet: 'GONE', item: 'GONE'),
          'operator' => '>',
          'right' => FLOAT_ZERO,
        }
        expect { TriggerModel.from_json(json, name: 'TRIG1', scope: $openc3_scope) }.to_not raise_error
      end

      it "does not raise on from_json when valueType was never constrained" do
        # valueType was unvalidated before, so already persisted triggers may hold
        # anything. Deserializing them must not take down the whole trigger group.
        json = {
          'group' => TMO_GROUP,
          'left' => item_operand(value_type: 'raw'),
          'operator' => '>',
          'right' => FLOAT_ZERO,
        }
        model = nil
        expect { model = TriggerModel.from_json(json, name: 'TRIG1', scope: $openc3_scope) }.to_not raise_error
        # But it is rejected if the user tries to save it
        expect { model.create() }.to raise_error(TriggerInputError, /invalid left operand, valueType 'raw' must be one of/)
      end
    end

    describe "trigger operator validation" do
      it "raises with an invalid operator" do
        expect {
          generate_trigger(
            left: {'type' => 'float', 'float' => '10'},
            operator: 'MEOW',
            right: {'type' => 'float', 'float' => '0'}
          )
        }.to raise_error(/invalid operator: 'MEOW'/)

        expect {
          generate_trigger(
            left: {'type' => 'trigger', 'trigger' => 'left'},
            operator: '==',
            right: {'type' => 'trigger', 'trigger' => 'right'}
          )
        }.to raise_error("invalid operator for triggers: '==' must be one of [\"AND\", \"OR\"]")
      end

      it "raises when references an invalid trigger" do
        expect {
          generate_trigger(
            left: {'type' => 'trigger', 'trigger' => 'foo'},
            operator: 'AND',
            right: {'type' => 'trigger', 'trigger' => 'bar'}
          ).create()
        }.to raise_error("failed to find dependent trigger: 'ALPHA:foo'")
      end
    end

    describe "dependent trigger test" do
      it "create a trigger that references another trigger" do
        trigger = generate_trigger_dependent_model()
        expect(trigger.roots.empty?).to be_falsey()
        left = TriggerModel.get(name: 'left', group: TMO_GROUP, scope: $openc3_scope)
        expect(left.dependents.empty?).to be_falsey()
        right = TriggerModel.get(name: 'right', group: TMO_GROUP, scope: $openc3_scope)
        expect(right.dependents.empty?).to be_falsey()
      end

      it "delete a trigger that references another trigger" do
        generate_trigger_dependent_model()
        expect {
          TriggerModel.delete(name: 'left', group: TMO_GROUP, scope: $openc3_scope)
        }.to raise_error(TriggerError)
        all = TriggerModel.all(group: TMO_GROUP, scope: $openc3_scope)
        expect(all.size).to eql(3)
        expect(all.empty?).to be_falsey()
      end

      it "delete a trigger" do
        generate_trigger_dependent_model()
        TriggerModel.delete(name: 'TRIG1', group: TMO_GROUP, scope: $openc3_scope)
        TriggerModel.delete(name: 'left', group: TMO_GROUP, scope: $openc3_scope)
        TriggerModel.delete(name: 'right', group: TMO_GROUP, scope: $openc3_scope)
        all = TriggerModel.all(group: TMO_GROUP, scope: $openc3_scope)
        expect(all.empty?).to be_truthy()
      end

      it "make OR trigger" do
        generate_trigger_dependent_model()
        model = generate_trigger(
          name: 'orTest',
          left: {'type' => 'trigger', 'trigger' => 'left'},
          operator: 'OR',
          right: {'type' => 'trigger', 'trigger' => 'right'}
        )
        model.create()
        all = TriggerModel.all(group: TMO_GROUP, scope: $openc3_scope)
        expect(all.size).to eql(4)
      end
    end

    describe "generate_topics" do
      it "generates single topic for items in the same packet" do
        model = generate_trigger(
          left: item_operand(item: 'TEMP1'),
          operator: '==',
          right: item_operand(item: 'TEMP2'),
        )
        model.create
        expect(model.generate_topics).to eql(["#{$openc3_scope}__DECOM__{INST}__HEALTH_STATUS"])
      end

      it "generates two topics for different target packets" do
        model = generate_trigger(
          left: item_operand(packet: 'HEALTH_STATUS', item: 'TEMP1'),
          operator: '==',
          right: item_operand(packet: 'ADCS', item: 'POSX'),
        )
        model.create
        expect(model.generate_topics).to eql(["#{$openc3_scope}__DECOM__{INST}__HEALTH_STATUS", "#{$openc3_scope}__DECOM__{INST}__ADCS"])
      end
    end
  end
end
