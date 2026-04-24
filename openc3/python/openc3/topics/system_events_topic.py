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
    def _active_db_shards(cls):
        """Collect all unique target db_shards from TargetModel"""
        db_shards = {0}
        # Iterate all scopes to find all target db_shards
        for key in Store.scan_iter(match="*__openc3_targets", type="hash", count=100):
            decoded_key = key.decode() if isinstance(key, bytes) else key
            for _name, json_data in Store.hgetall(decoded_key).items():
                parsed = json.loads(json_data)
                db_shards.add(int(parsed.get("db_shard", 0) or 0))
        return db_shards

    @classmethod
    def update_topic_offsets(cls):
        Topic.update_topic_offsets([cls.PRIMARY_KEY])

    @classmethod
    def write(cls, type, event):
        event["type"] = type
        msg = {"event": json.dumps(event)}
        # Write to all active db_shards so every interface microservice can read system events inline
        for db_shard in cls._active_db_shards():
            Topic.write_topic(cls.PRIMARY_KEY, msg, "*", 1000, db_shard=db_shard)

    @classmethod
    def read(cls):
        for _topic, _msg_id, msg_hash, _redis in Topic.read_topics([cls.PRIMARY_KEY]):
            yield json.loads(msg_hash[b"event"].decode())
