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

    included do
      # Identifies the broadcaster this subscription registered. Kept in
      # AnyCable channel state because channel instances don't survive between
      # the subscribe and unsubscribe RPCs.
      state_attr_accessor :broadcaster_token
    end

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
      self.broadcaster_token = SecureRandom.uuid
      # Clients that heartbeat say so when they subscribe so they can be reaped
      # even if they die before sending their first heartbeat
      BroadcasterRegistry.register(subscription_key, create_broadcaster(),
        heartbeat: [true, 'true'].include?(params[:heartbeat]), token: broadcaster_token)
    end

    def unsubscribed
      # No token means subscribed was rejected and nothing was registered
      token = broadcaster_token
      return unless token
      stop_stream_from subscription_key
      # Only remove our own registration. A resubscribe on the same connection
      # shares the key, and if its subscribe is handled before this unsubscribe
      # the newer broadcaster must survive.
      BroadcasterRegistry.unregister(subscription_key, token: token)
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
