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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/trigger_group_model'
require 'openc3/models/trigger_model'

module OpenC3
  describe TriggerGroupModel do
    TGMO_GROUP = 'GROUP'.freeze

    def generate_trigger_group_model(name: TGMO_GROUP)
      return TriggerGroupModel.new(
        name: name,
        scope: $openc3_scope
      )
    end

    def generate_trigger(
      name: 'foobar',
      left: {'type' => 'float', 'float' => '9000'},
      operator: '>',
      right: {'type' => 'float', 'float' => '42'},
      group: TGMO_GROUP
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

    before(:each) do
      mock_redis()
    end

    describe "self.all" do
      it "returns all trigger models" do
        generate_trigger_group_model().create()
        all = TriggerGroupModel.all(scope: $openc3_scope)
        expect(all.empty?).to be_falsey()
        expect(all[TGMO_GROUP]['name']).to eql(TGMO_GROUP)
        expect(all[TGMO_GROUP]['scope']).to eql($openc3_scope)
        # scope seperation returns no trigger models
        all = TriggerGroupModel.all(scope: 'foobar')
        expect(all.empty?).to be_truthy()
      end
    end

    describe "self.names" do
      it "returns trigger names" do
        generate_trigger_group_model().create()
        all = TriggerGroupModel.names(scope: $openc3_scope)
        expect(all.empty?).to be_falsey()
        expect(all[0]).to eql(TGMO_GROUP)
      end
    end

    describe "self.get" do
      it "returns a single trigger model" do
        generate_trigger_group_model().create()
        foobar = TriggerGroupModel.get(name: TGMO_GROUP, scope: $openc3_scope)
        expect(foobar.name).to eql(TGMO_GROUP)
        expect(foobar.scope).to eql($openc3_scope)
      end
    end

    describe "self.delete" do
      it "deletes a group" do
        generate_trigger_group_model().create()
        TriggerGroupModel.delete(name: TGMO_GROUP, scope: $openc3_scope)
        all = TriggerGroupModel.all(scope: $openc3_scope)
        expect(all.empty?).to be_truthy()
      end

      it "raises if group does not exist" do
        expect { TriggerGroupModel.delete(name: 'NOPE', scope: $openc3_scope) }.to raise_error("group 'NOPE' does not exist")
      end

      it "raises if group has associated triggers" do
        generate_trigger_group_model().create()
        generate_trigger(name: 'TRIG1').create()
        generate_trigger(name: 'TRIG10').create()
        expect { TriggerGroupModel.delete(name: TGMO_GROUP, scope: $openc3_scope) }.to raise_error("group '#{TGMO_GROUP}' has dependent triggers: [\"TRIG1\", \"TRIG10\"]")
      end
    end

    describe "instance attr_reader" do
      it "OpenC3::TriggerModel" do
        model = generate_trigger_group_model()
        expect(model.name).to eql(TGMO_GROUP)
        expect(model.scope).to eql($openc3_scope)
      end
    end

    describe "initialize" do
      it "requires a valid name" do
        expect { TriggerGroupModel.new(name: 10, scope: $openc3_scope) }.to raise_error("invalid group name: '10'")
        expect { TriggerGroupModel.new(name: 'MY_GROUP', scope: $openc3_scope) }.to raise_error("group name 'MY_GROUP' can not include an underscore")
      end

      it "requires a unique name" do
        generate_trigger_group_model().create()
        expect { generate_trigger_group_model().create() }.to raise_error("DEFAULT__TRIGGER__GROUP:GROUP already exists at create")
      end
    end

    describe "instance destroy" do
      it "remove an instance of a trigger" do
        generate_trigger_group_model().create()
        model = TriggerGroupModel.get(name: TGMO_GROUP, scope: $openc3_scope)
        model.destroy()
        all = TriggerGroupModel.all(scope: $openc3_scope)
        expect(all.empty?).to be_truthy()
      end
    end

    describe "instance as_json" do
      it "encodes all the input parameters" do
        json = generate_trigger_group_model().as_json(:allow_nan => true)
        expect(json['name']).to eql(TGMO_GROUP)
        expect(json['scope']).to eql($openc3_scope)
      end
    end

    describe "deploy" do
      it "creates a MicroserviceModel" do
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:create)
        # Verify the microservices that are started
        expect(MicroserviceModel).to receive(:new).with(hash_including(
                                                          name: "#{$openc3_scope}__TRIGGER_GROUP__#{TGMO_GROUP}",
                                                          topics: ["#{$openc3_scope}__openc3_autonomic"],
                                                          scope: $openc3_scope
                                                        )).and_return(umodel)
        model = generate_trigger_group_model()
        model.create()
        model.deploy()
      end
    end

    describe "undeploy" do
      it "only destroys the MicroserviceModel if no associated triggers" do
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:destroy)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel)
        model = generate_trigger_group_model()
        model.undeploy()
      end
    end
  end
end
