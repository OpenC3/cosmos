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

module ApplicationCable
  # Shared lifecycle for channels that stream from a per-subscription
  # broadcaster object. Including channels declare a key prefix with
  # `broadcaster_prefix` and implement a private `create_broadcaster`.
  # Broadcasters are tracked in BroadcasterRegistry so a subscription whose
  # Disconnect never arrives is eventually reaped.
  module BroadcasterChannel
    extend ActiveSupport::Concern

    # Sent to a heartbeating client whose broadcaster no longer exists (reaped
    # or lost), telling it to resubscribe. Handled inside the frontend Cable
    # wrapper so it never reaches the channel's received callback.
    RESUBSCRIBE_MESSAGE = { '__openc3_cable__' => 'resubscribe' }.freeze

    class_methods do
      def broadcaster_prefix(prefix = nil)
        @broadcaster_prefix = prefix if prefix
        @broadcaster_prefix
      end
    end

    def subscribed
      # Defensive: if the auth before_subscribe callback rejected us, skip work.
      return if subscription_rejected?
      stream_from subscription_key
      BroadcasterRegistry.register(subscription_key, create_broadcaster())
    end

    def unsubscribed
      if BroadcasterRegistry.registered?(subscription_key)
        stop_stream_from subscription_key
        BroadcasterRegistry.unregister(subscription_key)
      end
    end

    def heartbeat(_data = nil)
      unless BroadcasterRegistry.touch(subscription_key, heartbeat: true)
        transmit(RESUBSCRIBE_MESSAGE)
      end
    end

    private

    def subscription_key
      "#{self.class.broadcaster_prefix}_#{uuid}"
    end

    # Any perform from the client also counts as activity
    def broadcaster
      BroadcasterRegistry.touch(subscription_key)
      BroadcasterRegistry.get(subscription_key)
    end
  end
end
