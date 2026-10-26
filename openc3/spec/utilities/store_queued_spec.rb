# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "spec_helper"
require "openc3/utilities/store_queued"

module OpenC3
  describe StoreQueued do
    before(:each) do
      $store_queued = true
      mock_redis()
    end
    after(:each) do
      StoreQueued.shutdown
      $store_queued = false
    end

    it "batches store methods to execute in a pipeline" do
      StoreQueued.instance(0.1) # Set the update interval

      StoreQueued.hset("presence", "key", 10)
      sleep 0.05
      expect(Store.hget("presence", "key")).to eq "10"

      StoreQueued.hset("presence", "key1", 10)
      StoreQueued.hset("presence", "key2", 20)
      StoreQueued.hset("presence", "key3", 30)
      # Initially the values aren't there because they haven't been persisted
      expect(Store.hget("presence", "key1")).to be_nil
      expect(Store.hget("presence", "key2")).to be_nil
      expect(Store.hget("presence", "key3")).to be_nil
      sleep 0.15 # Wait past the UPDATE_INTERVAL
      # Now the values are persisted to the Store
      expect(Store.hget("presence", "key1")).to eq "10"
      expect(Store.hget("presence", "key2")).to eq "20"
      expect(Store.hget("presence", "key3")).to eq "30"
    end

    it "writes straight through to the store after shutdown" do
      StoreQueued.instance(10) # Long interval so only shutdown drains the queue

      StoreQueued.hset("presence", "key1", 10)
      expect(Store.hget("presence", "key1")).to be_nil
      StoreQueued.shutdown
      # Shutdown drains what was already queued
      expect(Store.hget("presence", "key1")).to eq "10"

      # Nothing will drain the queue again, so later writes must not be queued
      StoreQueued.hset("presence", "key2", 20)
      expect(Store.hget("presence", "key2")).to eq "20"
    end

    it "drains the queue before writing straight through" do
      # A direct write during the drain could be overwritten by an older queued
      # write, so the flag must only flip once the queue is empty
      store_queued = StoreQueued.instance(10)
      StoreQueued.hset("presence", "key1", 10)
      seen = []
      allow(Store.instance).to receive(:hset).and_wrap_original do |m, *args|
        seen << store_queued.instance_variable_get(:@shutdown)
        m.call(*args)
      end
      StoreQueued.shutdown
      expect(seen).to eql([nil])
      expect(store_queued.instance_variable_get(:@shutdown)).to be true
    end
  end

  describe StoreQueued, ".set_update_interval_all_shards" do
    before(:each) do
      mock_redis()
    end

    it "updates existing instances and is used by instances created later" do
      existing = StoreQueued.instance(db_shard: 0)
      expect(existing.update_interval).to eql 1
      StoreQueued.set_update_interval_all_shards(0.25)
      expect(existing.update_interval).to eql 0.25
      expect(StoreQueued.instance(db_shard: 1).update_interval).to eql 0.25
      # Separate setting per class
      expect(EphemeralStoreQueued.instance(db_shard: 1).update_interval).to eql 1
      # An explicit interval still wins for a new instance
      expect(StoreQueued.instance(0.5, db_shard: 2).update_interval).to eql 0.5
    end

    it "ignores intervals of 0 or less" do
      StoreQueued.set_update_interval_all_shards(0.25)
      StoreQueued.set_update_interval_all_shards(0)
      expect(StoreQueued.instance.update_interval).to eql 0.25
    end
  end
end
