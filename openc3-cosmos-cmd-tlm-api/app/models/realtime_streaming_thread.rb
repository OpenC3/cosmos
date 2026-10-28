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
  # Minimum seconds between lag checks. Each check costs a Redis round trip per
  # db_shard so don't do it every pass; lag thresholds are many seconds anyway.
  LAG_CHECK_INTERVAL_SECONDS = 1.0

  def initialize(streaming_api, collection, scope: nil)
    super(streaming_api, collection, scope: scope)
    @max_lag_seconds = max_lag_seconds()
    # Monotonic time when the current "behind" grace window started (nil when caught up)
    @behind_since = nil
    # Lag measured at the start of the current grace window, compared against
    # at the end of the window to decide whether we're catching up
    @behind_lag = nil
    # Monotonic time of the last lag check, used to rate limit the Redis queries
    @last_lag_check = nil
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
  #
  # Lag is how far the newest msg_id we read trails the newest msg_id in the
  # stream. Both are stamped by the same Redis server (XADD '*') so the result
  # is immune to clock skew between this container and Redis.
  def check_lag(newest_msg_ids, item_objects_by_topic, packet_objects_by_topic)
    # Disabled, or nothing was read this pass so there is nothing to measure.
    # An idle stream can't be behind: the blocking read would have returned data.
    return if @max_lag_seconds <= 0 or newest_msg_ids.empty?

    # Monotonic clock so wall clock adjustments (NTP, DST) can't affect the windows
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @last_lag_check and (now - @last_lag_check) < LAG_CHECK_INTERVAL_SECONDS
    @last_lag_check = now

    heads = stream_heads(newest_msg_ids.keys, item_objects_by_topic, packet_objects_by_topic)
    topic_lags = {}
    newest_msg_ids.each do |topic, msg_id|
      head = heads[topic]
      # Stream was deleted or trimmed to empty since we read it - can't measure
      next unless head
      # msg_ids are "<ms>-<seq>" so the difference of the ms parts is the lag
      topic_lags[topic] = (msg_id_ms(head) - msg_id_ms(msg_id)) / 1000.0
    end
    # The stream as a whole is only as current as its slowest topic
    lag = topic_lags.values.max || 0.0
    if lag <= @max_lag_seconds
      # Within tolerance so reset any grace window in progress
      @behind_since = nil
      @behind_lag = nil
      return
    end

    # Moderately behind: apply the grace window logic. Extremely behind falls
    # through to skip immediately since waiting risks reading trimmed data.
    if lag < @max_lag_seconds * SKIP_IMMEDIATELY_FACTOR
      if @behind_since.nil?
        # Just fell behind - start the first grace window
        @behind_since = now
        @behind_lag = lag
        return
      end
      # Still inside the current grace window - keep reading normally
      return if (now - @behind_since) < @max_lag_seconds
      if lag < @behind_lag
        # Catching up - give it another window
        @behind_since = now
        @behind_lag = lag
        return
      end
      # A whole window passed without the lag shrinking - fall through and skip
    end

    skip_ahead(lag, topic_lags, heads, item_objects_by_topic, packet_objects_by_topic)
    # Skipping puts us at the head so start fresh on the next check
    @behind_since = nil
    @behind_lag = nil
  end

  # Only topics that are actually behind are advanced so up to date topics
  # don't lose messages that arrived during this pass
  def skip_ahead(lag, topic_lags, heads, item_objects_by_topic, packet_objects_by_topic)
    OpenC3::Logger.warn("Realtime streaming fell #{lag.round(1)}s behind, skipping ahead to the latest data")
    topic_lags.each do |topic, topic_lag|
      next if topic_lag <= @max_lag_seconds
      # Both item and packet subscriptions can share a topic so move them all
      objects = (item_objects_by_topic[topic] || []) + (packet_objects_by_topic[topic] || [])
      # The next XREAD returns entries after the offset, so setting it to the
      # head msg_id resumes with the first message published after this check
      objects.each { |object| object.offset = heads[topic] }
    end
    # Tell opted in clients so they can show the gap rather than silently dropping data
    @streaming_api.transmit_notice('SKIPPED', "Streaming fell behind realtime, skipped #{lag.round(1)}s of data", skipped_seconds: lag.round(3))
  end

  # Only an explicit 0 disables lag handling. A malformed value (which to_f
  # would silently turn into 0) falls back to the default instead.
  def max_lag_seconds
    raw = ENV.fetch('OPENC3_STREAMING_MAX_LAG_SECONDS', nil)
    return DEFAULT_MAX_LAG_SECONDS if raw.nil? or raw.strip.empty?
    value = Float(raw, exception: false)
    return value if value
    OpenC3::Logger.warn("Invalid OPENC3_STREAMING_MAX_LAG_SECONDS '#{raw}', using #{DEFAULT_MAX_LAG_SECONDS}")
    DEFAULT_MAX_LAG_SECONDS
  end

  # Returns the newest msg_id of each topic using one pipelined round trip per db_shard
  def stream_heads(topics, item_objects_by_topic, packet_objects_by_topic)
    heads = {}
    # Every object on a topic lives on the same db_shard so the first one is enough
    topics_by_shard = topics.group_by do |topic|
      # Removing the last item subscription leaves an empty array behind, so
      # fall through to the packet subscriptions rather than defaulting to shard 0
      objects = item_objects_by_topic[topic].presence || packet_objects_by_topic[topic]
      objects&.first&.db_shard || 0
    end
    topics_by_shard.each do |db_shard, shard_topics|
      store = OpenC3::EphemeralStore.instance(db_shard: db_shard)
      # Pipeline so N topics cost a single round trip instead of N
      results = store.redis_pool.pipelined do
        # XREVRANGE with COUNT 1 returns just the newest entry
        shard_topics.each { |topic| store.xrevrange(topic, count: 1) }
      end
      # Each result is [[msg_id, fields]] (or empty) so dig out the msg_id
      shard_topics.zip(results) { |topic, result| heads[topic] = result&.dig(0, 0) }
    end
    heads
  end

  # Redis stream ids are "<milliseconds>-<sequence>"; return the milliseconds
  def msg_id_ms(msg_id)
    msg_id.split('-')[0].to_i
  end
end
