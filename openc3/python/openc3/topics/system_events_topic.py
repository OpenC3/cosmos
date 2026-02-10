# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json

from openc3.topics.topic import Topic


class SystemEventsTopic(Topic):
    PRIMARY_KEY = "OPENC3__SYSTEM__EVENTS"

    @classmethod
    def update_topic_offsets(cls):
        Topic.update_topic_offsets([cls.PRIMARY_KEY])

    @classmethod
    def write(cls, type, event):
        event["type"] = type
        Topic.write_topic(cls.PRIMARY_KEY, {"event": json.dumps(event)}, "*", 1000)

    @classmethod
    def read(cls):
        for _topic, _msg_id, msg_hash, _redis in Topic.read_topics([cls.PRIMARY_KEY]):
            yield json.loads(msg_hash[b"event"].decode())
