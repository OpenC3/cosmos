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
      StreamingChannel.class_variable_get(:@@broadcasters)['streaming_12345'] = nil
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
end
