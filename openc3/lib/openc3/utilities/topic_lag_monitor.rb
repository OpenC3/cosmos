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

require 'openc3/utilities/logger'
require 'openc3/utilities/store'

module OpenC3
  # Tracks how far a microservice is behind the Redis streams it consumes.
  #
  # Every processed message updates the lag gauge metric. When the lag crosses
  # the warning or critical threshold a user notification is published, and a
  # recovery notification is published once the microservice has caught back
  # up (with hysteresis so a lag hovering around a threshold doesn't flap).
  #
  # Streams are trimmed by wall clock time, so a consumer that falls far enough
  # behind silently skips data that was trimmed before it was read. While
  # lagging, gaps between consecutive message ids are checked against the
  # stream's max-deleted-entry-id and an alert is published if data was lost.
  class TopicLagMonitor
    OK = 0
    WARN = 1
    CRITICAL = 2

    # Lag must drop below threshold * CLEAR_RATIO to count as recovering
    CLEAR_RATIO = 0.5
    # Only look for trimmed data when consecutive message ids are this far apart
    TRIM_CHECK_GAP_SECONDS = 1.0
    # Minimum time between trimmed data checks on a single topic
    TRIM_CHECK_INTERVAL_SECONDS = 1.0
    # Maximum topics to list in a data skipped alert
    MAX_TOPICS_IN_ALERT = 5

    attr_reader :state

    def initialize(name:, logger:, metric: nil, scope: nil, db_shard: 0)
      @name = name
      @logger = logger
      @metric = metric
      @scope = scope
      @db_shard = db_shard
      @warn_seconds = env_float('OPENC3_LAG_WARN_SECONDS', 5.0)
      @critical_seconds = env_float('OPENC3_LAG_CRITICAL_SECONDS', 30.0)
      @clear_seconds = env_float('OPENC3_LAG_CLEAR_SECONDS', 10.0)
      @renotify_seconds = env_float('OPENC3_LAG_RENOTIFY_SECONDS', 300.0)
      @state = OK
      @max_lag = 0.0
      @below_since = nil
      @last_notify = nil
      @last_ids = {}
      @last_trim_check = {}
      @skipped = {}
      @last_skip_notify = nil
      @mutex = Mutex.new
    end

    # Record that a message was read from a topic
    #
    # @param topic [String] Redis stream the message was read from
    # @param msg_id [String] Redis stream id of the message
    # @param metric_name [String] Gauge metric to update with the lag
    # @param help [String] Help text for the gauge metric
    # @return [Float] The lag in seconds
    def record(topic, msg_id, metric_name: nil, help: nil, now: Time.now.to_f)
      lag = now - (id_ms(msg_id) / 1000.0)
      @metric.set(name: metric_name, value: lag, type: 'gauge', unit: 'seconds', help: help) if @metric and metric_name
      return lag if @warn_seconds <= 0 # Notifications disabled

      @mutex.synchronize do
        update_state(lag, now)
        prev_id = @last_ids[topic]
        @last_ids[topic] = msg_id
        check_trimmed(topic, prev_id, msg_id, now) if prev_id and @state != OK
        notify_skipped(now)
      end
      return lag
    end

    protected

    def update_state(lag, now)
      @max_lag = lag if lag > @max_lag
      level = if lag >= @critical_seconds
        CRITICAL
      elsif lag >= @warn_seconds
        WARN
      else
        OK
      end

      if level > @state
        @state = level
        @below_since = nil
        notify_lag(lag, now)
      elsif @state != OK
        threshold = (@state == CRITICAL) ? @critical_seconds : @warn_seconds
        if lag < threshold * CLEAR_RATIO
          @below_since ||= now
          if (now - @below_since) >= @clear_seconds
            @below_since = nil
            if @state == CRITICAL and lag >= @warn_seconds * CLEAR_RATIO
              @state = WARN
            else
              @state = OK
              @logger.info("#{@name} has caught up processing (max lag #{@max_lag.round(1)}s)", type: Logger::NOTIFICATION)
              @max_lag = 0.0
            end
          end
        else
          @below_since = nil
          notify_lag(lag, now) if (now - @last_notify) >= @renotify_seconds
        end
      end
    end

    def notify_lag(lag, now)
      message = "#{@name} is falling behind processing: #{lag.round(1)}s behind (max #{@max_lag.round(1)}s)"
      if @state == CRITICAL
        @logger.error(message, type: Logger::NOTIFICATION)
      else
        @logger.warn(message, type: Logger::NOTIFICATION)
      end
      @last_notify = now
    end

    def check_trimmed(topic, prev_id, msg_id, now)
      prev_ms = id_ms(prev_id)
      return if (id_ms(msg_id) - prev_ms) / 1000.0 < TRIM_CHECK_GAP_SECONDS

      last_check = @last_trim_check[topic]
      return if last_check and (now - last_check) < TRIM_CHECK_INTERVAL_SECONDS
      @last_trim_check[topic] = now

      info = EphemeralStore.instance(db_shard: db_shard_for(topic)).xinfo(:stream, topic)
      max_deleted = info && info['max-deleted-entry-id']
      return unless max_deleted
      # Entries after the last one we processed but before the one we just
      # read were deleted, i.e. they were trimmed before we could read them
      if compare_ids(max_deleted, prev_id) > 0 and compare_ids(max_deleted, msg_id) < 0
        skipped = (id_ms(max_deleted) - prev_ms) / 1000.0
        @skipped[topic] = (@skipped[topic] || 0.0) + skipped
      end
    rescue => e
      @logger.debug("#{@name} unable to check #{topic} for trimmed data: #{e.message}")
    end

    # Aggregate data skipped alerts so a burst of trims across many topics
    # produces a single alert rather than one per topic
    def notify_skipped(now)
      return if @skipped.empty?
      return if @last_skip_notify and (now - @last_skip_notify) < @renotify_seconds

      topics = @skipped.sort_by { |_topic, seconds| -seconds }
      listed = topics[0...MAX_TOPICS_IN_ALERT].map { |topic, seconds| "#{topic} (~#{seconds.round(1)}s)" }
      listed << "and #{topics.length - MAX_TOPICS_IN_ALERT} more" if topics.length > MAX_TOPICS_IN_ALERT
      @logger.error("#{@name} fell too far behind and data was trimmed before it was processed: #{listed.join(', ')}", type: Logger::ALERT)
      @skipped = {}
      @last_skip_notify = now
    end

    def db_shard_for(topic)
      # Target topics carry the target name as a Redis hashtag, e.g. SCOPE__DECOM__{TGT}__PKT
      match = topic.match(/\{([^}]+)\}/)
      return @db_shard unless match
      return Store.db_shard_for_target(match[1], scope: @scope || topic.split('__')[0])
    rescue
      return @db_shard
    end

    def id_ms(id)
      id.to_s.split('-')[0].to_i
    end

    def compare_ids(a, b)
      a_ms, a_seq = a.to_s.split('-').map(&:to_i)
      b_ms, b_seq = b.to_s.split('-').map(&:to_i)
      [a_ms, a_seq.to_i] <=> [b_ms, b_seq.to_i]
    end

    def env_float(name, default)
      value = ENV[name]
      return default if value.nil? or value.strip.empty?
      Float(value)
    rescue ArgumentError
      default
    end
  end
end
