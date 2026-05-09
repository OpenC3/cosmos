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
from unittest.mock import patch

from openc3.models.activity_model import ActivityModel
from openc3.models.timeline_model import TimelineError, TimelineInputError, TimelineModel
from test.test_helper import BucketMock, mock_redis


class TestTimelineModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def _activity(self, name, scope, offset_minutes=1):
        now = int(time.time())
        start = now + (offset_minutes * 60)
        stop = start + 600
        return ActivityModel(
            name=name,
            scope=scope,
            start=start,
            stop=stop,
            kind="COMMAND",
            data={"test": "test"},
        )

    # --- Construction & validation ---------------------------------------

    def test_init_requires_name_and_scope(self):
        with self.assertRaises(TimelineInputError):
            TimelineModel(name=None, scope="DEFAULT")
        with self.assertRaises(TimelineInputError):
            TimelineModel(name="foo", scope=None)

    def test_init_assigns_random_color_when_none(self):
        model = TimelineModel(name="foo", scope="DEFAULT")
        self.assertRegex(model.color, r"^#[0-9a-fA-F]{6}$")

    def test_init_accepts_valid_color(self):
        model = TimelineModel(name="foo", scope="DEFAULT", color="#A1B2C3")
        self.assertEqual(model.color, "#A1B2C3")

    def test_init_prepends_hash_if_missing(self):
        model = TimelineModel(name="foo", scope="DEFAULT", color="A1B2C3")
        self.assertEqual(model.color, "#A1B2C3")

    def test_init_rejects_invalid_color(self):
        with self.assertRaises(TimelineInputError):
            TimelineModel(name="foo", scope="DEFAULT", color="red")

    def test_execute_setter_handles_string_truthiness(self):
        model = TimelineModel(name="foo", scope="DEFAULT")
        model.execute = "FALSE"
        self.assertFalse(model.execute)
        model.execute = "true"
        self.assertTrue(model.execute)

    # --- Lookups ---------------------------------------------------------

    def test_get_returns_none_when_missing(self):
        self.assertIsNone(TimelineModel.get(name="missing", scope="DEFAULT"))

    def test_get_returns_a_model(self):
        TimelineModel(name="foo", scope="DEFAULT").create()
        loaded = TimelineModel.get(name="foo", scope="DEFAULT")
        self.assertIsNotNone(loaded)
        self.assertEqual(loaded.timeline_name, "foo")
        self.assertEqual(loaded.scope, "DEFAULT")

    def test_all_returns_keys_for_every_scope(self):
        TimelineModel(name="foo", scope="DEFAULT").create()
        TimelineModel(name="bar", scope="OTHER").create()
        all_models = TimelineModel.all()
        self.assertIn("DEFAULT__TIMELINE__foo", all_models)
        self.assertIn("OTHER__TIMELINE__bar", all_models)

    def test_names_returns_all_keys(self):
        TimelineModel(name="foo", scope="DEFAULT").create()
        TimelineModel(name="bar", scope="OTHER").create()
        names = TimelineModel.names()
        self.assertIn("DEFAULT__TIMELINE__foo", names)
        self.assertIn("OTHER__TIMELINE__bar", names)

    # --- Delete ----------------------------------------------------------

    def test_delete_empty_timeline(self):
        TimelineModel(name="foo", scope="DEFAULT").create()
        ret = TimelineModel.delete(name="foo", scope="DEFAULT")
        self.assertEqual(ret, "foo")
        self.assertIsNone(TimelineModel.get(name="foo", scope="DEFAULT"))

    def test_delete_refuses_when_activities_present_and_not_forced(self):
        TimelineModel(name="foo", scope="DEFAULT").create()
        self._activity("foo", "DEFAULT").create()
        with self.assertRaises(TimelineError):
            TimelineModel.delete(name="foo", scope="DEFAULT")

    def test_delete_force_removes_activities(self):
        TimelineModel(name="foo", scope="DEFAULT").create()
        self._activity("foo", "DEFAULT").create()
        ret = TimelineModel.delete(name="foo", scope="DEFAULT", force=True)
        self.assertEqual(ret, "foo")

    # --- Serialization ---------------------------------------------------

    def test_as_json_round_trip_via_from_json(self):
        TimelineModel(name="foo", scope="DEFAULT", color="#FF00FF").create()
        loaded = TimelineModel.get(name="foo", scope="DEFAULT")
        as_json = loaded.as_json()
        self.assertEqual(as_json["name"], "foo")
        self.assertEqual(as_json["scope"], "DEFAULT")
        self.assertEqual(as_json["color"], "#FF00FF")
        self.assertTrue(as_json["execute"])
        self.assertEqual(as_json["shard"], 0)

    def test_from_json_uses_caller_supplied_name_and_scope(self):
        # Even if json carries different name/scope, caller args win.
        json_data = {
            "name": "bogus",
            "scope": "BOGUS",
            "color": "#001122",
            "execute": True,
            "shard": 0,
            "updated_at": None,
        }
        model = TimelineModel.from_json(json_data, name="real", scope="REAL")
        self.assertEqual(model.timeline_name, "real")
        self.assertEqual(model.scope, "REAL")

    def test_from_json_raises_on_none(self):
        with self.assertRaises(RuntimeError):
            TimelineModel.from_json(None, name="x", scope="x")

    # --- Notify / deploy / undeploy --------------------------------------

    def test_notify_writes_to_topic(self):
        from openc3.topics.timeline_topic import TimelineTopic

        TimelineModel(name="foo", scope="DEFAULT").create()
        loaded = TimelineModel.get(name="foo", scope="DEFAULT")
        with patch.object(TimelineTopic, "write_activity") as mock_write:
            loaded.notify(kind="updated")
            mock_write.assert_called_once()
            payload, kwargs = mock_write.call_args[0][0], mock_write.call_args[1]
            self.assertEqual(payload["kind"], "updated")
            self.assertEqual(payload["type"], "timeline")
            self.assertEqual(payload["timeline"], "foo")
            self.assertEqual(kwargs["scope"], "DEFAULT")

    def test_notify_wraps_underlying_failure(self):
        from openc3.topics.timeline_topic import TimelineTopic

        model = TimelineModel(name="foo", scope="DEFAULT")
        model.create()
        with (
            patch.object(TimelineTopic, "write_activity", side_effect=RuntimeError("boom")),
            self.assertRaises(TimelineInputError),
        ):
            model.notify(kind="updated")

    def test_deploy_creates_a_microservice(self):
        from openc3.models.microservice_model import MicroserviceModel

        with patch("openc3.models.microservice_model.Bucket", BucketMock):
            BucketMock.get_client().clear()
            model = TimelineModel(name="foo", scope="DEFAULT")
            model.create()
            model.deploy()
            ms = MicroserviceModel.get(name="DEFAULT__TIMELINE__foo", scope="DEFAULT")
            self.assertIsNotNone(ms)
            self.assertEqual(ms["topics"], ["DEFAULT__openc3_timelines"])
            self.assertEqual(ms["cmd"], ["ruby", "timeline_microservice.rb", "DEFAULT__TIMELINE__foo"])

    def test_undeploy_removes_microservice(self):
        from openc3.models.microservice_model import MicroserviceModel

        with patch("openc3.models.microservice_model.Bucket", BucketMock):
            BucketMock.get_client().clear()
            model = TimelineModel(name="foo", scope="DEFAULT")
            model.create()
            model.deploy()
            self.assertIsNotNone(MicroserviceModel.get(name="DEFAULT__TIMELINE__foo", scope="DEFAULT"))
            model.undeploy()
            self.assertIsNone(MicroserviceModel.get(name="DEFAULT__TIMELINE__foo", scope="DEFAULT"))

    def test_undeploy_is_noop_when_no_microservice(self):
        # No deploy() was called — undeploy should silently do nothing
        # (notify is only fired when an existing microservice was found).
        model = TimelineModel(name="foo", scope="DEFAULT")
        model.create()
        with patch.object(TimelineModel, "notify") as mock_notify:
            model.undeploy()
            mock_notify.assert_not_called()
