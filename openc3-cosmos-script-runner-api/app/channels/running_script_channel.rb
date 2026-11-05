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

  # Upper bound on how long the live event broadcaster waits for the client's
  # 'ready' before starting to read anyway. This is the correctness floor for
  # the stream-registration race described in #subscribed, not a legacy-client
  # allowance: it also covers a 'ready' that never arrives because the client
  # died or the perform was lost. Every in-tree client (ScriptRunner.vue, the
  # Ruby and Python WebSocketApi) performs 'ready', so in practice this only
  # costs latency for third-party consumers that just subscribe and read.
  ARM_TIMEOUT = 1.0

  # Upper bound on the backlog delivered by #subscribed. AnyCable returns every
  # transmit() made during the subscribe RPC to the gateway in ONE gRPC
  # response, and gRPC rejects messages over 4MB. The replay stream is capped by
  # entry count (MAXLEN) but not by size, and single entries can be large ('file'
  # carries a whole script, 'output' up to max_output_characters), so a busy
  # long-running script could exceed the limit -- after which every (re)subscribe
  # failed and nobody could attach to the script again. Only the newest events
  # that fit are replayed. Half the limit leaves room for the per-transmission
  # JSON envelope.
  MAX_REPLAY_BYTES = 2 * 1024 * 1024

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
      newest = true
      replay_bytes = 0
      omitted = 0
      backlog = [] # Newest first
      # Walk newest to oldest so the size cap keeps the most recent events
      OpenC3::Topic.xrevrange(topic, '+', '-').each do |msg_id, msg_hash|
        last_offset = msg_id if newest
        data = msg_hash['data']
        # Only parse here if it could be 'complete'; everything is parsed below
        if newest && data&.include?('"complete"')
          event = parse_replay_event(data)
          if event && event['type'] == 'complete'
            complete = true
            # 'complete' must always reach the client or it never finishes the
            # session. Drop the report rather than the event if it is too big.
            if data.bytesize > MAX_REPLAY_BYTES
              event.delete('report')
              data = event.to_json
            end
          end
        end
        newest = false
        next unless data

        # Keep a contiguous tail: once one event does not fit, omit all older
        if omitted > 0 || replay_bytes + data.bytesize > MAX_REPLAY_BYTES
          omitted += 1
          next
        end
        replay_bytes += data.bytesize
        backlog << data
      end

      events = []
      if omitted > 0
        events << { 'type' => 'output', 'color' => 'BLUE',
                    'line' => "#{Time.now.sys.formatted} (SCRIPTRUNNER): Script history too large to replay, #{omitted} earlier events omitted\n" }
      end
      backlog.reverse_each do |data|
        # Parse individually so one corrupt entry cannot take the rest with it
        event = parse_replay_event(data)
        events << event if event
        if events.length >= RunningScriptReplayThread::MAX_BATCH_SIZE
          transmit(events)
          events = []
        end
      end
      transmit(events) unless events.empty?
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
    # publishes again -- leaving the client stuck on "Connecting...". Clients
    # declare themselves ready to stream events via the 'ready' action (see
    # #ready), performed after the subscription confirmation has round-tripped,
    # which guarantees the stream is registered. ARM_TIMEOUT bounds the wait for
    # a 'ready' that never comes.
    begin
      broadcaster = RunningScriptReplayThread.new(key, params[:id], last_offset,
                                                  arm_delay: ARM_TIMEOUT)
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
  # longer be dropped. Skips the remaining ARM_TIMEOUT and streams right away.
  # No-ops if the script already completed (no broadcaster) or on duplicate
  # performs.
  def ready
    @@broadcasters[subscription_key()]&.arm
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

  def parse_replay_event(data)
    JSON.parse(data)
  rescue StandardError => e
    OpenC3::Logger.warn("running_script replay skipped bad event: #{e.message}") rescue nil
    nil
  end

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
