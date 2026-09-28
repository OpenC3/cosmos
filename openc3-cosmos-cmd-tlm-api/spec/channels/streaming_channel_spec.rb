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

require "rails_helper"

# TODO: Seems like Rails 6.1 doesn't have this support built in yet
module ActionCable
  module Channel
    class ConnectionStub
      def pubsub
        ActionCable.server.pubsub
      end
    end
  end
end

RSpec.describe StreamingChannel, :type => :channel do
  before(:all) do
    stub_connection uuid: '12345', scope: 'DEFAULT'
  end

  it "subscribes" do
    subscribe()
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from('streaming_12345')
  end

  context "adds" do
    it "rejects without scope" do
      subscribe()
      subscription.add({ items: ['TLM__TGT__PKT__ITEM__CONVERTED'] })
      expect(subscription).to be_rejected
    end

    it "rejects without items" do
      subscribe()
      subscription.add({ scope: 'DEFAULT' })
      expect(subscription).to be_rejected
    end

    it "rejects with empty items" do
      subscribe()
      subscription.add({ scope: 'DEFAULT', items: [] })
      expect(subscription).to be_rejected
    end

    it "rejects with start_time greater than now" do
      time = Time.now.to_nsec_from_epoch + 1_000_000_000
      subscribe()
      subscription.add({ scope: 'DEFAULT', items: ['TLM__TGT__PKT__ITEM__CONVERTED'], start_time: time })
      expect(subscription).to be_rejected
    end

    it "adds specified items" do
      subscribe()
      subscription.add({ scope: 'DEFAULT', items: ['TLM__TGT__PKT__ITEM__CONVERTED'] })
      expect(subscription).to be_confirmed
    end
  end

  context "with a missing broadcaster" do
    # The broadcaster only exists between subscribed and unsubscribed. A perform
    # that races a rejected/torn-down subscription (broadcaster == nil) must be a
    # harmless no-op, not a NoMethodError that reject_subscription()s every panel
    # on the connection. (String keys here mirror the JSON-parsed data a real
    # client sends, so validate_data passes and we actually exercise the guard.)
    before do
      subscribe()
      ApplicationCable::BroadcasterRegistry.unregister('streaming_12345')
    end

    it "does not reject a remove" do
      subscription.remove({ 'scope' => 'DEFAULT', 'items' => ['TLM__TGT__PKT__ITEM__CONVERTED'] })
      expect(subscription).not_to be_rejected
    end

    it "does not reject an add" do
      subscription.add({ 'scope' => 'DEFAULT', 'items' => ['TLM__TGT__PKT__ITEM__CONVERTED'] })
      expect(subscription).not_to be_rejected
    end
  end

  context "broadcaster lifecycle" do
    let(:registry) { ApplicationCable::BroadcasterRegistry }

    before(:each) { allow(OpenC3::Logger).to receive(:warn) }

    it "registers on subscribe and unregisters on unsubscribe" do
      subscribe()
      expect(registry.get('streaming_12345')).to be_a(StreamingApi)
      unsubscribe()
      expect(registry.registered?('streaming_12345')).to be false
    end

    it "kills a previous broadcaster registered under the same key" do
      subscribe()
      first = registry.get('streaming_12345')
      expect(first).to receive(:kill)
      subscribe()
      expect(registry.get('streaming_12345')).not_to equal(first)
    end

    it "reaps a heartbeating subscription that stops heartbeating" do
      subscribe()
      subscription.heartbeat({})
      broadcaster = registry.get('streaming_12345')
      expect(broadcaster).to receive(:kill)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(registry.sweep(now + registry.ttl + 1)).to eql ['streaming_12345']
      expect(registry.registered?('streaming_12345')).to be false
    end

    it "does not reap a subscription that never heartbeats" do
      subscribe()
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect(registry.sweep(now + registry.ttl + 1)).to be_empty
      expect(registry.registered?('streaming_12345')).to be true
    end

    it "tells a heartbeating client to resubscribe once its broadcaster is gone" do
      subscribe()
      registry.unregister('streaming_12345')
      subscription.heartbeat({})
      expect(transmissions.last).to eql({ '__openc3_cable__' => 'resubscribe' })
    end
  end
end
