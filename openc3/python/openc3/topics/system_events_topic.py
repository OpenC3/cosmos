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
from openc3.utilities.store import Store


class SystemEventsTopic(Topic):
    PRIMARY_KEY = "OPENC3__SYSTEM__EVENTS"

    @classmethod
    def _active_shards(cls):
        """Collect all unique target shards from TargetModel data on shard 0."""
        shards = {0}
        # Iterate all scopes to find all target shards
        for key in Store.scan_iter(match="*__openc3_targets", type="hash", count=100):
            decoded_key = key.decode() if isinstance(key, bytes) else key
            for _name, json_data in Store.hgetall(decoded_key).items():
                parsed = json.loads(json_data)
                shards.add(int(parsed.get("shard", 0) or 0))
        return shards

    @classmethod
    def update_topic_offsets(cls):
        Topic.update_topic_offsets([cls.PRIMARY_KEY])

    @classmethod
    def write(cls, type, event):
        event["type"] = type
        msg = {"event": json.dumps(event)}
        # Write to all active shards so every interface microservice can read system events inline
        for shard in cls._active_shards():
            Topic.write_topic(cls.PRIMARY_KEY, msg, "*", 1000, shard=shard)

    @classmethod
    def read(cls):
        for _topic, _msg_id, msg_hash, _redis in Topic.read_topics([cls.PRIMARY_KEY]):
            yield json.loads(msg_hash[b"event"].decode())
