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

class RunningScriptChannel < ApplicationCable::Channel
  @@broadcasters = {}

  def subscribed
    # Defensive: if the auth before_subscribe callback rejected us, skip work.
    return if subscription_rejected?
    # The running script mirrors its per-script events into a short-lived Redis
    # stream. Tail that stream (backlog first, then live) as the single ordered
    # source and re-broadcast each event to this subscription's private key.
    # This fixes the race where a client subscribed after the script had already
    # produced output/state (the anycable broadcast is pub/sub with no history),
    # which left the state stuck on "Connecting..." or output as "No data".
    subscription_key = "running-script-#{uuid}"
    stream_from subscription_key
    # Guard against a duplicate broadcaster for this key (e.g. if subscribed
    # fires again before unsubscribed) which would deliver every event twice.
    @@broadcasters[subscription_key]&.stop
    begin
      broadcaster = RunningScriptReplayThread.new(subscription_key, params[:id])
      broadcaster.start
      @@broadcasters[subscription_key] = broadcaster
    rescue StandardError => e
      # Best-effort: a replay failure must not break the subscription.
      OpenC3::Logger.warn("running_script replay start failed: #{e.message}") rescue nil
    end
  end

  def unsubscribed
    subscription_key = "running-script-#{uuid}"
    if @@broadcasters[subscription_key]
      stop_stream_from subscription_key
      @@broadcasters[subscription_key].stop
      @@broadcasters.delete(subscription_key)
    end
  end
end
