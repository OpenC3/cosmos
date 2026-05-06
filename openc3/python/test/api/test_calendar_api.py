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
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from openc3.api.calendar_api import (
    _cal_to_epoch,
    commit_timeline_activity,
    count_timeline_activities,
    create_timeline,
    create_timeline_activity,
    delete_timeline,
    delete_timeline_activity,
    get_timeline,
    get_timeline_activities,
    get_timeline_activity,
    list_timelines,
    set_timeline_color,
    set_timeline_execute,
    update_timeline_activity,
)
from openc3.models.activity_model import (
    ActivityInputError,
    ActivityModel,
)
from openc3.models.timeline_model import TimelineError, TimelineInputError
from test.test_helper import *


SCOPE = "DEFAULT"
TIMELINE = "cal_test"


class TestCalendarApi(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        # MicroserviceModel.__init__ builds an S3 bucket client; route it
        # through the in-memory BucketMock used by the rest of the test suite.
        BucketMock.get_client().clear()
        patcher = patch("openc3.models.microservice_model.Bucket", BucketMock)
        patcher.start()
        self.addCleanup(patcher.stop)

    def _future_window(self, offset_hours=1, duration_hours=1):
        now = datetime.now(timezone.utc)
        start = now + timedelta(hours=offset_hours)
        stop = now + timedelta(hours=offset_hours + duration_hours)
        return start, stop

    def _make_timeline(self, name=TIMELINE, scope=SCOPE):
        return create_timeline(name, scope=scope)

    # --- list_timelines --------------------------------------------------

    def test_list_timelines_empty(self):
        self.assertEqual(list_timelines(scope=SCOPE), [])

    def test_list_timelines_filters_by_scope(self):
        create_timeline("alpha", scope="DEFAULT")
        create_timeline("beta", scope="DEFAULT")
        create_timeline("alpha", scope="OTHER")
        names = sorted(t["name"] for t in list_timelines(scope="DEFAULT"))
        self.assertEqual(names, ["alpha", "beta"])

    # --- create_timeline -------------------------------------------------

    def test_create_timeline_returns_dict(self):
        result = create_timeline(TIMELINE, scope=SCOPE)
        self.assertEqual(result["name"], TIMELINE)
        self.assertEqual(result["scope"], SCOPE)
        self.assertTrue(result["execute"])
        self.assertRegex(result["color"], r"^#[0-9a-fA-F]{6}$")

    def test_create_timeline_honors_color(self):
        result = create_timeline(TIMELINE, color="#A0B1C2", scope=SCOPE)
        self.assertEqual(result["color"], "#A0B1C2")

    def test_create_timeline_rejects_invalid_color(self):
        with self.assertRaises(TimelineInputError):
            create_timeline(TIMELINE, color="red", scope=SCOPE)

    # --- get_timeline ----------------------------------------------------

    def test_get_timeline_returns_none_when_missing(self):
        self.assertIsNone(get_timeline("missing", scope=SCOPE))

    def test_get_timeline_returns_dict_when_present(self):
        create_timeline(TIMELINE, color="#112233", scope=SCOPE)
        result = get_timeline(TIMELINE, scope=SCOPE)
        self.assertEqual(result["name"], TIMELINE)
        self.assertEqual(result["color"], "#112233")

    # --- set_timeline_color ----------------------------------------------

    def test_set_timeline_color_returns_none_when_missing(self):
        self.assertIsNone(set_timeline_color("missing", "#FF0000", scope=SCOPE))

    def test_set_timeline_color_updates(self):
        create_timeline(TIMELINE, scope=SCOPE)
        result = set_timeline_color(TIMELINE, "#445566", scope=SCOPE)
        self.assertEqual(result["color"], "#445566")
        self.assertEqual(get_timeline(TIMELINE, scope=SCOPE)["color"], "#445566")

    def test_set_timeline_color_rejects_invalid(self):
        create_timeline(TIMELINE, scope=SCOPE)
        with self.assertRaises(TimelineInputError):
            set_timeline_color(TIMELINE, "not-a-color", scope=SCOPE)

    # --- set_timeline_execute --------------------------------------------

    def test_set_timeline_execute_returns_none_when_missing(self):
        self.assertIsNone(set_timeline_execute("missing", False, scope=SCOPE))

    def test_set_timeline_execute_toggles_with_string(self):
        create_timeline(TIMELINE, scope=SCOPE)
        self.assertFalse(set_timeline_execute(TIMELINE, "FALSE", scope=SCOPE)["execute"])
        self.assertTrue(set_timeline_execute(TIMELINE, "true", scope=SCOPE)["execute"])

    # --- delete_timeline -------------------------------------------------

    def test_delete_timeline_returns_none_when_missing(self):
        self.assertIsNone(delete_timeline("missing", scope=SCOPE))

    def test_delete_timeline_empty(self):
        create_timeline(TIMELINE, scope=SCOPE)
        result = delete_timeline(TIMELINE, scope=SCOPE)
        self.assertEqual(result, {"name": TIMELINE})
        self.assertIsNone(get_timeline(TIMELINE, scope=SCOPE))

    def test_delete_timeline_refuses_with_activities(self):
        create_timeline(TIMELINE, scope=SCOPE)
        start, stop = self._future_window()
        create_timeline_activity(TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE)
        with self.assertRaises(TimelineError):
            delete_timeline(TIMELINE, scope=SCOPE)

    def test_delete_timeline_force_clears_activities(self):
        create_timeline(TIMELINE, scope=SCOPE)
        start, stop = self._future_window()
        create_timeline_activity(TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE)
        result = delete_timeline(TIMELINE, force=True, scope=SCOPE)
        self.assertEqual(result, {"name": TIMELINE})

    # --- create_timeline_activity ----------------------------------------

    def test_create_activity_with_datetimes(self):
        self._make_timeline()
        start, stop = self._future_window()
        result = create_timeline_activity(
            TIMELINE, kind="COMMAND", start=start, stop=stop,
            data={"cmd": "INST ABORT"}, scope=SCOPE,
        )
        self.assertEqual(result["kind"], "command")
        self.assertEqual(result["start"], int(start.timestamp()))
        self.assertEqual(result["stop"], int(stop.timestamp()))
        self.assertEqual(result["data"], {"cmd": "INST ABORT"})

    def test_create_activity_with_iso_strings(self):
        self._make_timeline()
        start, stop = self._future_window()
        result = create_timeline_activity(
            TIMELINE, kind="SCRIPT", start=start.isoformat(), stop=stop.isoformat(),
            data={"script": "INST/foo.py"}, scope=SCOPE,
        )
        self.assertEqual(result["kind"], "script")
        self.assertEqual(result["start"], int(start.timestamp()))

    def test_create_activity_with_integer_epoch(self):
        self._make_timeline()
        start, stop = self._future_window()
        result = create_timeline_activity(
            TIMELINE, kind="reserve",
            start=int(start.timestamp()), stop=int(stop.timestamp()),
            scope=SCOPE,
        )
        self.assertEqual(result["kind"], "reserve")

    def test_create_activity_records_username(self):
        self._make_timeline()
        start, stop = self._future_window()
        result = create_timeline_activity(
            TIMELINE, kind="COMMAND", start=start, stop=stop,
            data={"username": "alice"}, scope=SCOPE,
        )
        self.assertEqual(result["events"][0]["username"], "alice")

    def test_create_activity_recurring(self):
        self._make_timeline()
        start = int(time.time()) + 60
        stop = start + 1800
        recurring = {"frequency": "1", "span": "days", "end": start + 86400 * 3}
        create_timeline_activity(
            TIMELINE, kind="COMMAND", start=start, stop=stop,
            data={"cmd": "INST ABORT"}, recurring=recurring, scope=SCOPE,
        )
        all_acts = ActivityModel.all(name=TIMELINE, scope=SCOPE)
        self.assertEqual(len(all_acts), 4)

    def test_create_activity_rejects_past_start(self):
        self._make_timeline()
        now = datetime.now(timezone.utc)
        with self.assertRaises(ActivityInputError):
            create_timeline_activity(
                TIMELINE, kind="COMMAND",
                start=now - timedelta(hours=1), stop=now,
                scope=SCOPE,
            )

    def test_create_activity_rejects_too_long(self):
        self._make_timeline()
        now = datetime.now(timezone.utc)
        with self.assertRaises(ActivityInputError):
            create_timeline_activity(
                TIMELINE, kind="COMMAND",
                start=now + timedelta(hours=1), stop=now + timedelta(days=2),
                scope=SCOPE,
            )

    # --- update_timeline_activity ----------------------------------------

    def test_update_returns_none_when_missing(self):
        self._make_timeline()
        result = update_timeline_activity(
            TIMELINE, id=0, kind="COMMAND", start=0, stop=0,
            uuid="no-such", scope=SCOPE,
        )
        self.assertIsNone(result)

    def test_update_changes_kind_and_window(self):
        self._make_timeline()
        start, stop = self._future_window(offset_hours=1)
        created = create_timeline_activity(
            TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE,
        )
        new_start, new_stop = self._future_window(offset_hours=4)
        updated = update_timeline_activity(
            TIMELINE,
            id=created["start"],
            kind="SCRIPT",
            start=new_start, stop=new_stop,
            uuid=created["uuid"],
            data={"script": "foo.py"},
            scope=SCOPE,
        )
        self.assertEqual(updated["kind"], "script")
        self.assertEqual(updated["start"], int(new_start.timestamp()))

    # --- get_timeline_activity -------------------------------------------

    def test_get_activity_returns_none_when_missing(self):
        self._make_timeline()
        self.assertIsNone(get_timeline_activity(TIMELINE, 0, "no-such", scope=SCOPE))

    def test_get_activity_returns_dict(self):
        self._make_timeline()
        start, stop = self._future_window()
        created = create_timeline_activity(
            TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE,
        )
        result = get_timeline_activity(TIMELINE, created["start"], created["uuid"], scope=SCOPE)
        self.assertEqual(result["uuid"], created["uuid"])

    # --- get_timeline_activities -----------------------------------------

    def test_get_activities_empty(self):
        self._make_timeline()
        self.assertEqual(get_timeline_activities(TIMELINE, scope=SCOPE), [])

    def test_get_activities_default_window(self):
        self._make_timeline()
        start, stop = self._future_window()
        create_timeline_activity(TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE)
        result = get_timeline_activities(TIMELINE, scope=SCOPE)
        self.assertEqual(len(result), 1)

    def test_get_activities_excludes_outside_window(self):
        self._make_timeline()
        start, stop = self._future_window()
        create_timeline_activity(TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE)
        far = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
        far_stop = (datetime.now(timezone.utc) + timedelta(days=31)).isoformat()
        self.assertEqual(
            get_timeline_activities(TIMELINE, start=far, stop=far_stop, scope=SCOPE), []
        )

    # --- delete_timeline_activity ----------------------------------------

    def test_delete_activity_returns_zero_when_missing(self):
        self._make_timeline()
        ret = delete_timeline_activity(TIMELINE, 0, "no-such", scope=SCOPE)
        self.assertEqual(ret, 0)

    def test_delete_activity_removes(self):
        self._make_timeline()
        start, stop = self._future_window()
        created = create_timeline_activity(
            TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE,
        )
        ret = delete_timeline_activity(TIMELINE, created["start"], created["uuid"], scope=SCOPE)
        self.assertEqual(ret, 1)
        self.assertEqual(count_timeline_activities(TIMELINE, scope=SCOPE), 0)

    # --- count_timeline_activities ---------------------------------------

    def test_count_activities_starts_at_zero(self):
        self._make_timeline()
        self.assertEqual(count_timeline_activities(TIMELINE, scope=SCOPE), 0)

    def test_count_activities_increments(self):
        self._make_timeline()
        s1, p1 = self._future_window(offset_hours=1)
        create_timeline_activity(TIMELINE, kind="COMMAND", start=s1, stop=p1, scope=SCOPE)
        s2, p2 = self._future_window(offset_hours=4)
        create_timeline_activity(TIMELINE, kind="COMMAND", start=s2, stop=p2, scope=SCOPE)
        self.assertEqual(count_timeline_activities(TIMELINE, scope=SCOPE), 2)

    # --- commit_timeline_activity ----------------------------------------

    def test_commit_returns_none_when_missing(self):
        self._make_timeline()
        self.assertIsNone(
            commit_timeline_activity(TIMELINE, 0, "no-such", status="done", scope=SCOPE)
        )

    def test_commit_appends_event(self):
        self._make_timeline()
        start, stop = self._future_window()
        created = create_timeline_activity(
            TIMELINE, kind="COMMAND", start=start, stop=stop, scope=SCOPE,
        )
        result = commit_timeline_activity(
            TIMELINE, created["start"], created["uuid"],
            status="completed", message="finished", scope=SCOPE,
        )
        self.assertEqual(len(result["events"]), 2)
        last = result["events"][-1]
        self.assertEqual(last["event"], "completed")
        self.assertEqual(last["message"], "finished")

    # --- _cal_to_epoch ---------------------------------------------------

    def test_cal_to_epoch_int(self):
        self.assertEqual(_cal_to_epoch(12345), 12345)

    def test_cal_to_epoch_float(self):
        self.assertEqual(_cal_to_epoch(12345.9), 12345)

    def test_cal_to_epoch_bool(self):
        # bool is a subclass of int — should coerce, not pass through unchanged
        self.assertEqual(_cal_to_epoch(True), 1)
        self.assertEqual(_cal_to_epoch(False), 0)

    def test_cal_to_epoch_numeric_string(self):
        self.assertEqual(_cal_to_epoch("12345"), 12345)
        self.assertEqual(_cal_to_epoch("-7"), -7)

    def test_cal_to_epoch_iso_string(self):
        dt = datetime(2031, 4, 16, 1, 2, 3, tzinfo=timezone.utc)
        self.assertEqual(_cal_to_epoch(dt.isoformat()), int(dt.timestamp()))

    def test_cal_to_epoch_iso_string_with_z(self):
        dt = datetime(2031, 4, 16, 1, 2, 3, tzinfo=timezone.utc)
        self.assertEqual(_cal_to_epoch("2031-04-16T01:02:03Z"), int(dt.timestamp()))

    def test_cal_to_epoch_datetime_naive_treated_as_utc(self):
        dt = datetime(2031, 4, 16, 1, 2, 3)
        expected = int(dt.replace(tzinfo=timezone.utc).timestamp())
        self.assertEqual(_cal_to_epoch(dt), expected)

    def test_cal_to_epoch_datetime_with_tz(self):
        dt = datetime(2031, 4, 16, 1, 2, 3, tzinfo=timezone.utc)
        self.assertEqual(_cal_to_epoch(dt), int(dt.timestamp()))

    def test_cal_to_epoch_invalid_string_raises(self):
        with self.assertRaises(ValueError):
            _cal_to_epoch("not-a-date")
