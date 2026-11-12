# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "spec_helper"
require "openc3/utilities/questdb_client"
require "openc3/models/target_model"

module OpenC3
  describe QuestDBClient, no_ext: true do
    before(:each) do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OPENC3_TSDB_HOSTNAME').and_return('tsdb-SHARDNUM')
      QuestDBClient.instance_variable_set(:@db_shard_cache, {})
    end

    after(:each) do
      QuestDBClient.instance_variable_set(:@db_shard_cache, {})
    end

    describe "hostname_for_db_shard" do
      it "replaces SHARDNUM with the db_shard" do
        expect(QuestDBClient.hostname_for_db_shard(0)).to eql 'tsdb-0'
        expect(QuestDBClient.hostname_for_db_shard(2)).to eql 'tsdb-2'
      end

      it "uses the same host for every db_shard without SHARDNUM" do
        allow(ENV).to receive(:[]).with('OPENC3_TSDB_HOSTNAME').and_return('tsdb')
        expect(QuestDBClient.hostname_for_db_shard(0)).to eql 'tsdb'
        expect(QuestDBClient.hostname_for_db_shard(2)).to eql 'tsdb'
      end
    end

    describe "db_shard_for_target" do
      it "returns 0 for no target without a lookup" do
        expect(TargetModel).not_to receive(:get)
        expect(QuestDBClient.db_shard_for_target(nil)).to eql 0
      end

      it "returns the db_shard of the target in the given scope" do
        allow(TargetModel).to receive(:get) do |name:, scope:|
          { 'name' => name, 'db_shard' => scope == 'OTHER' ? '3' : 1 }
        end
        expect(QuestDBClient.db_shard_for_target('INST')).to eql 1
        expect(QuestDBClient.db_shard_for_target('INST', scope: 'OTHER')).to eql 3
      end

      it "returns 0 for a target which doesn't exist or can't be looked up" do
        allow(TargetModel).to receive(:get).with(name: 'MISSING', scope: 'DEFAULT').and_return(nil)
        allow(TargetModel).to receive(:get).with(name: 'BROKEN', scope: 'DEFAULT').and_raise("down")
        expect(QuestDBClient.db_shard_for_target('MISSING')).to eql 0
        expect(QuestDBClient.db_shard_for_target('BROKEN')).to eql 0
      end

      it "caches the db_shard for a minute" do
        allow(TargetModel).to receive(:get).and_return({ 'db_shard' => 1 }, { 'db_shard' => 2 })
        now = Time.now
        allow(Time).to receive(:now).and_return(now)
        expect(QuestDBClient.db_shard_for_target('INST')).to eql 1
        allow(Time).to receive(:now).and_return(now + 59)
        expect(QuestDBClient.db_shard_for_target('INST')).to eql 1
        expect(TargetModel).to have_received(:get).once
        allow(Time).to receive(:now).and_return(now + 61)
        expect(QuestDBClient.db_shard_for_target('INST')).to eql 2
        expect(TargetModel).to have_received(:get).twice
      end
    end
  end
end
