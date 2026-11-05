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

import time
import unittest

from openc3.models.activity_model import (
    ActivityError,
    ActivityInputError,
    ActivityModel,
    ActivityOverlapError,
)
from openc3.models.timeline_model import TimelineModel
from test.test_helper import mock_redis


TIMELINE = "tl"
SCOPE = "DEFAULT"


class TestActivityModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        TimelineModel(name=TIMELINE, scope=SCOPE).create()

    def _make(self, offset_minutes=1, duration_minutes=10, kind="COMMAND", data=None):
        if data is None:
            data = {"test": "test"}
        now = int(time.time())
        start = now + (offset_minutes * 60)
        stop = start + (duration_minutes * 60)
        return ActivityModel(
            name=TIMELINE,
            scope=SCOPE,
            start=start,
            stop=stop,
            kind=kind,
            data=data,
        )

    # --- validate_input --------------------------------------------------

    def test_validate_rejects_start_after_stop(self):
        with self.assertRaises(ActivityInputError):
            self._make(offset_minutes=10, duration_minutes=-1).validate_input(
                start=100, stop=50, kind="command", data={}
            )

    def test_validate_rejects_excessive_duration(self):
        model = self._make()
        now = int(time.time())
        with self.assertRaises(ActivityInputError):
            model.validate_input(
                start=now + 60, stop=now + 60 + ActivityModel.MAX_DURATION + 1, kind="command", data={}
            )

    def test_validate_rejects_unknown_kind(self):
        model = self._make()
        now = int(time.time())
        with self.assertRaises(ActivityInputError):
            model.validate_input(start=now + 60, stop=now + 120, kind="banana", data={})

    def test_validate_rejects_non_dict_data(self):
        model = self._make()
        now = int(time.time())
        with self.assertRaises(ActivityInputError):
            model.validate_input(start=now + 60, stop=now + 120, kind="command", data="not-a-dict")

    def test_validate_rejects_past_start(self):
        model = self._make()
        now = int(time.time())
        with self.assertRaises(ActivityInputError):
            model.validate_input(
                start=now - ActivityModel.START_GRACE_SECONDS - 60,
                stop=now,
                kind="command",
                data={},
            )

    def test_validate_allows_past_for_expire_kind(self):
        model = self._make()
        now = int(time.time())
        # Should NOT raise
        model.validate_input(
            start=now - 1000,
            stop=now - 500,
            kind="expire",
            data={},
        )

    # --- create / get / score / count ------------------------------------

    def test_create_persists_an_activity(self):
        a = self._make()
        a.create()
        all_acts = ActivityModel.all(name=TIMELINE, scope=SCOPE)
        self.assertEqual(len(all_acts), 1)
        self.assertEqual(all_acts[0]["start"], a.start)
        self.assertEqual(all_acts[0]["uuid"], a.uuid)

    def test_create_records_a_created_event(self):
        a = self._make()
        a.create(username="alice")
        all_acts = ActivityModel.all(name=TIMELINE, scope=SCOPE)
        events = all_acts[0]["events"]
        self.assertEqual(events[0]["event"], "created")
        self.assertEqual(events[0]["username"], "alice")

    def test_create_requires_an_existing_timeline(self):
        a = ActivityModel(
            name="ghost",
            scope=SCOPE,
            start=int(time.time()) + 60,
            stop=int(time.time()) + 120,
            kind="COMMAND",
            data={"x": 1},
        )
        with self.assertRaises(ActivityError):
            a.create()

    def test_create_with_no_overlap_rejects_collisions(self):
        first = self._make(offset_minutes=1, duration_minutes=30)
        first.create()
        # Same window should collide
        second = self._make(offset_minutes=2, duration_minutes=30)
        with self.assertRaises(ActivityOverlapError):
            second.create(overlap=False)

    def test_score_returns_none_for_missing(self):
        self.assertIsNone(ActivityModel.score(name=TIMELINE, score=0, scope=SCOPE))

    def test_score_returns_a_model(self):
        a = self._make()
        a.create()
        loaded = ActivityModel.score(name=TIMELINE, score=a.start, uuid=a.uuid, scope=SCOPE)
        self.assertIsNotNone(loaded)
        self.assertEqual(loaded.uuid, a.uuid)

    def test_count_reflects_inserts(self):
        self.assertEqual(ActivityModel.count(name=TIMELINE, scope=SCOPE), 0)
        self._make(offset_minutes=1).create()
        self._make(offset_minutes=10).create()
        self.assertEqual(ActivityModel.count(name=TIMELINE, scope=SCOPE), 2)

    def test_get_validates_start_stop_order(self):
        with self.assertRaises(ActivityInputError):
            ActivityModel.get(name=TIMELINE, start=100, stop=50, scope=SCOPE)

    # --- update ----------------------------------------------------------

    def test_update_moves_the_activity(self):
        a = self._make(offset_minutes=1, duration_minutes=10)
        a.create()
        old_start = a.start
        new_start = a.start + 600
        new_stop = new_start + 600
        a.update(start=new_start, stop=new_stop, kind="script", data={"script": "foo.rb"})
        # Original score is gone
        self.assertIsNone(ActivityModel.score(name=TIMELINE, score=old_start, uuid=a.uuid, scope=SCOPE))
        loaded = ActivityModel.score(name=TIMELINE, score=new_start, uuid=a.uuid, scope=SCOPE)
        self.assertEqual(loaded.kind, "script")
        # An "updated" event should have been recorded
        kinds = [e["event"] for e in loaded.events]
        self.assertIn("updated", kinds)

    def test_update_records_changes_in_audit_event(self):
        a = self._make()
        a.create()
        a.update(start=a.start + 600, stop=a.stop + 600, kind="command", data={"new": "data"})
        loaded = ActivityModel.all(name=TIMELINE, scope=SCOPE)[0]
        update_events = [e for e in loaded["events"] if e["event"] == "updated"]
        self.assertTrue(update_events)
        changes = update_events[-1].get("changes", {})
        self.assertIn("start", changes)
        self.assertIn("stop", changes)

    # --- destroy ---------------------------------------------------------

    def test_destroy_returns_zero_when_missing(self):
        result = ActivityModel.destroy(name=TIMELINE, scope=SCOPE, score=0, uuid="no-such")
        self.assertEqual(result, 0)

    def test_destroy_removes_a_specific_activity(self):
        a = self._make()
        a.create()
        result = ActivityModel.destroy(name=TIMELINE, scope=SCOPE, score=a.start, uuid=a.uuid)
        self.assertEqual(result, 1)
        self.assertEqual(ActivityModel.count(name=TIMELINE, scope=SCOPE), 0)

    def test_range_destroy_removes_window(self):
        a1 = self._make(offset_minutes=1, duration_minutes=10)
        a1.create()
        a2 = self._make(offset_minutes=20, duration_minutes=10)
        a2.create()
        # Destroy only the first
        result = ActivityModel.range_destroy(name=TIMELINE, scope=SCOPE, min=a1.start, max=a1.start)
        self.assertEqual(result, 1)
        self.assertEqual(ActivityModel.count(name=TIMELINE, scope=SCOPE), 1)

    # --- recurring -------------------------------------------------------

    def test_recurring_creates_multiple_activities(self):
        now = int(time.time())
        start = now + 60
        stop = start + 1800
        recurring = {"frequency": "1", "span": "days", "end": start + 86400 * 3}
        a = ActivityModel(
            name=TIMELINE,
            scope=SCOPE,
            start=start,
            stop=stop,
            kind="COMMAND",
            data={"x": 1},
            recurring=recurring,
        )
        a.create()
        all_acts = ActivityModel.all(name=TIMELINE, scope=SCOPE)
        self.assertEqual(len(all_acts), 4)
        # Each recurring instance should share the recurring uuid
        recurring_uuids = {act["recurring"]["uuid"] for act in all_acts}
        self.assertEqual(len(recurring_uuids), 1)

    def test_recurring_overlap_raises(self):
        now = int(time.time())
        start = now + 60
        # 90-minute activities recurring every 60 minutes will overlap
        stop = start + 90 * 60
        recurring = {"frequency": "1", "span": "hours", "end": start + 7200}
        a = ActivityModel(
            name=TIMELINE,
            scope=SCOPE,
            start=start,
            stop=stop,
            kind="COMMAND",
            data={"x": 1},
            recurring=recurring,
        )
        with self.assertRaises(ActivityOverlapError):
            a.create()

    # --- commit / events -------------------------------------------------

    def test_commit_appends_event(self):
        a = self._make()
        a.create()
        a.commit(status="completed", message="done")
        loaded = ActivityModel.score(name=TIMELINE, score=a.start, uuid=a.uuid, scope=SCOPE)
        last = loaded.events[-1]
        self.assertEqual(last["event"], "completed")
        self.assertEqual(last["message"], "done")
        self.assertTrue(last.get("commit"))

    # --- as_json / from_json ---------------------------------------------

    def test_as_json_round_trip(self):
        a = self._make(data={"k": "v"})
        a.create()
        j = a.as_json()
        copy = ActivityModel.from_json(j, name=TIMELINE, scope=SCOPE)
        self.assertEqual(copy.start, a.start)
        self.assertEqual(copy.stop, a.stop)
        self.assertEqual(copy.kind, a.kind)
        self.assertEqual(copy.data, a.data)
        self.assertEqual(copy.uuid, a.uuid)

    def test_from_json_raises_on_none(self):
        with self.assertRaises(RuntimeError):
            ActivityModel.from_json(None, name=TIMELINE, scope=SCOPE)
