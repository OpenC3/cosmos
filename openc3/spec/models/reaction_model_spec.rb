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

require 'spec_helper'
require 'openc3/models/reaction_model'
require 'openc3/models/trigger_group_model'
require 'openc3/models/trigger_model'

module OpenC3
  describe ReactionModel do
    RMO_GROUP = 'GROUP'

    def generate_trigger_group_model(name: RMO_GROUP)
      return TriggerGroupModel.new(name: name, scope: $openc3_scope)
    end

    def generate_custom_trigger(
      name: 'TRIG1',
      left: {'type' => 'float', 'float' => '9000'},
      operator: '>',
      right: {'type' => 'float', 'float' => '42'}
    )
      return TriggerModel.new(
        name: name,
        scope: $openc3_scope,
        group: RMO_GROUP,
        left: left,
        operator: operator,
        right: right,
        dependents: []
      )
    end

    def generate_custom_reaction(
      name: 'REACT1',
      snooze: 300,
      triggers: [{'name' => 'TRIG1', 'group' => RMO_GROUP}],
      trigger_level: 'EDGE',
      actions: [{'type' => 'command', 'value' => 'TEST'}]
    )
      return ReactionModel.new(
        name: name,
        scope: $openc3_scope,
        snooze: snooze,
        triggers: triggers,
        trigger_level: trigger_level,
        actions: actions
      )
    end

    def generate_reaction(name: 'REACT1')
      generate_custom_trigger().create()
      reaction = generate_custom_reaction(name: name)
      reaction.create()
      return reaction
    end

    before(:each) do
      mock_redis()
      generate_trigger_group_model().create()
    end

    describe "self.create_unique_name" do
      it "creates a unique name using a count" do
        name = ReactionModel.create_unique_name(scope: $openc3_scope)
        expect(name).to eql 'REACT1' # By default it creates REACT1
        generate_reaction(name: 'REACT9')
        name = ReactionModel.create_unique_name(scope: $openc3_scope)
        expect(name).to eql 'REACT10' # Previous is 9 so now 10
      end
    end

    describe "check attr_reader" do
      it "OpenC3::ReactionModel" do
        model = generate_reaction()
        expect(model.name).to eql('REACT1')
        expect(model.scope).to eql($openc3_scope)
        expect(model.enabled).to be_truthy()
        expect(model.snooze).to eql(300)
        expect(model.snoozed_until).to be_nil()
        expect(model.triggers.empty?).to be_falsey()
        expect(model.actions.empty?).to be_falsey()
      end
    end

    describe "self.all" do
      it "scope separation returns no trigger models" do
        generate_reaction()
        all = ReactionModel.all(scope: 'NOPE')
        expect(all.empty?).to be_truthy()
      end
    end

    describe "self.all" do
      it "returns all the reactions" do
        generate_reaction()
        all = ReactionModel.all(scope: $openc3_scope)
        expect(all.empty?).to be_falsey()
        expect(all['REACT1'].empty?).to be_falsey()
        expect(all['REACT1']['name']).to eql('REACT1')
        expect(all['REACT1']['scope']).to eql($openc3_scope)
        expect(all['REACT1']['triggers']).to_not be_nil()
        expect(all['REACT1']['actions']).to_not be_nil()
      end
    end

    describe "self.names" do
      it "returns reaction names" do
        generate_reaction()
        all = ReactionModel.names(scope: $openc3_scope)
        expect(all.empty?).to be_falsey()
        expect(all[0]).to eql('REACT1')
      end
    end

    describe "self.get" do
      it "returns a single reaction model" do
        generate_reaction()
        foobar = ReactionModel.get(name: 'REACT1', scope: $openc3_scope)
        expect(foobar.name).to eql('REACT1')
        expect(foobar.scope).to eql($openc3_scope)
        expect(foobar.triggers.empty?).to be_falsey()
        expect(foobar.actions.empty?).to be_falsey()
      end
    end

    describe "self.delete" do
      it "raise if the reaction does not exist" do
        expect { ReactionModel.delete(name: 'NOPE', scope: $openc3_scope) }.to raise_error("reaction 'NOPE' does not exist")
      end

      it "delete an reaction" do
        generate_reaction()
        ReactionModel.delete(name: 'REACT1', scope: $openc3_scope)
        all = ReactionModel.all(scope: $openc3_scope)
        expect(all.empty?).to be_truthy()
        trigger = TriggerModel.get(name: 'TRIG1', group: RMO_GROUP, scope: $openc3_scope)
        expect(trigger.dependents.empty?).to be_truthy()
      end
    end

    describe "initialize" do
      it "raises with a duplicate name" do
        generate_reaction()
        expect { generate_custom_reaction().create() }.to raise_error("existing reaction found: REACT1")
      end

      it "validates trigger_level" do
        generate_reaction()
        expect { generate_custom_reaction(trigger_level: 'HIGH') }.to raise_error("invalid trigger level, must be EDGE or LEVEL: HIGH")
      end

      it "validates snooze" do
        generate_reaction()
        generate_custom_reaction(snooze: '10') # We automatically convert valid string numbers
        expect { generate_custom_reaction(snooze: '10.5') }.to raise_error("invalid snooze value: 10.5")
        expect { generate_custom_reaction(snooze: 'MORE') }.to raise_error("invalid snooze value: MORE")
      end

      it "validates triggers" do
        generate_reaction()
        expect { generate_custom_reaction(triggers: 'TRIG1') }.to raise_error("invalid triggers, must be array of hashes: TRIG1")
        expect { generate_custom_reaction(triggers: ['TRIG1']) }.to raise_error("invalid trigger, must be hash: TRIG1")
        expect { generate_custom_reaction(triggers: [{'name' => 'TRIG1'}]) }.to raise_error(/invalid trigger, must contain 'name' and 'group' keys/)
        triggers = [
          {'name' => 'TRIG1', 'group' => RMO_GROUP},
          {'name' => 'TRIG1', 'group' => RMO_GROUP} # duplicate
        ]
        expect { generate_custom_reaction(triggers: triggers) }.to raise_error(/no duplicate triggers allowed/)
      end

      it "validates actions" do
        generate_reaction()
        expect { generate_custom_reaction(actions: 'command') }.to raise_error("invalid actions, must be array of hashes: command")
        expect { generate_custom_reaction(actions: ['command']) }.to raise_error("invalid action, must be a hash: command")
        expect { generate_custom_reaction(actions: [{'value' => 'TEST'}]) }.to raise_error(/invalid action, must contain 'type'/)
        expect { generate_custom_reaction(actions: [{'type' => 'command'}]) }.to raise_error(/invalid action, must contain 'value'/)
        actions = [
          {'type' => 'other', 'value' => 'TEST'}
        ]
        expect { generate_custom_reaction(actions: actions) }.to raise_error("invalid action type 'other', must be one of [\"script\", \"command\", \"notify\"]")
      end
    end

    describe "notify_enable and notify_disable" do
      it "changes enabled to true and false" do
        model = generate_reaction()
        model.notify_disable()
        expect(model.enabled).to be_falsey()
        model.notify_enable()
        expect(model.enabled).to be_truthy()
      end
    end

    describe "sleep and awaken" do
      it "disable and then enable trigger" do
        model = generate_reaction()
        model.sleep()
        expect(model.snoozed_until).to be_within(1).of(Time.now.to_i + 300)
        model.awaken()
        expect(model.snoozed_until).to be nil
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        model = generate_reaction()
        json = model.as_json(:allow_nan => true)
        expect(json['name']).to eql('REACT1')
        expect(json['scope']).to eql($openc3_scope)
        expect(json['snooze']).to eql(300)
        expect(json['triggers']).to_not be_nil()
        expect(json['actions']).to_not be_nil()
      end
    end

    describe "single reaction test" do
      it "create an reaction that references an invalid triggers" do
        expect {
          generate_custom_reaction(
            triggers: ['bad-trigger'],
          ).create()
        }.to raise_error(ReactionInputError)
        expect {
          generate_custom_reaction(
            triggers: [{'name' => 'bad-trigger', 'group' => RMO_GROUP}],
          ).create()
        }.to raise_error(ReactionInputError)
      end
    end

    describe "single reaction test" do
      it "create an reaction that uses a bad action" do
        expect {
          generate_custom_reaction(
            actions: [{'type' => 'meow', 'data' => 'TEST'}]
          ).create()
        }.to raise_error(ReactionInputError)
        expect {
          generate_custom_reaction(
            actions: [{'type' => 'command'}]
          ).create()
        }.to raise_error(ReactionInputError)
      end
    end

    describe "deploy" do
      it "creates a MicroserviceModel" do
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:create)
        # Verify the microservices that are started
        expect(MicroserviceModel).to receive(:new).with(hash_including(
                                                          name: "#{$openc3_scope}__OPENC3__REACTION",
                                                          topics: ["#{$openc3_scope}__openc3_autonomic"],
                                                          scope: $openc3_scope
                                                        )).and_return(umodel)
        model = generate_reaction()
        model.deploy()
      end
    end

    describe "delete / undeploy" do
      it "only destroys the MicroserviceModel if no associated triggers" do
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:destroy)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel)
        model = generate_reaction()
        model.undeploy() # This does nothing because we have reactions
        # delete calls undeploy
        ReactionModel.delete(name: 'REACT1', scope: $openc3_scope)
      end
    end
  end
end
