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

require_relative 'streaming_thread'

class RealtimeStreamingThread < StreamingThread
  # How far behind realtime (in seconds) the stream may fall before we consider
  # skipping ahead. Set OPENC3_STREAMING_MAX_LAG_SECONDS to 0 to disable.
  DEFAULT_MAX_LAG_SECONDS = 10.0
  # Beyond this multiple of the max lag we skip immediately, even if catching up,
  # because Redis only retains a limited window and the data is about to be trimmed
  SKIP_IMMEDIATELY_FACTOR = 6

  def initialize(streaming_api, collection, scope: nil)
    super(streaming_api, collection, scope: scope)
    @max_lag_seconds = ENV.fetch('OPENC3_STREAMING_MAX_LAG_SECONDS', DEFAULT_MAX_LAG_SECONDS).to_f
    @behind_since = nil
    @behind_lag = nil
  end

  def thread_body
    redis_thread_body()
  end

  # Realtime displays want current values, so if we can't keep up we jump to the
  # newest data rather than falling ever further behind. A stream that is over
  # the threshold but catching up (e.g. just handed off from a historical query)
  # gets a grace window of @max_lag_seconds, and each window in which the lag
  # shrinks starts a new one. Only when the lag fails to shrink over a whole
  # window (or gets extreme) do we skip.
  def check_lag(newest_msg_ids, item_objects_by_topic, packet_objects_by_topic)
    return if @max_lag_seconds <= 0 or newest_msg_ids.empty?

    now = Time.now.to_f
    newest_ms = newest_msg_ids.values.map { |msg_id| msg_id.split('-')[0].to_i }
    lag = now - (newest_ms.min / 1000.0)
    if lag <= @max_lag_seconds
      @behind_since = nil
      @behind_lag = nil
      return
    end

    if lag < @max_lag_seconds * SKIP_IMMEDIATELY_FACTOR
      if @behind_since.nil?
        @behind_since = now
        @behind_lag = lag
        return
      end
      return if (now - @behind_since) < @max_lag_seconds
      if lag < @behind_lag
        # Catching up - give it another window
        @behind_since = now
        @behind_lag = lag
        return
      end
    end

    skip_ahead(lag, item_objects_by_topic, packet_objects_by_topic)
    @behind_since = nil
    @behind_lag = nil
  end

  def skip_ahead(lag, item_objects_by_topic, packet_objects_by_topic)
    OpenC3::Logger.warn("Realtime streaming fell #{lag.round(1)}s behind, skipping ahead to the latest data")
    (item_objects_by_topic.keys | packet_objects_by_topic.keys).each do |topic|
      objects = (item_objects_by_topic[topic] || []) + (packet_objects_by_topic[topic] || [])
      next if objects.empty?
      last_offset = OpenC3::Topic.get_last_offset(topic, db_shard: objects[0].db_shard)
      next if last_offset == "0-0"
      objects.each { |object| object.offset = last_offset }
    end
    @streaming_api.transmit_notice('SKIPPED', "Streaming fell behind realtime, skipped #{lag.round(1)}s of data", skipped_seconds: lag.round(3))
  end
end
