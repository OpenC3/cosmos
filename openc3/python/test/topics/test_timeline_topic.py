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

import json
import unittest

from openc3.topics.timeline_topic import TimelineTopic
from openc3.utilities.store import EphemeralStore
from test.test_helper import mock_redis


class TestTimelineTopic(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_primary_key_matches_activity_model(self):
        # Documented invariant: TimelineTopic.PRIMARY_KEY must be the same as
        # ActivityModel.PRIMARY_KEY so writes from the model land on the
        # right stream.
        from openc3.models.activity_model import ActivityModel

        self.assertEqual(TimelineTopic.PRIMARY_KEY, ActivityModel.PRIMARY_KEY)

    def test_write_activity_writes_to_scoped_stream(self):
        activity = {
            "timeline": "tl",
            "kind": "created",
            "type": "activity",
            "data": json.dumps({"name": "tl", "start": 1, "stop": 2}),
        }
        TimelineTopic.write_activity(activity, scope="DEFAULT")

        store = EphemeralStore.instance()
        topic_name = f"DEFAULT{TimelineTopic.PRIMARY_KEY}"
        # Returns [(stream_id, fields), ...]
        entries = store.xrange(topic_name, count=10)
        self.assertEqual(len(entries), 1)
        _, fields = entries[0]
        self.assertEqual(fields[b"timeline"], b"tl")
        self.assertEqual(fields[b"kind"], b"created")
        self.assertEqual(fields[b"type"], b"activity")

    def test_write_activity_isolates_scopes(self):
        TimelineTopic.write_activity(
            {"timeline": "alpha", "kind": "created", "type": "activity", "data": "{}"},
            scope="DEFAULT",
        )
        TimelineTopic.write_activity(
            {"timeline": "beta", "kind": "created", "type": "activity", "data": "{}"},
            scope="OTHER",
        )

        store = EphemeralStore.instance()
        default = store.xrange(f"DEFAULT{TimelineTopic.PRIMARY_KEY}", count=10)
        other = store.xrange(f"OTHER{TimelineTopic.PRIMARY_KEY}", count=10)
        self.assertEqual(len(default), 1)
        self.assertEqual(len(other), 1)
        self.assertEqual(default[0][1][b"timeline"], b"alpha")
        self.assertEqual(other[0][1][b"timeline"], b"beta")

    def test_write_activity_appends_in_order(self):
        for i in range(3):
            TimelineTopic.write_activity(
                {
                    "timeline": "tl",
                    "kind": "updated",
                    "type": "activity",
                    "data": json.dumps({"i": i}),
                },
                scope="DEFAULT",
            )

        store = EphemeralStore.instance()
        entries = store.xrange(f"DEFAULT{TimelineTopic.PRIMARY_KEY}", count=10)
        self.assertEqual(len(entries), 3)
        seen = [json.loads(fields[b"data"].decode()) for _, fields in entries]
        self.assertEqual([s["i"] for s in seen], [0, 1, 2])
