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
require 'openc3/utilities/store'
require 'openc3/utilities/store_queued'

module OpenC3
  describe "Store db_shards" do
    before(:each) do
      mock_redis_db_shards()
    end

    describe "instance" do
      it "connects each db_shard to its own SHARDNUM host" do
        expect(Store.instance(db_shard: 0).redis_url).to eql "redis://redis-0:6379"
        expect(Store.instance(db_shard: 2).redis_url).to eql "redis://redis-2:6379"
        expect(EphemeralStore.instance(db_shard: 2).redis_url).to eql "redis://redis-ephemeral-2:6380"
      end

      it "keeps a singleton per db_shard" do
        expect(Store.instance(db_shard: 1)).to be(Store.instance(db_shard: 1))
        expect(Store.instance(db_shard: 1)).not_to be(Store.instance(db_shard: 0))
        expect(EphemeralStore.instance(db_shard: 1)).not_to be(Store.instance(db_shard: 1))
      end

      it "delegates class methods to db_shard 0" do
        Store.set('KEY', 'zero')
        expect(Store.instance(db_shard: 0).get('KEY')).to eql 'zero'
        expect(Store.instance(db_shard: 1).get('KEY')).to be_nil
      end
    end

    describe "db_shard_for_target" do
      it "returns 0 for a nil, unknown or unsharded target" do
        Store.hset('DEFAULT__openc3_targets', 'PLAIN', JSON.generate({ 'name' => 'PLAIN' }))
        expect(Store.db_shard_for_target(nil, scope: 'DEFAULT')).to eql 0
        expect(Store.db_shard_for_target('UNKNOWN', scope: 'DEFAULT')).to eql 0
        expect(Store.db_shard_for_target('PLAIN', scope: 'DEFAULT')).to eql 0
      end

      it "reads the target from db_shard 0 in the given scope" do
        set_target_db_shard('INST', 2)
        set_target_db_shard('INST', 3, scope: 'OTHER')
        # A target hash on another db_shard is ignored
        Store.instance(db_shard: 2).hset('DEFAULT__openc3_targets', 'INST', JSON.generate({ 'db_shard' => 5 }))
        expect(Store.db_shard_for_target('INST', scope: 'DEFAULT')).to eql 2
        expect(Store.db_shard_for_target('INST', scope: 'OTHER')).to eql 3
      end

      it "returns 0 when the lookup fails" do
        Store.hset('DEFAULT__openc3_targets', 'BAD', 'not json')
        expect(Store.db_shard_for_target('BAD', scope: 'DEFAULT')).to eql 0
      end

      it "caches the db_shard for 60 seconds" do
        set_target_db_shard('INST', 1)
        now = Time.now
        allow(Time).to receive(:now).and_return(now)
        expect(Store.db_shard_for_target('INST', scope: 'DEFAULT')).to eql 1

        Store.hset('DEFAULT__openc3_targets', 'INST', JSON.generate({ 'db_shard' => 2 }))
        allow(Time).to receive(:now).and_return(now + 59)
        expect(Store.db_shard_for_target('INST', scope: 'DEFAULT')).to eql 1
        allow(Time).to receive(:now).and_return(now + 61)
        expect(Store.db_shard_for_target('INST', scope: 'DEFAULT')).to eql 2
      end
    end

    describe "StoreQueued" do
      it "keeps a singleton per db_shard which writes to that db_shard" do
        expect(StoreQueued.instance(db_shard: 1)).to be(StoreQueued.instance(db_shard: 1))
        expect(StoreQueued.instance(db_shard: 1)).not_to be(StoreQueued.instance(db_shard: 0))

        StoreQueued.instance(db_shard: 1).hset('HASH', 'KEY', 'one')
        expect(Store.instance(db_shard: 1).hget('HASH', 'KEY')).to eql 'one'
        expect(Store.instance(db_shard: 0).hget('HASH', 'KEY')).to be_nil

        EphemeralStoreQueued.instance(db_shard: 1).hset('HASH', 'KEY', 'eph')
        expect(EphemeralStore.instance(db_shard: 1).hget('HASH', 'KEY')).to eql 'eph'
        expect(Store.instance(db_shard: 1).hget('HASH', 'KEY')).to eql 'one'
      end

      it "processes queued writes on its db_shard" do
        $store_queued = true
        queued = StoreQueued.new(1000, db_shard: 1)
        queued.hset('HASH', 'KEY', 'queued')
        queued.process_queue
        expect(Store.instance(db_shard: 1).hget('HASH', 'KEY')).to eql 'queued'
        expect(Store.instance(db_shard: 0).hget('HASH', 'KEY')).to be_nil
      ensure
        queued&.shutdown
        $store_queued = false
      end
    end
  end
end
