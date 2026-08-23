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

require 'openc3'

# Streams a running script's replay stream and re-broadcasts new events in
# bounded batches to a single ActionCable subscription. The running script (running_script.rb /
# running_script.py) mirrors every per-script frontend event into the stream
# "running-script-channel:<id>:replay" (capped + short TTL).
#
# IMPORTANT: this thread only handles LIVE events (those written after the
# subscription was established). The already-present backlog is delivered
# separately by RunningScriptChannel#subscribed via transmit(), because a
# stream broadcast issued from this thread can race the gateway registering the
# subscriber's stream_from and be dropped -- which is exactly how a
# fast-completing script's output used to be lost. For the same reason the
# first read is deferred: current clients declare themselves ready to stream
# events via the 'ready' channel action after their subscription confirmation
# round-trips (proving the stream is registered), which arm()s us. A 'ready'
# that never arrives is bounded by arm_delay. The
# channel reads the backlog up to
# @start_offset and starts us there, so there is no gap and no duplicate
# delivery. Modeled on MessagesThread/TopicsThread in cmd-tlm-api.
class RunningScriptReplayThread
  MAX_BATCH_SIZE = 100

  def initialize(subscription_key, id, start_offset = '0-0', arm_delay: 0.0)
    @subscription_key = subscription_key
    @topic = "running-script-channel:#{id}:replay"
    # Stream strictly after the backlog the channel already transmitted.
    # Guard nil explicitly: a nil offset makes read_topics raise and
    # silently kills the thread (worst case re-delivery from 0-0 is
    # preferable to no delivery at all).
    @offsets = [start_offset || '0-0']
    # Wait up to arm_delay before the first read unless arm() is called
    # sooner. Broadcasts issued before the gateway registers the
    # subscriber's stream are silently dropped; current clients report ready
    # to stream events as soon as their subscription confirmation round-trips
    # (proving registration); arm_delay bounds a 'ready' that never arrives.
    @arm_delay = arm_delay
    @armed = arm_delay <= 0.0
    @cancel_thread = false
    @thread = nil
  end

  # Called when the client is ready to stream events: skip any remaining delay
  # and start reading/broadcasting immediately
  def arm
    @armed = true
  end

  def start
    @thread = Thread.new do
      unless @armed
        deadline = Time.now + @arm_delay
        while !@armed && !@cancel_thread && Time.now < deadline
          sleep 0.05
        end
      end
      while !@cancel_thread
        events = []
        # read_topics blocks up to ~1s for new entries then returns, so the loop
        # both drains the backlog (offset starts at '0-0') and streams live.
        OpenC3::Topic.read_topics([@topic], @offsets) do |_topic, msg_id, msg_hash, _redis|
          @offsets[0] = msg_id
          data = msg_hash['data']
          if data
            event = JSON.parse(data)
            events << event
            transmit_events(events) if events.length >= MAX_BATCH_SIZE
            # 'complete' is the script's terminal event: nothing is written to
            # the stream after it. End the thread so it self-cleans without
            # needing to be recycled, even if the client disconnects abruptly
            # (and unsubscribed never fires). A client that subscribes after the
            # script finished still gets the full backlog (replayed from '0-0',
            # including complete) via its own fresh thread, which then ends too.
            @cancel_thread = true if event['type'] == 'complete'
          end
          break if @cancel_thread
        end
        # read_topics commonly yields many entries from one Redis XREAD. Send
        # them in one ActionCable frame rather than paying the websocket and
        # client dispatch cost once per script event. Also flushes 'complete'
        # immediately instead of leaving a partial terminal batch pending.
        transmit_events(events)
      end
    rescue => e
      OpenC3::Logger.error("RunningScriptReplayThread died: #{e.formatted}") rescue nil
    end
  end

  def stop
    @cancel_thread = true
  end

  private

  def transmit_events(events)
    return if events.empty?

    ActionCable.server.broadcast(@subscription_key, events.dup)
    events.clear
  end
end
