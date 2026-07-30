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

  # How long the live event broadcaster waits before its first read when the
  # client has not declared itself ready to stream events via the 'ready'
  # action. Covers legacy clients (older CLI gems / frontend bundles /
  # third-party websocket consumers) that only subscribe and read: their events
  # are delayed by up to this much at attach, in exchange for not being dropped
  # by the stream-registration race described below. Current clients perform
  # 'ready' after the subscription confirmation and get events immediately.
  LEGACY_ARM_DELAY = 1.0

  def subscribed
    # Defensive: if the auth before_subscribe callback rejected us, skip work.
    return if subscription_rejected?
    # The running script mirrors its per-script events into a short-lived Redis
    # stream so a client that subscribes after the script has already produced
    # output/state still receives what it missed (the raw anycable broadcast is
    # pub/sub with no history, which left state stuck on "Connecting..." or
    # output as "No data").
    key = subscription_key()
    stream_from key
    # Guard against a duplicate broadcaster for this key (e.g. if subscribed
    # fires again before unsubscribed) which would deliver every event twice.
    @@broadcasters[key]&.stop
    @@broadcasters.delete(key)

    # Deliver the existing backlog via transmit() rather than a stream
    # broadcast. transmit is returned with the subscription confirmation and
    # delivered reliably; a broadcast issued now (from here or a background
    # thread) can race the gateway registering our stream_from above and be
    # dropped -- which is how a fast-completing script (e.g. a parse-time crash)
    # lost all of its output. We record the last backlog offset and, only if the
    # script has not already finished, start a thread to stream LIVE events from
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

    # Start streaming live events, but DELAYED: a broadcast issued right now can
    # race the gateway registering our stream_from above and be silently
    # dropped. That loses any events written between the xrange and the thread's
    # first read, and a script that then goes quiet (e.g. parked in a wait) never
    # publishes again -- leaving the client stuck on "Connecting...". Current
    # clients declare themselves ready to stream events immediately via the
    # 'ready' action (see #ready), performed after the subscription confirmation
    # has round-tripped, which guarantees the stream is registered. The delay is
    # only the fallback for legacy clients that never perform 'ready'.
    begin
      broadcaster = RunningScriptReplayThread.new(key, params[:id], last_offset,
                                                  arm_delay: LEGACY_ARM_DELAY)
      broadcaster.start
      @@broadcasters[key] = broadcaster
    rescue StandardError => e
      # Best-effort: a replay failure must not break the subscription.
      OpenC3::Logger.warn("running_script replay start failed: #{e.message}") rescue nil
    end
  end

  # Channel action performed by the client to declare that it is ready to
  # stream events: it has received the subscription confirmation, so by now the
  # gateway has registered this subscription's stream and live broadcasts can no
  # longer be dropped. Skips the legacy delay and starts streaming right away.
  # No-ops if the script already completed (no broadcaster) or on duplicate
  # performs.
  def ready
    @@broadcasters["running-script-#{uuid}"]&.arm
  end

  def unsubscribed
    key = subscription_key()
    if @@broadcasters[key]
      stop_stream_from key
      @@broadcasters[key].stop
      @@broadcasters.delete(key)
    end
  end

  private

  # The stream (and @@broadcasters) key must identify this subscription, not
  # just its connection. `uuid` is an identified_by on the connection, so it is
  # shared by every RunningScriptChannel subscription in the same browser tab.
  # Keying on it alone meant tearing down one subscription stopped the replay
  # thread of another script's subscription on the same connection -- which left
  # that script's Script Runner stuck on "Connecting..." with no live events.
  # AnyCable is stateless between commands so this has to be derived, not
  # generated: (connection, script id) is unique because the client dedupes
  # subscriptions by identifier, so a connection only ever has one subscription
  # per script.
  def subscription_key
    "running-script-#{uuid}-#{params[:id]}"
  end
end
