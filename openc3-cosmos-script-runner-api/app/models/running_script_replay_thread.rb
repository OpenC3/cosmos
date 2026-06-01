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

# Tails a running script's replay stream and re-broadcasts each event to a
# single ActionCable subscription. The running script (running_script.rb /
# running_script.py) mirrors every per-script frontend event into the stream
# "script-api:running-script-channel:<id>:replay" (capped + short TTL). Reading
# from '0-0' yields the existing backlog first and then blocks for live events,
# so a client that subscribes after the script started still receives the events
# it missed -- in order, from a single source (no pub/sub history gap, no dedup
# needed on the client). Modeled on MessagesThread/TopicsThread in cmd-tlm-api.
class RunningScriptReplayThread
  def initialize(subscription_key, id)
    @subscription_key = subscription_key
    @topic = "running-script-channel:#{id}:replay"
    @offsets = ['0-0'] # Start at the beginning to replay the backlog, then tail
    @cancel_thread = false
    @thread = nil
  end

  def start
    @thread = Thread.new do
      while !@cancel_thread
        # read_topics blocks up to ~1s for new entries then returns, so the loop
        # both drains the backlog (offset starts at '0-0') and tails live.
        OpenC3::Topic.read_topics([@topic], @offsets) do |_topic, msg_id, msg_hash, _redis|
          @offsets[0] = msg_id
          data = msg_hash['data']
          if data
            event = JSON.parse(data)
            ActionCable.server.broadcast(@subscription_key, event)
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
      end
    rescue => e
      OpenC3::Logger.error("RunningScriptReplayThread died: #{e.formatted}") rescue nil
    end
  end

  def stop
    @cancel_thread = true
  end
end
