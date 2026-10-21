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
require "openc3/utilities/store"

module OpenC3
  describe Store do
    describe "build_redis" do
      # A transient network blip (the same kind that makes targets reconnect)
      # must be retried inside the client with jittered backoff instead of
      # immediately surfacing a connection error to callers, which would
      # otherwise propagate up and kill the caller (e.g. the operator).
      it "configures equal-jitter reconnect backoff mirroring Python" do
        captured = nil
        allow(Redis).to receive(:new) do |**kwargs|
          captured = kwargs
          double("redis").as_null_object
        end

        store = Store.allocate
        store.instance_variable_set(:@redis_url, "redis://localhost:6379")
        store.instance_variable_set(:@redis_username, nil)
        store.instance_variable_set(:@redis_key, nil)
        store.send(:build_redis)

        attempts = captured[:reconnect_attempts]
        expect(attempts.length).to eq(3)
        # Equal-jitter ranges per retry with cap=5, base=0.625:
        # t = min(cap, base*2**f); delay in [t/2, t]
        expect(attempts[0]).to be_between(0.625, 1.25)
        expect(attempts[1]).to be_between(1.25, 2.5)
        expect(attempts[2]).to be_between(2.5, 5.0) # final retry caps at 5s
      end

      it "samples fresh jittered delays each call to de-sync clients" do
        store = Store.allocate
        a = store.send(:reconnect_backoff_delays)
        b = store.send(:reconnect_backoff_delays)
        # Astronomically unlikely to be identical unless jitter is missing
        expect(a).not_to eq(b)
      end
    end

    describe "read_topics" do
      before(:each) do
        mock_redis()
        stub_const("OpenC3::Store::READ_TOPICS_DEFAULT_COUNT", 2)
      end

      it "caps the read at READ_TOPICS_DEFAULT_COUNT when no count is given" do
        5.times { |i| EphemeralStore.write_topic("TEST__TOPIC", { "i" => i.to_s }) }
        ids = []
        EphemeralStore.read_topics(["TEST__TOPIC"], ["0-0"]) { |_t, msg_id, _h, _r| ids << msg_id }
        expect(ids.length).to eql 2
        # Continuing from the last offset picks up where the capped read stopped
        EphemeralStore.read_topics(["TEST__TOPIC"], [ids[-1]]) { |_t, msg_id, _h, _r| ids << msg_id }
        expect(ids.length).to eql 4
        expect(ids.uniq.length).to eql 4
      end

      it "honors an explicit count" do
        5.times { |i| EphemeralStore.write_topic("TEST__TOPIC", { "i" => i.to_s }) }
        ids = []
        EphemeralStore.read_topics(["TEST__TOPIC"], ["0-0"], nil, 4) { |_t, msg_id, _h, _r| ids << msg_id }
        expect(ids.length).to eql 4
      end
    end
  end
end
