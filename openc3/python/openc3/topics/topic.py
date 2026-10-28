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

import math
import os
import re
import time

from openc3.utilities.store import EphemeralStore


class TopicMeta(type):
    def __getattr__(cls, func):
        def method(*args, **kwargs):
            return getattr(EphemeralStore.instance(), func)(*args, **kwargs)

        return method


class Topic(metaclass=TopicMeta):
    # Stream trimming contract for the high rate target streams
    # (TELEMETRY__, COMMAND__, DECOM__, DECOMCMD__):
    #
    # The streams are primarily trimmed by their consumers once the data is safely
    # persisted elsewhere:
    #   * TELEMETRY__ / COMMAND__ are trimmed by the log microservice (LogWriter) once a
    #     log file has been moved to the bucket plus LogWriter::CLEANUP_DELAY.
    #   * DECOM__ / DECOMCMD__ are trimmed by the TSDB microservice which keeps
    #     TsdbMicroservice.TRIM_KEEP_MS of data.
    #
    # If a trimmer is absent (logging disabled, no TSDB) or falls far behind, the streams
    # would grow without bound. As a safety net every write to these streams also passes
    # an approximate XADD MINID so no entry older than the safety max age is retained.
    # The max age is OPENC3_STREAM_MAX_AGE_SECONDS (default 600s, 0 or empty disables) and is
    # never less than STREAM_MAX_AGE_MIN_SECONDS. For TELEMETRY__ / COMMAND__ the max age is
    # never less than two log cycles plus the cleanup delay, because historical streaming reads
    # data not yet in the bucket from the stream.
    #
    # When the minid is calculated from now (auto generated ids) it uses this host's clock while
    # Redis generates the ids from its own clock. A writer clock ahead of Redis by more than the
    # max age would trim the entire stream (including the entry being added) so hosts must be
    # time synchronized (NTP).
    STREAM_MAX_AGE_DEFAULT_SECONDS = 600
    # Twice TsdbMicroservice.TRIM_KEEP_MS. Also protects against small clock offsets.
    STREAM_MAX_AGE_MIN_SECONDS = 120
    # LogWriter.CLEANUP_DELAY is defined from this
    LOG_CLEANUP_DELAY_SECONDS = 60
    # TargetModel default log cycle time
    DEFAULT_LOG_CYCLE_TIME_SECONDS = 600
    # How long to wait before retrying a failed log cycle time lookup
    LOG_CYCLE_LOOKUP_RETRY_SECONDS = 60
    # These are calculated on the write path of every packet so they are cached per process.
    # The environment doesn't change while a microservice runs and the log cycle time only
    # changes when the plugin (and therefore the microservices) are reinstalled.
    _stream_max_age_ms = None
    _log_stream_max_age_ms = {}
    _log_cycle_lookup_retry_at = {}

    @classmethod
    def clear_topics(cls, topics, maxlen=0, db_shard=0):
        store = EphemeralStore.instance(db_shard=db_shard)
        for topic in topics:
            store.xtrim(topic, maxlen)

    @classmethod
    def topics(cls, key, scope, db_shard=0):
        return sorted(
            set(
                EphemeralStore.instance(db_shard=db_shard).scan_iter(
                    match=f"{scope}__{key}__*", type="stream", count=100
                )
            )
        )

    @classmethod
    def get_cnt(cls, topic, db_shard=0):
        _, packet = EphemeralStore.instance(db_shard=db_shard).get_newest_message(topic)
        if packet:
            return int(packet[b"received_count"])
        else:
            return 0

    # DB_Shard-aware topic methods for target-specific streams

    @classmethod
    def write_topic(cls, topic, msg_hash, id="*", maxlen=None, approximate=True, db_shard=0, minid=None):
        return EphemeralStore.instance(db_shard=db_shard).write_topic(
            topic, msg_hash, id, maxlen, approximate, minid=minid
        )

    @classmethod
    def stream_max_age_seconds(cls) -> float:
        """Configured safety max age in seconds (<= 0 means disabled)"""
        value = os.environ.get("OPENC3_STREAM_MAX_AGE_SECONDS")
        if value is None:
            return cls.STREAM_MAX_AGE_DEFAULT_SECONDS
        if not value.strip():
            return 0.0
        # Strictly parse and reject nan / inf, which would raise when converted to
        # milliseconds on every write. A typo keeps the safety cap at the default
        # rather than disabling it.
        try:
            seconds = float(value)
        except ValueError:
            seconds = math.nan
        if math.isfinite(seconds):
            return seconds
        from openc3.utilities.logger import Logger

        Logger.warn(
            f"OPENC3_STREAM_MAX_AGE_SECONDS of '{value}' is invalid, using {cls.STREAM_MAX_AGE_DEFAULT_SECONDS}"
        )
        return cls.STREAM_MAX_AGE_DEFAULT_SECONDS

    @classmethod
    def stream_max_age_ms(cls) -> int:
        """Cached safety max age in milliseconds (0 means disabled)"""
        if cls._stream_max_age_ms is None:
            seconds = cls.stream_max_age_seconds()
            if seconds <= 0:
                cls._stream_max_age_ms = 0
            elif seconds < cls.STREAM_MAX_AGE_MIN_SECONDS:
                from openc3.utilities.logger import Logger

                Logger.warn(
                    f"OPENC3_STREAM_MAX_AGE_SECONDS of {seconds} is below the minimum, "
                    f"using {cls.STREAM_MAX_AGE_MIN_SECONDS}"
                )
                cls._stream_max_age_ms = cls.STREAM_MAX_AGE_MIN_SECONDS * 1000
            else:
                cls._stream_max_age_ms = int(seconds * 1000)
        return cls._stream_max_age_ms

    @classmethod
    def stream_safety_minid(cls, id="*", max_age_ms=None):
        """Calculates the MINID to pass to XADD to cap the age of entries in a target stream.

        The cap is anchored to the id being written (or now for auto generated ids) so an
        explicitly id'd entry (e.g. decom reusing the raw packet id) is never trimmed by its own add.
        max_age_ms defaults to the configured stream_max_age_ms.
        Returns None if the safety cap is disabled.
        """
        if max_age_ms is None:
            max_age_ms = cls.stream_max_age_ms()
        if max_age_ms <= 0:
            return None
        if not id or id == "*":
            base_ms = int(time.time() * 1000)
        else:
            entry_id = id.decode() if isinstance(id, bytes) else str(id)
            base_ms = int(entry_id.partition("-")[0])
        minid_ms = base_ms - max_age_ms
        if minid_ms <= 0:
            return None
        return str(minid_ms)

    @classmethod
    def log_stream_safety_minid(cls, target_name, cmd_or_tlm, scope):
        """Calculates the MINID for a TELEMETRY__ / COMMAND__ stream write which also never
        trims younger than log_stream_min_age_seconds. The resulting max age is cached per stream.
        """
        key = (scope, target_name, cmd_or_tlm)
        max_age_ms = cls._log_stream_max_age_ms.get(key)
        if max_age_ms is None:
            max_age_ms = cls.log_stream_max_age_ms(target_name, cmd_or_tlm, scope)
            if max_age_ms is None:
                return None  # Log cycle time unknown so don't cap yet
            cls._log_stream_max_age_ms[key] = max_age_ms
        return cls.stream_safety_minid(max_age_ms=max_age_ms)

    @classmethod
    def log_stream_max_age_ms(cls, target_name, cmd_or_tlm, scope):
        """Max age in milliseconds for a TELEMETRY__ / COMMAND__ stream (0 means disabled)
        or None if the log cycle time couldn't be determined. Guessing the log cycle time
        could trim data historical streaming still needs, so the stream isn't capped until a
        lookup (retried every LOG_CYCLE_LOOKUP_RETRY_SECONDS) succeeds.
        """
        max_age_ms = cls.stream_max_age_ms()
        if max_age_ms <= 0:
            return max_age_ms
        key = (scope, target_name, cmd_or_tlm)
        now = time.monotonic()
        retry_at = cls._log_cycle_lookup_retry_at.get(key)
        if retry_at is not None and now < retry_at:
            return None
        try:
            min_age_ms = cls.log_stream_min_age_seconds(target_name, cmd_or_tlm, scope) * 1000
        except Exception as error:
            from openc3.utilities.logger import Logger

            Logger.warn(
                f"Unable to determine log cycle time for {target_name} {cmd_or_tlm}, stream age not capped: {error}"
            )
            cls._log_cycle_lookup_retry_at[key] = now + cls.LOG_CYCLE_LOOKUP_RETRY_SECONDS
            return None
        cls._log_cycle_lookup_retry_at.pop(key, None)
        return max(max_age_ms, min_age_ms)

    @classmethod
    def log_stream_min_age_seconds(cls, target_name, cmd_or_tlm, scope):
        """Minimum age to retain in a TELEMETRY__ / COMMAND__ stream so the log microservice
        and historical streaming always have the data not yet moved to the bucket.
        Raises if the TargetModel lookup fails.
        """
        from openc3.models.target_model import TargetModel

        cycle_time = cls.DEFAULT_LOG_CYCLE_TIME_SECONDS
        model = TargetModel.get(name=target_name, scope=scope)
        if model:
            field = "cmd_log_cycle_time" if cmd_or_tlm == "CMD" else "tlm_log_cycle_time"
            value = int(model.get(field) or 0)
            if value > 0:
                cycle_time = value
        return 2 * (cycle_time + cls.LOG_CLEANUP_DELAY_SECONDS)

    @classmethod
    def clear_stream_max_age_cache(cls):
        cls._stream_max_age_ms = None
        cls._log_stream_max_age_ms = {}
        cls._log_cycle_lookup_retry_at = {}

    @classmethod
    def read_topics(cls, topics, offsets=None, timeout_ms=1000, count=None, db_shard=0):
        return EphemeralStore.instance(db_shard=db_shard).read_topics(topics, offsets, timeout_ms, count)

    @classmethod
    def get_newest_message(cls, topic, db_shard=0):
        return EphemeralStore.instance(db_shard=db_shard).get_newest_message(topic)

    @classmethod
    def get_oldest_message(cls, topic, db_shard=0):
        return EphemeralStore.instance(db_shard=db_shard).get_oldest_message(topic)

    @classmethod
    def get_last_offset(cls, topic, db_shard=0):
        return EphemeralStore.instance(db_shard=db_shard).get_last_offset(topic)

    @classmethod
    def update_topic_offsets(cls, topics, db_shard=0):
        return EphemeralStore.instance(db_shard=db_shard).update_topic_offsets(topics)

    @classmethod
    def trim_topic(cls, topic, minid, approximate=True, limit=0, db_shard=0):
        return EphemeralStore.instance(db_shard=db_shard).trim_topic(topic, minid, approximate, limit=limit)

    @classmethod
    def target_name_from_topic(cls, topic):
        """Extract the target name from the {TARGET} hash tag in a topic like
        DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS. Returns None if there is none."""
        match = re.search(r"__\{([^}]+)\}__", topic)
        return match.group(1) if match else None

    @classmethod
    def group_topics_by_db_shard(cls, topics, target_pattern, scope):
        """Group topics by db_shard. Topics matching target_pattern are db_sharded; others go to db_shard 0."""
        from openc3.utilities.store import Store

        groups = {}
        for topic in topics:
            if target_pattern in topic:
                if "TARGET__" in target_pattern:
                    target_name = topic.split("TARGET__")[1] if "TARGET__" in topic else None
                else:
                    target_name = cls.target_name_from_topic(topic)
                db_shard = int(Store.db_shard_for_target(target_name, scope=scope) or 0)
            else:
                db_shard = 0
            if db_shard not in groups:
                groups[db_shard] = []
            groups[db_shard].append(topic)
        return groups

    @staticmethod
    def all_same_db_shard(db_shard_groups):
        """Check if all db_shard groups resolve to a single db_shard (fast path)."""
        return len(db_shard_groups) <= 1

    @classmethod
    def write_ack(cls, topic, result, msg_id, db_shard=0):
        """Build the ACK topic from a command/router topic and write the ack."""
        ack_topic = topic.split("__")
        ack_topic[1] = "ACK" + ack_topic[1]
        ack_topic = "__".join(ack_topic)
        Topic.write_topic(ack_topic, {"result": result, "id": msg_id}, "*", 100, db_shard=db_shard)
