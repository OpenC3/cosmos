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

import os
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
    # The max age is OPENC3_STREAM_MAX_AGE_SECONDS (default 600s, 0 or empty disables).
    # For TELEMETRY__ / COMMAND__ the max age is never less than two log cycles plus the
    # cleanup delay, because historical streaming reads data not yet in the bucket from
    # the stream.
    STREAM_MAX_AGE_DEFAULT_SECONDS = 600
    # Mirrors LogWriter::CLEANUP_DELAY and the TargetModel default log cycle time
    LOG_CLEANUP_DELAY_SECONDS = 60
    DEFAULT_LOG_CYCLE_TIME_SECONDS = 600
    _log_cycle_times = {}

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
        try:
            return float(value)
        except ValueError:
            return 0.0

    @classmethod
    def stream_safety_minid(cls, id="*", min_age_seconds=0):
        """Calculates the MINID to pass to XADD to cap the age of entries in a target stream.

        The cap is anchored to the id being written (or now for auto generated ids) so an
        explicitly id'd entry (e.g. decom reusing the raw packet id) is never trimmed by its own add.
        Returns None if the safety cap is disabled.
        """
        max_age = cls.stream_max_age_seconds()
        if max_age <= 0:
            return None
        max_age = max(max_age, min_age_seconds)
        if not id or id == "*":
            base_ms = int(time.time() * 1000)
        else:
            if isinstance(id, bytes):
                id = id.decode()
            base_ms = int(str(id).split("-")[0])
        minid_ms = base_ms - int(max_age * 1000)
        if minid_ms <= 0:
            return None
        return str(minid_ms)

    @classmethod
    def log_stream_min_age_seconds(cls, target_name, cmd_or_tlm, scope):
        """Minimum age to retain in a TELEMETRY__ / COMMAND__ stream so the log microservice
        and historical streaming always have the data not yet moved to the bucket.

        The log cycle time is cached per process since it only changes when the plugin
        (and therefore the microservices) are reinstalled.
        """
        key = f"{scope}__{target_name}__{cmd_or_tlm}"
        cycle_time = cls._log_cycle_times.get(key)
        if cycle_time is None:
            cycle_time = cls.DEFAULT_LOG_CYCLE_TIME_SECONDS
            try:
                from openc3.models.target_model import TargetModel

                model = TargetModel.get(name=target_name, scope=scope)
                if model:
                    field = "cmd_log_cycle_time" if cmd_or_tlm == "CMD" else "tlm_log_cycle_time"
                    value = int(model.get(field) or 0)
                    if value > 0:
                        cycle_time = value
            except Exception as error:
                from openc3.utilities.logger import Logger

                Logger.warn(f"Unable to determine log cycle time for {target_name}: {error}")
            cls._log_cycle_times[key] = cycle_time
        return 2 * (cycle_time + cls.LOG_CLEANUP_DELAY_SECONDS)

    @classmethod
    def clear_log_cycle_times(cls):
        cls._log_cycle_times = {}

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
    def group_topics_by_db_shard(cls, topics, target_pattern, scope):
        """Group topics by db_shard. Topics matching target_pattern are db_sharded; others go to db_shard 0."""
        import re

        from openc3.utilities.store import Store

        groups = {}
        for topic in topics:
            if target_pattern in topic:
                if "TARGET__" in target_pattern:
                    target_name = topic.split("TARGET__")[1] if "TARGET__" in topic else None
                else:
                    match = re.search(r"__\{?([^}_]+)\}?__", topic)
                    target_name = match.group(1) if match else None
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
