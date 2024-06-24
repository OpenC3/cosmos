# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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
  end
end
