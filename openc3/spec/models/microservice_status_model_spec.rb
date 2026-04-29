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
require 'openc3/models/microservice_status_model'
require 'openc3/models/microservice_model'

module OpenC3
  describe MicroserviceStatusModel, type: :model do
    before(:each) do
      mock_redis()
      local_s3()
      MicroserviceStatusModel.instance_variable_set(:@db_shard_cache, {})
    end

    after(:each) do
      local_s3_unset()
    end

    describe "initialize" do
      it "creates new" do
        model = MicroserviceStatusModel.new(name: 'DEFAULT__TYPE__TEST', state: 'RUNNING', scope: 'DEFAULT')
        expect(model).to be_a(MicroserviceStatusModel)
      end
    end

    describe "as_json" do
      it "returns all attributes" do
        model = MicroserviceStatusModel.new(name: 'DEFAULT__TYPE__TEST', state: 'RUNNING', count: 5, scope: 'DEFAULT')
        json = model.as_json()
        expect(json['name']).to eq('DEFAULT__TYPE__TEST')
        expect(json['state']).to eq('RUNNING')
        expect(json['count']).to eq(5)
      end
    end

    describe "self.get" do
      it "returns nil for nonexistent" do
        result = MicroserviceStatusModel.get(name: 'DEFAULT__TYPE__TEST', scope: 'DEFAULT')
        expect(result).to be_nil
      end

      it "returns status from correct db_shard" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__TEST", scope: "DEFAULT").create
        MicroserviceStatusModel.set({ name: 'DEFAULT__TYPE__TEST', state: 'RUNNING' }, scope: 'DEFAULT')
        result = MicroserviceStatusModel.get(name: 'DEFAULT__TYPE__TEST', scope: 'DEFAULT')
        expect(result['name']).to eq('DEFAULT__TYPE__TEST')
        expect(result['state']).to eq('RUNNING')
      end

      it "returns status when base model has non-zero db_shard" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__DB_SHARD", scope: "DEFAULT", db_shard: 1).create
        MicroserviceStatusModel.set({ name: 'DEFAULT__TYPE__DB_SHARD', state: 'RUNNING' }, scope: 'DEFAULT')
        result = MicroserviceStatusModel.get(name: 'DEFAULT__TYPE__DB_SHARD', scope: 'DEFAULT')
        expect(result['name']).to eq('DEFAULT__TYPE__DB_SHARD')
        expect(result['state']).to eq('RUNNING')
      end
    end

    describe "self.names" do
      it "returns empty for no statuses" do
        names = MicroserviceStatusModel.names(scope: 'DEFAULT')
        expect(names).to eq([])
      end

      it "returns names across db_shards" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS1", scope: "DEFAULT", db_shard: 0).create
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS2", scope: "DEFAULT", db_shard: 1).create
        MicroserviceStatusModel.set({ name: 'DEFAULT__TYPE__MS1', state: 'RUNNING' }, scope: 'DEFAULT')
        MicroserviceStatusModel.set({ name: 'DEFAULT__TYPE__MS2', state: 'RUNNING' }, scope: 'DEFAULT')
        names = MicroserviceStatusModel.names(scope: 'DEFAULT')
        expect(names).to contain_exactly('DEFAULT__TYPE__MS1', 'DEFAULT__TYPE__MS2')
      end
    end

    describe "self.all" do
      it "returns empty for no statuses" do
        all = MicroserviceStatusModel.all(scope: 'DEFAULT')
        expect(all).to eq({})
      end

      it "returns all statuses across db_shards" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS1", scope: "DEFAULT", db_shard: 0).create
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS2", scope: "DEFAULT", db_shard: 1).create
        MicroserviceStatusModel.set({ name: 'DEFAULT__TYPE__MS1', state: 'RUNNING' }, scope: 'DEFAULT')
        MicroserviceStatusModel.set({ name: 'DEFAULT__TYPE__MS2', state: 'STOPPED' }, scope: 'DEFAULT')
        all = MicroserviceStatusModel.all(scope: 'DEFAULT')
        expect(all.keys).to contain_exactly('DEFAULT__TYPE__MS1', 'DEFAULT__TYPE__MS2')
        expect(all['DEFAULT__TYPE__MS1']['state']).to eq('RUNNING')
        expect(all['DEFAULT__TYPE__MS2']['state']).to eq('STOPPED')
      end
    end

    describe "create and destroy" do
      it "creates and destroys on the correct db_shard" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__TEST", scope: "DEFAULT", db_shard: 1).create
        model = MicroserviceStatusModel.new(name: 'DEFAULT__TYPE__TEST', state: 'RUNNING', scope: 'DEFAULT')
        model.create(force: true)
        result = MicroserviceStatusModel.get(name: 'DEFAULT__TYPE__TEST', scope: 'DEFAULT')
        expect(result['state']).to eq('RUNNING')
        model.destroy
        result = MicroserviceStatusModel.get(name: 'DEFAULT__TYPE__TEST', scope: 'DEFAULT')
        expect(result).to be_nil
      end
    end

    describe "_db_shard_for_name" do
      it "returns 0 when base model does not exist" do
        db_shard = MicroserviceStatusModel._db_shard_for_name('DEFAULT__TYPE__NONE', scope: 'DEFAULT')
        expect(db_shard).to eq(0)
      end

      it "returns db_shard from MicroserviceModel" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__TEST", scope: "DEFAULT", db_shard: 2).create
        db_shard = MicroserviceStatusModel._db_shard_for_name('DEFAULT__TYPE__TEST', scope: 'DEFAULT')
        expect(db_shard).to eq(2)
      end
    end

    describe "_active_db_shards" do
      it "always includes db_shard 0" do
        db_shards = MicroserviceStatusModel._active_db_shards(scope: 'DEFAULT')
        expect(db_shards).to include(0)
      end

      it "includes all unique db_shards from MicroserviceModels" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS1", scope: "DEFAULT", db_shard: 0).create
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS2", scope: "DEFAULT", db_shard: 2).create
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS3", scope: "DEFAULT", db_shard: 2).create
        db_shards = MicroserviceStatusModel._active_db_shards(scope: 'DEFAULT')
        expect(db_shards).to contain_exactly(0, 2)
      end

      it "only includes db_shards for the given scope" do
        MicroserviceModel.new(name: "DEFAULT__TYPE__MS1", scope: "DEFAULT", db_shard: 1).create
        MicroserviceModel.new(name: "OTHER__TYPE__MS2", scope: "OTHER", db_shard: 3).create
        db_shards = MicroserviceStatusModel._active_db_shards(scope: 'DEFAULT')
        expect(db_shards).to contain_exactly(0, 1)
      end
    end
  end
end
