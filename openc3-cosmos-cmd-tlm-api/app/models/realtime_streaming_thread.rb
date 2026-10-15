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
    @max_lag_seconds = ENV.fetch('OPENC3_STREAMING_MAX_LAG_SECONDS', DEFAULT_MAX_LAG_SECONDS).to_f
    @behind_since = nil
    @behind_lag = nil
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
    return if @max_lag_seconds <= 0 or newest_msg_ids.empty?

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return if @last_lag_check and (now - @last_lag_check) < LAG_CHECK_INTERVAL_SECONDS
    @last_lag_check = now

    heads = stream_heads(newest_msg_ids.keys, item_objects_by_topic, packet_objects_by_topic)
    topic_lags = {}
    newest_msg_ids.each do |topic, msg_id|
      head = heads[topic]
      next unless head
      topic_lags[topic] = (msg_id_ms(head) - msg_id_ms(msg_id)) / 1000.0
    end
    lag = topic_lags.values.max || 0.0
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

    skip_ahead(lag, topic_lags, heads, item_objects_by_topic, packet_objects_by_topic)
    @behind_since = nil
    @behind_lag = nil
  end

  # Only topics that are actually behind are advanced so up to date topics
  # don't lose messages that arrived during this pass
  def skip_ahead(lag, topic_lags, heads, item_objects_by_topic, packet_objects_by_topic)
    OpenC3::Logger.warn("Realtime streaming fell #{lag.round(1)}s behind, skipping ahead to the latest data")
    topic_lags.each do |topic, topic_lag|
      next if topic_lag <= @max_lag_seconds
      objects = (item_objects_by_topic[topic] || []) + (packet_objects_by_topic[topic] || [])
      objects.each { |object| object.offset = heads[topic] }
    end
    @streaming_api.transmit_notice('SKIPPED', "Streaming fell behind realtime, skipped #{lag.round(1)}s of data", skipped_seconds: lag.round(3))
  end

  # Returns the newest msg_id of each topic using one pipelined round trip per db_shard
  def stream_heads(topics, item_objects_by_topic, packet_objects_by_topic)
    heads = {}
    topics_by_shard = topics.group_by do |topic|
      objects = item_objects_by_topic[topic] || packet_objects_by_topic[topic]
      objects&.first&.db_shard || 0
    end
    topics_by_shard.each do |db_shard, shard_topics|
      store = OpenC3::EphemeralStore.instance(db_shard: db_shard)
      results = store.redis_pool.pipelined do
        shard_topics.each { |topic| store.xrevrange(topic, count: 1) }
      end
      shard_topics.zip(results) { |topic, result| heads[topic] = result&.dig(0, 0) }
    end
    heads
  end

  def msg_id_ms(msg_id)
    msg_id.split('-')[0].to_i
  end
end
