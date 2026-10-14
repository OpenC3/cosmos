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
OTHER_TOPIC = "DEFAULT__DECOM__{INST}__ADCS"
NOW = 1_000_000.0  # Start of a gauge window


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
        self.addCleanup(self.env.stop)
        self.logger = Mock()
        self.metric = Mock()

    def monitor(self):
        return TopicLagMonitor(name="DEFAULT__DECOM__INST_INT", logger=self.logger, metric=self.metric)

    def rec(self, monitor, lag, at, topic=TOPIC):
        return monitor.record(topic, id_for(lag, at), now=NOW + at)

    def rec_gauge(self, monitor, lag, at):
        """Record a message with the gauge metric enabled"""
        return monitor.record(TOPIC, id_for(lag, at), metric_name="m", help="h", now=NOW + at)

    def gauge_values(self):
        return [call.kwargs["value"] for call in self.metric.set.call_args_list]

    def warn_and_recover(self, monitor):
        """Warn at 0 and recover at 11"""
        self.rec(monitor, 6, 0)
        self.rec(monitor, 1, 1)
        self.rec(monitor, 1, 11)
        self.assertEqual(monitor.state, TopicLagMonitor.OK)

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
        self.assertIn(f"has caught up processing (max lag 6.0s on {TOPIC})", self.logger.info.call_args.args[0])
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
        with patch.dict(os.environ, {"OPENC3_LAG_WARN_SECONDS": "20", "OPENC3_LAG_CRITICAL_SECONDS": "60"}):
            monitor = self.monitor()
        self.rec(monitor, 10, 0)
        self.assertEqual(monitor.state, TopicLagMonitor.OK)
        self.logger.warn.assert_not_called()

    def test_zero_warning_disables_notifications(self):
        with patch.dict(os.environ, {"OPENC3_LAG_WARN_SECONDS": "0"}):
            monitor = self.monitor()
        monitor.record(TOPIC, id_for(100), metric_name="m", help="h", now=NOW)
        self.metric.set.assert_called_once()
        self.logger.warn.assert_not_called()
        self.logger.error.assert_not_called()

    def test_invalid_environment_uses_default(self):
        with patch.dict(os.environ, {"OPENC3_LAG_WARN_SECONDS": "abc"}):
            monitor = self.monitor()
        self.rec(monitor, 6, 0)
        self.logger.warn.assert_called_once()

    def test_names_lagging_topic_and_max_lag_topic(self):
        monitor = self.monitor()
        self.rec(monitor, 6, 0)
        self.assertEqual(
            self.logger.warn.call_args.args[0],
            f"DEFAULT__DECOM__INST_INT is falling behind processing: 6.0s behind on {TOPIC} (max 6.0s on {TOPIC})",
        )
        self.rec(monitor, 31, 1, OTHER_TOPIC)
        self.assertEqual(
            self.logger.error.call_args.args[0],
            f"DEFAULT__DECOM__INST_INT is falling behind processing: 31.0s behind on {OTHER_TOPIC} "
            f"(max 31.0s on {OTHER_TOPIC})",
        )
        self.rec(monitor, 1, 2)
        self.rec(monitor, 1, 12)
        self.assertEqual(monitor.state, TopicLagMonitor.OK)
        self.assertEqual(
            self.logger.info.call_args.args[0],
            f"DEFAULT__DECOM__INST_INT has caught up processing (max lag 31.0s on {OTHER_TOPIC})",
        )

    def test_no_renotify_or_recovery_within_renotify_interval(self):
        monitor = self.monitor()
        self.warn_and_recover(monitor)
        self.rec(monitor, 6, 20)
        self.assertEqual(monitor.state, TopicLagMonitor.WARN)
        self.rec(monitor, 1, 21)
        self.rec(monitor, 1, 31)
        self.assertEqual(monitor.state, TopicLagMonitor.OK)
        self.assertEqual(self.logger.warn.call_count, 1)
        self.assertEqual(self.logger.info.call_count, 1)

    def test_notifies_again_after_renotify_interval(self):
        monitor = self.monitor()
        self.warn_and_recover(monitor)
        self.rec(monitor, 6, 300)
        self.assertEqual(self.logger.warn.call_count, 2)

    def test_renotifies_continued_episode_after_renotify_interval(self):
        monitor = self.monitor()
        self.warn_and_recover(monitor)
        self.rec(monitor, 6, 20)
        self.rec(monitor, 6, 300)
        self.rec(monitor, 1, 301)
        self.rec(monitor, 1, 311)
        self.assertEqual(self.logger.warn.call_count, 2)
        self.assertEqual(self.logger.info.call_count, 2)

    def test_always_notifies_escalation_past_last_notified_level(self):
        monitor = self.monitor()
        self.warn_and_recover(monitor)
        self.rec(monitor, 31, 20)
        self.assertEqual(monitor.state, TopicLagMonitor.CRITICAL)
        self.logger.error.assert_called_once()
        self.assertIn("31.0s behind", self.logger.error.call_args.args[0])

    def test_gauge_reports_max_lag_within_window(self):
        monitor = self.monitor()
        self.rec_gauge(monitor, 3, 0)
        self.rec_gauge(monitor, 1, 1)  # Lower lag doesn't change the reported max
        self.rec_gauge(monitor, 4, 2)
        self.assertEqual([round(v, 2) for v in self.gauge_values()], [3, 4])

    def test_gauge_holds_previous_window_max(self):
        monitor = self.monitor()
        self.rec_gauge(monitor, 4, 0)
        self.rec_gauge(monitor, 1, 5)
        self.rec_gauge(monitor, 1, 10)
        self.assertEqual([round(v, 2) for v in self.gauge_values()], [4, 4, 1])

    def test_gauge_does_not_hold_max_across_idle_window(self):
        monitor = self.monitor()
        self.rec_gauge(monitor, 4, 0)
        self.rec_gauge(monitor, 1, 12)
        self.assertEqual([round(v, 2) for v in self.gauge_values()], [4, 1])

    def test_gauge_tracks_each_metric_name_separately(self):
        monitor = self.monitor()
        monitor.record(TOPIC, id_for(4), metric_name="a", help="h", now=NOW)
        monitor.record(TOPIC, id_for(1), metric_name="b", help="h", now=NOW)
        self.assertEqual(self.metric.set.call_args.kwargs["name"], "b")
        self.assertAlmostEqual(self.metric.set.call_args.kwargs["value"], 1, places=2)


if __name__ == "__main__":
    unittest.main()
