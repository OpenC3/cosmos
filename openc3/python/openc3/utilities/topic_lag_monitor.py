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
import re
import threading
import time

from openc3.utilities.logger import Logger
from openc3.utilities.store import EphemeralStore, Store


HASHTAG_RE = re.compile(r"\{([^}]+)\}")


class TopicLagMonitor:
    """Tracks how far a microservice is behind the Redis streams it consumes.

    Every processed message updates the lag gauge metric. When the lag crosses
    the warning or critical threshold a user notification is published, and a
    recovery notification is published once the microservice has caught back
    up (with hysteresis so a lag hovering around a threshold doesn't flap).

    Streams are trimmed by wall clock time, so a consumer that falls far enough
    behind silently skips data that was trimmed before it was read. While
    lagging, gaps between consecutive message ids are checked against the
    stream's max-deleted-entry-id and an alert is published if data was lost.
    """

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

    def __init__(self, name, logger, metric=None, scope=None, db_shard=0):
        self.name = name
        self.logger = logger
        self.metric = metric
        self.scope = scope
        self.db_shard = db_shard
        self.warn_seconds = self._env_float("OPENC3_LAG_WARN_SECONDS", 5.0)
        self.critical_seconds = self._env_float("OPENC3_LAG_CRITICAL_SECONDS", 30.0)
        self.clear_seconds = self._env_float("OPENC3_LAG_CLEAR_SECONDS", 10.0)
        self.renotify_seconds = self._env_float("OPENC3_LAG_RENOTIFY_SECONDS", 300.0)
        self.state = self.OK
        self.max_lag = 0.0
        self.below_since = None
        self.last_notify = None
        self.last_ids = {}
        self.last_trim_check = {}
        self.skipped = {}
        self.last_skip_notify = None
        self.mutex = threading.Lock()

    def record(self, topic, msg_id, metric_name=None, help=None, now=None):
        """Record that a message was read from a topic and return the lag in seconds"""
        if now is None:
            now = time.time()
        lag = now - (self._id_ms(msg_id) / 1000.0)
        if self.metric is not None and metric_name:
            self.metric.set(name=metric_name, value=lag, type="gauge", unit="seconds", help=help)
        if self.warn_seconds <= 0:  # Notifications disabled
            return lag

        with self.mutex:
            self._update_state(lag, now)
            prev_id = self.last_ids.get(topic)
            self.last_ids[topic] = msg_id
            if prev_id is not None and self.state != self.OK:
                self._check_trimmed(topic, prev_id, msg_id, now)
            self._notify_skipped(now)
        return lag

    def _update_state(self, lag, now):
        if lag > self.max_lag:
            self.max_lag = lag
        if lag >= self.critical_seconds:
            level = self.CRITICAL
        elif lag >= self.warn_seconds:
            level = self.WARN
        else:
            level = self.OK

        if level > self.state:
            self.state = level
            self.below_since = None
            self._notify_lag(lag, now)
        elif self.state != self.OK:
            threshold = self.critical_seconds if self.state == self.CRITICAL else self.warn_seconds
            if lag < threshold * self.CLEAR_RATIO:
                if self.below_since is None:
                    self.below_since = now
                if (now - self.below_since) >= self.clear_seconds:
                    self.below_since = None
                    if self.state == self.CRITICAL and lag >= self.warn_seconds * self.CLEAR_RATIO:
                        self.state = self.WARN
                    else:
                        self.state = self.OK
                        self.logger.info(
                            f"{self.name} has caught up processing (max lag {round(self.max_lag, 1)}s)",
                            type=Logger.NOTIFICATION,
                        )
                        self.max_lag = 0.0
            else:
                self.below_since = None
                if (now - self.last_notify) >= self.renotify_seconds:
                    self._notify_lag(lag, now)

    def _notify_lag(self, lag, now):
        message = f"{self.name} is falling behind processing: {round(lag, 1)}s behind (max {round(self.max_lag, 1)}s)"
        if self.state == self.CRITICAL:
            self.logger.error(message, type=Logger.NOTIFICATION)
        else:
            self.logger.warn(message, type=Logger.NOTIFICATION)
        self.last_notify = now

    def _check_trimmed(self, topic, prev_id, msg_id, now):
        prev_ms = self._id_ms(prev_id)
        if (self._id_ms(msg_id) - prev_ms) / 1000.0 < self.TRIM_CHECK_GAP_SECONDS:
            return
        last_check = self.last_trim_check.get(topic)
        if last_check is not None and (now - last_check) < self.TRIM_CHECK_INTERVAL_SECONDS:
            return
        self.last_trim_check[topic] = now

        try:
            info = EphemeralStore.instance(db_shard=self._db_shard_for(topic)).xinfo_stream(topic)
            max_deleted = info.get("max-deleted-entry-id") if info else None
            if not max_deleted:
                return
            if isinstance(max_deleted, bytes):
                max_deleted = max_deleted.decode()
            # Entries after the last one we processed but before the one we just
            # read were deleted, i.e. they were trimmed before we could read them
            if self._compare_ids(max_deleted, prev_id) > 0 and self._compare_ids(max_deleted, msg_id) < 0:
                skipped = (self._id_ms(max_deleted) - prev_ms) / 1000.0
                self.skipped[topic] = self.skipped.get(topic, 0.0) + skipped
        except Exception as error:
            self.logger.debug(f"{self.name} unable to check {topic} for trimmed data: {error}")

    def _notify_skipped(self, now):
        """Aggregate data skipped alerts so a burst of trims across many topics
        produces a single alert rather than one per topic"""
        if not self.skipped:
            return
        if self.last_skip_notify is not None and (now - self.last_skip_notify) < self.renotify_seconds:
            return

        topics = sorted(self.skipped.items(), key=lambda item: -item[1])
        listed = [f"{topic} (~{round(seconds, 1)}s)" for topic, seconds in topics[: self.MAX_TOPICS_IN_ALERT]]
        if len(topics) > self.MAX_TOPICS_IN_ALERT:
            listed.append(f"and {len(topics) - self.MAX_TOPICS_IN_ALERT} more")
        self.logger.error(
            f"{self.name} fell too far behind and data was trimmed before it was processed: {', '.join(listed)}",
            type=Logger.ALERT,
        )
        self.skipped = {}
        self.last_skip_notify = now

    def _db_shard_for(self, topic):
        # Target topics carry the target name as a Redis hashtag, e.g. SCOPE__DECOM__{TGT}__PKT
        match = HASHTAG_RE.search(topic)
        if not match:
            return self.db_shard
        try:
            return Store.db_shard_for_target(match.group(1), scope=self.scope or topic.split("__")[0])
        except Exception:
            return self.db_shard

    @staticmethod
    def _id_ms(msg_id):
        if isinstance(msg_id, bytes):
            msg_id = msg_id.decode()
        return int(str(msg_id).split("-")[0])

    @staticmethod
    def _compare_ids(a, b):
        def parts(msg_id):
            if isinstance(msg_id, bytes):
                msg_id = msg_id.decode()
            split = str(msg_id).split("-")
            return (int(split[0]), int(split[1]) if len(split) > 1 else 0)

        a_parts = parts(a)
        b_parts = parts(b)
        return (a_parts > b_parts) - (a_parts < b_parts)

    @staticmethod
    def _env_float(name, default):
        value = os.environ.get(name)
        if value is None or value.strip() == "":
            return default
        try:
            return float(value)
        except ValueError:
            return default
