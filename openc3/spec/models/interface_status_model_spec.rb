# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/models/interface_status_model'
require 'openc3/models/interface_model'
require 'openc3/models/router_model'
require 'openc3/models/router_status_model'

module OpenC3
  describe InterfaceStatusModel, type: :model do
    before(:each) do
      mock_redis()
      InterfaceStatusModel.instance_variable_set(:@shard_cache, {})
    end

    describe "initialize" do
      it "creates new" do
        model = InterfaceStatusModel.new(name: 'IS', state: 'up', scope: 'DEFAULT')
        expect(model).to be_a(InterfaceStatusModel)
      end
    end

    describe "as_json" do
      it "returns all attributes" do
        model = InterfaceStatusModel.new(name: 'IS', state: 'up', scope: 'DEFAULT')
        expect(model.as_json()['name']).to eq('IS')
        expect(model.as_json()['state']).to eq('up')
      end
    end

    describe "self.get" do
      it "returns nil for nonexistent" do
        name = InterfaceStatusModel.get(name: 'IS', scope: 'DEFAULT')
        expect(name).to be_nil
      end

      it "returns status from correct shard" do
        # Create an InterfaceModel with target_shard 0 (default)
        InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT").create
        # Create and store the status
        InterfaceStatusModel.set({ name: 'TEST_INT', state: 'CONNECTED' }, scope: 'DEFAULT')
        result = InterfaceStatusModel.get(name: 'TEST_INT', scope: 'DEFAULT')
        expect(result['name']).to eq('TEST_INT')
        expect(result['state']).to eq('CONNECTED')
      end

      it "returns status when base model has non-zero target_shard" do
        InterfaceModel.new(name: "SHARD_INT", scope: "DEFAULT", target_shard: 1).create
        InterfaceStatusModel.set({ name: 'SHARD_INT', state: 'ATTEMPTING' }, scope: 'DEFAULT')
        result = InterfaceStatusModel.get(name: 'SHARD_INT', scope: 'DEFAULT')
        expect(result['name']).to eq('SHARD_INT')
        expect(result['state']).to eq('ATTEMPTING')
      end
    end

    describe "self.names" do
      it "returns empty for no statuses" do
        names = InterfaceStatusModel.names(scope: 'DEFAULT')
        expect(names).to eq([])
      end

      it "returns names across shards" do
        InterfaceModel.new(name: "INT1", scope: "DEFAULT", target_shard: 0).create
        InterfaceModel.new(name: "INT2", scope: "DEFAULT", target_shard: 1).create
        InterfaceStatusModel.set({ name: 'INT1', state: 'CONNECTED' }, scope: 'DEFAULT')
        InterfaceStatusModel.set({ name: 'INT2', state: 'DISCONNECTED' }, scope: 'DEFAULT')
        names = InterfaceStatusModel.names(scope: 'DEFAULT')
        expect(names).to contain_exactly('INT1', 'INT2')
      end
    end

    describe "self.all" do
      it "returns empty for no statuses" do
        all = InterfaceStatusModel.all(scope: 'DEFAULT')
        expect(all).to eq({})
      end

      it "returns all statuses across shards" do
        InterfaceModel.new(name: "INT1", scope: "DEFAULT", target_shard: 0).create
        InterfaceModel.new(name: "INT2", scope: "DEFAULT", target_shard: 1).create
        InterfaceStatusModel.set({ name: 'INT1', state: 'CONNECTED' }, scope: 'DEFAULT')
        InterfaceStatusModel.set({ name: 'INT2', state: 'DISCONNECTED' }, scope: 'DEFAULT')
        all = InterfaceStatusModel.all(scope: 'DEFAULT')
        expect(all.keys).to contain_exactly('INT1', 'INT2')
        expect(all['INT1']['state']).to eq('CONNECTED')
        expect(all['INT2']['state']).to eq('DISCONNECTED')
      end
    end

    describe "create and destroy" do
      it "creates and destroys on the correct shard" do
        InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT", target_shard: 1).create
        model = InterfaceStatusModel.new(name: 'TEST_INT', state: 'CONNECTED', scope: 'DEFAULT')
        model.create(force: true)
        result = InterfaceStatusModel.get(name: 'TEST_INT', scope: 'DEFAULT')
        expect(result['state']).to eq('CONNECTED')
        model.destroy
        result = InterfaceStatusModel.get(name: 'TEST_INT', scope: 'DEFAULT')
        expect(result).to be_nil
      end
    end

    describe "_shard_for_name" do
      it "returns 0 when base model does not exist" do
        shard = InterfaceStatusModel._shard_for_name('NONEXISTENT', scope: 'DEFAULT')
        expect(shard).to eq(0)
      end

      it "returns target_shard from InterfaceModel" do
        InterfaceModel.new(name: "MY_INT", scope: "DEFAULT", target_shard: 2).create
        shard = InterfaceStatusModel._shard_for_name('MY_INT', scope: 'DEFAULT')
        expect(shard).to eq(2)
      end
    end

    describe "_active_shards" do
      it "always includes shard 0" do
        shards = InterfaceStatusModel._active_shards(scope: 'DEFAULT')
        expect(shards).to include(0)
      end

      it "includes all unique target_shards from InterfaceModels" do
        InterfaceModel.new(name: "INT1", scope: "DEFAULT", target_shard: 0).create
        InterfaceModel.new(name: "INT2", scope: "DEFAULT", target_shard: 2).create
        InterfaceModel.new(name: "INT3", scope: "DEFAULT", target_shard: 2).create
        shards = InterfaceStatusModel._active_shards(scope: 'DEFAULT')
        expect(shards).to contain_exactly(0, 2)
      end
    end
  end

  describe RouterStatusModel, type: :model do
    before(:each) do
      mock_redis()
      RouterStatusModel.instance_variable_set(:@shard_cache, {})
    end

    describe "self.get" do
      it "returns status from correct shard" do
        RouterModel.new(name: "TEST_RTR", scope: "DEFAULT", target_shard: 1).create
        RouterStatusModel.set({ name: 'TEST_RTR', state: 'CONNECTED' }, scope: 'DEFAULT')
        result = RouterStatusModel.get(name: 'TEST_RTR', scope: 'DEFAULT')
        expect(result['name']).to eq('TEST_RTR')
        expect(result['state']).to eq('CONNECTED')
      end
    end

    describe "_shard_for_name" do
      it "returns target_shard from RouterModel" do
        RouterModel.new(name: "MY_RTR", scope: "DEFAULT", target_shard: 3).create
        shard = RouterStatusModel._shard_for_name('MY_RTR', scope: 'DEFAULT')
        expect(shard).to eq(3)
      end
    end
  end
end
