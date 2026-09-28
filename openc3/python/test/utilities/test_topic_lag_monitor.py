# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import unittest
from unittest.mock import Mock, patch

from openc3.utilities.logger import Logger
from openc3.utilities.topic_lag_monitor import TopicLagMonitor


TOPIC = "DEFAULT__DECOM__{INST}__HEALTH_STATUS"
NOW = 1_000_000.0


def id_for(lag, at=0, seq=0):
    """Build a stream id written lag seconds before NOW + at"""
    return f"{int((NOW + at - lag) * 1000)}-{seq}"


class TestTopicLagMonitor(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {}, clear=False)
        self.env.start()
        for key in list(os.environ):
            if key.startswith("OPENC3_LAG_"):
                del os.environ[key]
        self.store = Mock()
        self.store.xinfo_stream.return_value = {}
        store_patch = patch("openc3.utilities.topic_lag_monitor.EphemeralStore")
        self.ephemeral_store = store_patch.start()
        self.ephemeral_store.instance.return_value = self.store
        shard_patch = patch("openc3.utilities.topic_lag_monitor.Store")
        self.store_class = shard_patch.start()
        self.store_class.db_shard_for_target.return_value = 0
        self.addCleanup(store_patch.stop)
        self.addCleanup(shard_patch.stop)
        self.addCleanup(self.env.stop)
        self.logger = Mock()
        self.metric = Mock()

    def monitor(self):
        return TopicLagMonitor(name="DEFAULT__DECOM__INST_INT", logger=self.logger, metric=self.metric, scope="DEFAULT")

    def rec(self, monitor, lag, at):
        return monitor.record(TOPIC, id_for(lag, at), now=NOW + at)

    def test_sets_gauge_and_returns_lag(self):
        monitor = self.monitor()
        lag = monitor.record(TOPIC, id_for(1.5), metric_name="decom_topic_delta_seconds", help="help", now=NOW)
        self.assertAlmostEqual(lag, 1.5, places=2)
        self.metric.set.assert_called_once()
        kwargs = self.metric.set.call_args.kwargs
        self.assertEqual(kwargs["name"], "decom_topic_delta_seconds")
        self.assertAlmostEqual(kwargs["value"], 1.5, places=2)
        self.assertEqual(kwargs["type"], "gauge")
        self.assertEqual(monitor.state, TopicLagMonitor.OK)

    def test_notifies_on_warning_and_critical(self):
        monitor = self.monitor()
        self.rec(monitor, 6, 0)
        self.assertEqual(monitor.state, TopicLagMonitor.WARN)
        self.logger.warn.assert_called_once()
        self.assertIn("falling behind processing: 6.0s behind", self.logger.warn.call_args.args[0])
        self.assertEqual(self.logger.warn.call_args.kwargs["type"], Logger.NOTIFICATION)
        self.rec(monitor, 7, 1)
        self.logger.warn.assert_called_once()

        self.rec(monitor, 31, 2)
        self.assertEqual(monitor.state, TopicLagMonitor.CRITICAL)
        self.logger.error.assert_called_once()
        self.assertIn("31.0s behind", self.logger.error.call_args.args[0])
        self.assertEqual(self.logger.error.call_args.kwargs["type"], Logger.NOTIFICATION)

    def test_recovers_after_hold_time(self):
        monitor = self.monitor()
        self.rec(monitor, 6, 0)
        self.rec(monitor, 4, 1)  # Below warn but not below warn * CLEAR_RATIO
        self.rec(monitor, 1, 2)  # Below clear threshold, hold starts
        self.rec(monitor, 1, 11)
        self.rec(monitor, 3, 12)  # Bounces back up, hold restarts
        self.rec(monitor, 1, 13)
        self.rec(monitor, 1, 22)
        self.assertEqual(monitor.state, TopicLagMonitor.WARN)
        self.logger.info.assert_not_called()

        self.rec(monitor, 1, 23)
        self.assertEqual(monitor.state, TopicLagMonitor.OK)
        self.logger.info.assert_called_once()
        self.assertIn("has caught up processing (max lag 6.0s)", self.logger.info.call_args.args[0])
        self.assertEqual(self.logger.info.call_args.kwargs["type"], Logger.NOTIFICATION)

    def test_steps_down_from_critical_to_warning_silently(self):
        monitor = self.monitor()
        self.rec(monitor, 40, 0)
        self.rec(monitor, 10, 1)
        self.rec(monitor, 10, 11)
        self.assertEqual(monitor.state, TopicLagMonitor.WARN)
        self.logger.info.assert_not_called()

    def test_rate_limits_repeated_notifications(self):
        monitor = self.monitor()
        self.rec(monitor, 6, 0)
        self.rec(monitor, 6, 100)
        self.rec(monitor, 6, 299)
        self.assertEqual(self.logger.warn.call_count, 1)
        self.rec(monitor, 6, 300)
        self.assertEqual(self.logger.warn.call_count, 2)

    def test_thresholds_from_environment(self):
        os.environ["OPENC3_LAG_WARN_SECONDS"] = "20"
        os.environ["OPENC3_LAG_CRITICAL_SECONDS"] = "60"
        monitor = self.monitor()
        self.rec(monitor, 10, 0)
        self.assertEqual(monitor.state, TopicLagMonitor.OK)
        self.logger.warn.assert_not_called()

    def test_zero_warning_disables_notifications(self):
        os.environ["OPENC3_LAG_WARN_SECONDS"] = "0"
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(100), metric_name="m", help="h", now=NOW)
        self.metric.set.assert_called_once()
        self.logger.warn.assert_not_called()
        self.logger.error.assert_not_called()

    def test_invalid_environment_uses_default(self):
        os.environ["OPENC3_LAG_WARN_SECONDS"] = "abc"
        monitor = self.monitor()
        self.rec(monitor, 6, 0)
        self.logger.warn.assert_called_once()

    def test_no_trim_check_when_not_lagging(self):
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(3), now=NOW)
        monitor.record(TOPIC, id_for(1), now=NOW)
        self.store.xinfo_stream.assert_not_called()

    def test_no_trim_check_for_small_gaps(self):
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(61), now=NOW)
        monitor.record(TOPIC, id_for(60.5), now=NOW)
        self.store.xinfo_stream.assert_not_called()

    def test_alerts_when_data_was_trimmed(self):
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(90), now=NOW)
        # Everything up through 40s ago was trimmed before we read it
        self.store.xinfo_stream.return_value = {"max-deleted-entry-id": id_for(40).encode()}
        monitor.record(TOPIC, id_for(39), now=NOW)
        self.store.xinfo_stream.assert_called_once_with(TOPIC)
        alerts = [c for c in self.logger.error.call_args_list if c.kwargs.get("type") == Logger.ALERT]
        self.assertEqual(len(alerts), 1)
        self.assertIn(f"data was trimmed before it was processed: {TOPIC} (~50.0s)", alerts[0].args[0])

    def test_no_alert_when_deleted_data_was_processed(self):
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(40), now=NOW)
        self.store.xinfo_stream.return_value = {"max-deleted-entry-id": id_for(50)}
        monitor.record(TOPIC, id_for(35), now=NOW)
        self.store.xinfo_stream.assert_called_once()
        alerts = [c for c in self.logger.error.call_args_list if c.kwargs.get("type") == Logger.ALERT]
        self.assertEqual(alerts, [])

    def test_aggregates_and_rate_limits_skipped_alerts(self):
        topic2 = "DEFAULT__DECOM__{INST}__ADCS"
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(90), now=NOW)
        monitor.record(topic2, id_for(90), now=NOW)
        self.store.xinfo_stream.return_value = {"max-deleted-entry-id": id_for(40)}
        monitor.record(TOPIC, id_for(39), now=NOW)
        monitor.record(topic2, id_for(39), now=NOW + 2)
        alerts = [c for c in self.logger.error.call_args_list if c.kwargs.get("type") == Logger.ALERT]
        self.assertEqual(len(alerts), 1)
        self.assertIn(TOPIC, alerts[0].args[0])
        monitor.record(topic2, id_for(38), now=NOW + 301)
        alerts = [c for c in self.logger.error.call_args_list if c.kwargs.get("type") == Logger.ALERT]
        self.assertEqual(len(alerts), 2)
        self.assertIn(topic2, alerts[1].args[0])
        self.assertNotIn(TOPIC, alerts[1].args[0])

    def test_rate_limits_xinfo_per_topic(self):
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(90), now=NOW)
        monitor.record(TOPIC, id_for(80), now=NOW)
        monitor.record(TOPIC, id_for(70), now=NOW + 0.5)
        self.store.xinfo_stream.assert_called_once()

    def test_db_shard_from_target_hashtag(self):
        self.store_class.db_shard_for_target.return_value = 2
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(90), now=NOW)
        monitor.record(TOPIC, id_for(80), now=NOW)
        self.store_class.db_shard_for_target.assert_called_with("INST", scope="DEFAULT")
        self.ephemeral_store.instance.assert_called_with(db_shard=2)

    def test_handles_xinfo_errors(self):
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(90), now=NOW)
        self.store.xinfo_stream.side_effect = RuntimeError("no such key")
        monitor.record(TOPIC, id_for(80), now=NOW)
        self.logger.debug.assert_called_once()
        self.assertIn("unable to check", self.logger.debug.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
