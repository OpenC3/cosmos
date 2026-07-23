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

  # How long the live-tail broadcaster waits before its first read when the
  # client has not armed it via the 'tail' action. Covers legacy clients
  # (older CLI gems / frontend bundles / third-party websocket consumers)
  # that only subscribe and read: their events are delayed by up to this
  # much at attach, in exchange for not being dropped by the
  # stream-registration race described below. Current clients perform
  # 'tail' after the subscription confirmation and get events immediately.
  LEGACY_ARM_DELAY = 1.0

  def subscribed
    # Defensive: if the auth before_subscribe callback rejected us, skip work.
    return if subscription_rejected?
    # The running script mirrors its per-script events into a short-lived Redis
    # stream so a client that subscribes after the script has already produced
    # output/state still receives what it missed (the raw anycable broadcast is
    # pub/sub with no history, which left state stuck on "Connecting..." or
    # output as "No data").
    subscription_key = "running-script-#{uuid}"
    stream_from subscription_key
    # Guard against a duplicate broadcaster for this key (e.g. if subscribed
    # fires again before unsubscribed) which would deliver every event twice.
    @@broadcasters[subscription_key]&.stop
    @@broadcasters.delete(subscription_key)

    # Deliver the existing backlog via transmit() rather than a stream
    # broadcast. transmit is returned with the subscription confirmation and
    # delivered reliably; a broadcast issued now (from here or a background
    # thread) can race the gateway registering our stream_from above and be
    # dropped -- which is how a fast-completing script (e.g. a parse-time crash)
    # lost all of its output. We record the last backlog offset and, only if the
    # script has not already finished, start a thread to tail LIVE events from
    # there (those are written later, after stream_from is registered).
    topic = "running-script-channel:#{params[:id]}:replay"
    last_offset = '0-0'
    complete = false
    begin
      OpenC3::Topic.xrange(topic, '-', '+').each do |msg_id, msg_hash|
        last_offset = msg_id
        data = msg_hash['data']
        next unless data
        event = JSON.parse(data)
        transmit(event)
        complete = true if event['type'] == 'complete'
      end
    rescue StandardError => e
      # Best-effort: a replay failure must not break the subscription.
      OpenC3::Logger.warn("running_script replay backlog failed: #{e.message}") rescue nil
    end
    # Script already finished -- the backlog held the terminal 'complete', so
    # there is nothing left to stream.
    return if complete

    # Start the live tail, but DELAYED: a broadcast issued right now can race
    # the gateway registering our stream_from above and be silently dropped.
    # That loses any events written between the xrange and the thread's first
    # read, and a script that then goes quiet (e.g. parked in a wait) never
    # publishes again -- leaving the client stuck on "Connecting...". Current
    # clients arm the tail immediately via the 'tail' action (see #tail),
    # performed after the subscription confirmation has round-tripped, which
    # guarantees the stream is registered. The delay is only the fallback for
    # legacy clients that never perform 'tail'.
    begin
      broadcaster = RunningScriptReplayThread.new(subscription_key, params[:id], last_offset,
                                                  arm_delay: LEGACY_ARM_DELAY)
      broadcaster.start
      @@broadcasters[subscription_key] = broadcaster
    rescue StandardError => e
      # Best-effort: a replay failure must not break the subscription.
      OpenC3::Logger.warn("running_script replay start failed: #{e.message}") rescue nil
    end
  end

  # Channel action performed by the client after it receives the
  # subscription confirmation. By then the gateway has registered this
  # subscription's stream, so live broadcasts can no longer be dropped --
  # skip the legacy arm delay and start tailing right away. No-ops if the
  # script already completed (no broadcaster) or on duplicate performs.
  def tail
    @@broadcasters["running-script-#{uuid}"]&.arm
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
