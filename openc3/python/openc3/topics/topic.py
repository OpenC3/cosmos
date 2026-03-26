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
    def clear_topics(cls, topics, maxlen=0, shard=0):
        store = EphemeralStore.instance(shard=shard)
        for topic in topics:
            store.xtrim(topic, maxlen)

    @classmethod
    def topics(cls, key, scope, shard=0):
        return sorted(set(EphemeralStore.instance(shard=shard).scan_iter(match=f"{scope}__{key}__*", type="stream", count=100)))

    @classmethod
    def get_cnt(cls, topic, shard=0):
        _, packet = EphemeralStore.instance(shard=shard).get_newest_message(topic)
        if packet:
            return int(packet[b"received_count"])
        else:
            return 0

    # Shard-aware topic methods for target-specific streams

    @classmethod
    def write_topic(cls, topic, msg_hash, id="*", maxlen=None, approximate=True, shard=0):
        return EphemeralStore.instance(shard=shard).write_topic(topic, msg_hash, id, maxlen, approximate)

    @classmethod
    def read_topics(cls, topics, offsets=None, timeout_ms=1000, count=None, shard=0):
        return EphemeralStore.instance(shard=shard).read_topics(topics, offsets, timeout_ms, count)

    @classmethod
    def get_newest_message(cls, topic, shard=0):
        return EphemeralStore.instance(shard=shard).get_newest_message(topic)

    @classmethod
    def get_oldest_message(cls, topic, shard=0):
        return EphemeralStore.instance(shard=shard).get_oldest_message(topic)

    @classmethod
    def get_last_offset(cls, topic, shard=0):
        return EphemeralStore.instance(shard=shard).get_last_offset(topic)

    @classmethod
    def update_topic_offsets(cls, topics, shard=0):
        return EphemeralStore.instance(shard=shard).update_topic_offsets(topics)

    @classmethod
    def trim_topic(cls, topic, minid, approximate=True, limit=0, shard=0):
        return EphemeralStore.instance(shard=shard).trim_topic(topic, minid, approximate, limit=limit)
