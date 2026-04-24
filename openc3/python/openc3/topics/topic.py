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

from openc3.utilities.store import EphemeralStore


class TopicMeta(type):
    def __getattr__(cls, func):
        def method(*args, **kwargs):
            return getattr(EphemeralStore.instance(), func)(*args, **kwargs)

        return method


class Topic(metaclass=TopicMeta):
    @classmethod
    def clear_topics(cls, topics, maxlen=0, db_shard=0):
        store = EphemeralStore.instance(db_shard=db_shard)
        for topic in topics:
            store.xtrim(topic, maxlen)

    @classmethod
    def topics(cls, key, scope, db_shard=0):
        return sorted(
            set(EphemeralStore.instance(db_shard=db_shard).scan_iter(match=f"{scope}__{key}__*", type="stream", count=100))
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
    def write_topic(cls, topic, msg_hash, id="*", maxlen=None, approximate=True, db_shard=0):
        return EphemeralStore.instance(db_shard=db_shard).write_topic(topic, msg_hash, id, maxlen, approximate)

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
