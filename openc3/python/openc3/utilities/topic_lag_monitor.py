# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import threading
import time

from openc3.utilities.logger import Logger


class TopicLagMonitor:
    """Tracks how far a microservice is behind the Redis streams it consumes.

    Every processed message updates the lag gauge metric with the maximum lag
    seen over the last metric update interval. When the lag crosses the warning
    or critical threshold a user notification is published, and a recovery
    notification is published once the microservice has caught back up (with
    hysteresis so a lag hovering around a threshold doesn't flap).

    Streams are trimmed by time once their data is logged, so a consumer can
    only skip trimmed data after lagging far past the critical threshold.

    Recovery assumes each monitor is fed by a single reader that reads every
    stream with pending entries on each XREAD (COUNT limits how many entries
    but not which streams). A backlogged topic then reports its high lag every
    read cycle, so fresh messages on other topics can't clear the alert early.
    """

    OK = 0
    WARN = 1
    CRITICAL = 2

    # Lag must drop below threshold * CLEAR_RATIO to count as recovering
    CLEAR_RATIO = 0.5
    # Matches Metric.UPDATE_INTERVAL so every lag spike is published
    GAUGE_WINDOW_SECONDS = 5.0

    def __init__(self, name, logger, metric=None):
        self.name = name
        self.logger = logger
        self.metric = metric
        self.warn_seconds = self._env_float("OPENC3_LAG_WARN_SECONDS", 5.0)
        self.critical_seconds = self._env_float("OPENC3_LAG_CRITICAL_SECONDS", 30.0)
        self.clear_seconds = self._env_float("OPENC3_LAG_CLEAR_SECONDS", 10.0)
        self.renotify_seconds = self._env_float("OPENC3_LAG_RENOTIFY_SECONDS", 300.0)
        self.state = self.OK
        self.max_lag = 0.0
        self.max_lag_topic = None
        self.below_since = None
        self.below_ok_since = None
        self.last_notify = None
        self.last_notify_level = self.OK
        self.notified = False
        self.gauges = {}
        self.mutex = threading.Lock()

    def record(self, topic, msg_id, metric_name=None, help=None, now=None):
        """Record that a message was read from a topic and return the lag in seconds"""
        if now is None:
            now = time.time()
        lag = now - (self._id_ms(msg_id) / 1000.0)
        if self.metric is not None and metric_name:
            self._update_gauge(metric_name, help, lag, now)
        if self.warn_seconds <= 0:  # Notifications disabled
            return lag

        # Fast path for the common case of keeping up: skip the mutex and state machine
        if self.state == self.OK and lag < self.warn_seconds:
            return lag

        with self.mutex:
            self._update_state(topic, lag, now)
        return lag

    def _update_gauge(self, metric_name, help, lag, now):
        """Topics read by one microservice can lag by very different amounts, so
        publish the maximum lag rather than whichever topic was read last. The
        previous window's maximum is held through the current window so a spike
        just before a window boundary is still published."""
        if self.metric is None:
            return
        window = int(now / self.GAUGE_WINDOW_SECONDS)
        gauge = self.gauges.get(metric_name)
        if gauge is None:
            gauge = {"window": window, "max": lag, "previous_max": 0.0}
            self.gauges[metric_name] = gauge
        elif window != gauge["window"]:
            gauge["previous_max"] = gauge["max"] if window == gauge["window"] + 1 else 0.0
            gauge["window"] = window
            gauge["max"] = lag
        elif lag > gauge["max"]:
            gauge["max"] = lag
        else:
            return  # Published value is unchanged
        value = max(gauge["max"], gauge["previous_max"])
        self.metric.set(name=metric_name, value=value, type="gauge", unit="seconds", help=help)

    def _update_state(self, topic, lag, now):
        if lag < self.warn_seconds * self.CLEAR_RATIO:
            if self.below_ok_since is None:
                self.below_ok_since = now
        else:
            self.below_ok_since = None
        if lag > self.max_lag:
            self.max_lag = lag
            self.max_lag_topic = topic
        if lag >= self.critical_seconds:
            level = self.CRITICAL
        elif lag >= self.warn_seconds:
            level = self.WARN
        else:
            level = self.OK

        if level > self.state:
            self.state = level
            self.below_since = None
            # Bursty load can make a microservice recover and fall behind over and
            # over, so falling back to an already announced level soon after the
            # last notification continues that episode rather than notifying again
            if not (
                self.last_notify is not None
                and level <= self.last_notify_level
                and (now - self.last_notify) < self.renotify_seconds
            ):
                self._notify_lag(topic, lag, now)
        elif self.state != self.OK:
            threshold = self.critical_seconds if self.state == self.CRITICAL else self.warn_seconds
            if lag < threshold * self.CLEAR_RATIO:
                if self.below_since is None:
                    self.below_since = now
                if (now - self.below_since) >= self.clear_seconds:
                    self.below_since = None
                    if self.state == self.CRITICAL and (
                        self.below_ok_since is None or (now - self.below_ok_since) < self.clear_seconds
                    ):
                        self.state = self.WARN
                        self.below_since = self.below_ok_since
                    else:
                        self.state = self.OK
                        if self.notified:
                            self.logger.info(
                                f"{self.name} has caught up processing "
                                f"(max lag {round(self.max_lag, 1)}s on {self.max_lag_topic})",
                                type=Logger.NOTIFICATION,
                            )
                        self.notified = False
                        self.max_lag = 0.0
                        self.max_lag_topic = None
            else:
                self.below_since = None
                if (now - self.last_notify) >= self.renotify_seconds:
                    self._notify_lag(topic, lag, now)

    def _notify_lag(self, topic, lag, now):
        message = (
            f"{self.name} is falling behind processing: {round(lag, 1)}s behind on {topic} "
            f"(max {round(self.max_lag, 1)}s on {self.max_lag_topic})"
        )
        if self.state == self.CRITICAL:
            self.logger.error(message, type=Logger.NOTIFICATION)
        else:
            self.logger.warn(message, type=Logger.NOTIFICATION)
        self.last_notify = now
        self.last_notify_level = self.state
        self.notified = True

    @staticmethod
    def _id_ms(msg_id):
        if isinstance(msg_id, bytes):
            msg_id = msg_id.decode()
        return int(str(msg_id).split("-")[0])

    @staticmethod
    def _env_float(name, default):
        value = os.environ.get(name, "").strip()
        if not value:
            return default
        try:
            return float(value)
        except ValueError:
            return default
