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

module OpenC3
  # Tracks how far a microservice is behind the Redis streams it consumes.
  #
  # Every processed message updates the lag gauge metric with the maximum lag
  # seen over the last metric update interval. When the lag crosses the warning
  # or critical threshold a user notification is published, and a recovery
  # notification is published once the microservice has caught back up (with
  # hysteresis so a lag hovering around a threshold doesn't flap).
  #
  # Streams are trimmed by time once their data is logged, so a consumer can
  # only skip trimmed data after lagging far past the critical threshold.
  #
  # Recovery assumes each monitor is fed by a single reader that reads every
  # stream with pending entries on each XREAD (COUNT limits how many entries
  # but not which streams). A backlogged topic then reports its high lag every
  # read cycle, so fresh messages on other topics can't clear the alert early.
  class TopicLagMonitor
    OK = 0
    WARN = 1
    CRITICAL = 2

    # Lag must drop below threshold * CLEAR_RATIO to count as recovering
    CLEAR_RATIO = 0.5
    # Matches Metric::UPDATE_INTERVAL so every lag spike is published
    GAUGE_WINDOW_SECONDS = 5.0

    attr_reader :state

    def initialize(name:, logger:, metric: nil)
      @name = name
      @logger = logger
      @metric = metric
      @warn_seconds = env_float('OPENC3_LAG_WARN_SECONDS', 5.0)
      @critical_seconds = env_float('OPENC3_LAG_CRITICAL_SECONDS', 30.0)
      @clear_seconds = env_float('OPENC3_LAG_CLEAR_SECONDS', 10.0)
      @renotify_seconds = env_float('OPENC3_LAG_RENOTIFY_SECONDS', 300.0)
      @state = OK
      @max_lag = 0.0
      @max_lag_topic = nil
      @below_since = nil
      @below_ok_since = nil
      @last_notify = nil
      @last_notify_level = OK
      @notified = false
      @gauges = {}
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
      update_gauge(metric_name, help, lag, now) if @metric and metric_name
      return lag if @warn_seconds <= 0 # Notifications disabled

      # Fast path for the common case of keeping up: skip the mutex and state machine
      return lag if @state == OK and lag < @warn_seconds

      @mutex.synchronize { update_state(topic, lag, now) }
      return lag
    end

    protected

    # Topics read by one microservice can lag by very different amounts, so
    # publish the maximum lag rather than whichever topic was read last. The
    # previous window's maximum is held through the current window so a spike
    # just before a window boundary is still published.
    def update_gauge(metric_name, help, lag, now)
      window = (now / GAUGE_WINDOW_SECONDS).to_i
      gauge = @gauges[metric_name]
      if gauge.nil?
        gauge = @gauges[metric_name] = { window: window, max: lag, previous_max: 0.0 }
      elsif window != gauge[:window]
        gauge[:previous_max] = (window == gauge[:window] + 1) ? gauge[:max] : 0.0
        gauge[:window] = window
        gauge[:max] = lag
      elsif lag > gauge[:max]
        gauge[:max] = lag
      else
        return # Published value is unchanged
      end
      value = (gauge[:max] > gauge[:previous_max]) ? gauge[:max] : gauge[:previous_max]
      @metric.set(name: metric_name, value: value, type: 'gauge', unit: 'seconds', help: help)
    end

    def update_state(topic, lag, now)
      if lag < @warn_seconds * CLEAR_RATIO
        @below_ok_since ||= now
      else
        @below_ok_since = nil
      end
      if lag > @max_lag
        @max_lag = lag
        @max_lag_topic = topic
      end
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
        # Bursty load can make a microservice recover and fall behind over and
        # over, so falling back to an already announced level soon after the
        # last notification continues that episode rather than notifying again
        unless @last_notify and level <= @last_notify_level and (now - @last_notify) < @renotify_seconds
          notify_lag(topic, lag, now)
        end
      elsif @state != OK
        threshold = (@state == CRITICAL) ? @critical_seconds : @warn_seconds
        if lag < threshold * CLEAR_RATIO
          @below_since ||= now
          if (now - @below_since) >= @clear_seconds
            @below_since = nil
            if @state == CRITICAL and (@below_ok_since.nil? or (now - @below_ok_since) < @clear_seconds)
              @state = WARN
              @below_since = @below_ok_since
            else
              @state = OK
              @logger.info("#{@name} has caught up processing (max lag #{@max_lag.round(1)}s on #{@max_lag_topic})", type: Logger::NOTIFICATION) if @notified
              @notified = false
              @max_lag = 0.0
              @max_lag_topic = nil
            end
          end
        else
          @below_since = nil
          notify_lag(topic, lag, now) if (now - @last_notify) >= @renotify_seconds
        end
      end
    end

    def notify_lag(topic, lag, now)
      message = "#{@name} is falling behind processing: #{lag.round(1)}s behind on #{topic} (max #{@max_lag.round(1)}s on #{@max_lag_topic})"
      if @state == CRITICAL
        @logger.error(message, type: Logger::NOTIFICATION)
      else
        @logger.warn(message, type: Logger::NOTIFICATION)
      end
      @last_notify = now
      @last_notify_level = @state
      @notified = true
    end

    def id_ms(id)
      id.to_s.split('-')[0].to_i
    end

    def env_float(name, default)
      value = ENV.fetch(name, '').strip
      return default if value.empty?
      Float(value)
    rescue ArgumentError
      default
    end
  end
end
