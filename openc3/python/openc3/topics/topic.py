# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
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
    def clear_topics(cls, topics, maxlen=0):
        for topic in topics:
            EphemeralStore.xtrim(topic, maxlen)

    @classmethod
    def topics(cls, key, scope):
        return sorted(set(list(EphemeralStore.scan_iter(match=f"{scope}__{key}__*", type="stream", count=100))))

    @classmethod
    def get_cnt(cls, topic):
        _, packet = EphemeralStore.get_newest_message(topic)
        if packet:
            return int(packet[b"received_count"])
        else:
            return 0
