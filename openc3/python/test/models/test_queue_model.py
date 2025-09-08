# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import json
import threading
import unittest
from unittest.mock import Mock, patch
from test.test_helper import mock_redis
from openc3.models.queue_model import QueueModel, QueueError
from openc3.topics.queue_topic import QueueTopic


class TestQueueModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.scope = "DEFAULT"
        self.name = "TEST_QUEUE"
        self.queue_model = QueueModel(name=self.name, scope=self.scope)

    def test_primary_key(self):
        self.assertEqual(QueueModel.PRIMARY_KEY, "openc3__queue")

    def test_initialization(self):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        self.assertEqual(queue.name, "TEST")
        self.assertEqual(queue.scope, "DEFAULT")
        self.assertEqual(queue.microservice_name, "DEFAULT__QUEUE__TEST")

    def test_initialization_with_defaults(self):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        self.assertEqual(queue.state, "HOLD")
        # updated_at is set during create(), not __init__()
        self.assertIsNone(queue.updated_at)

    def test_get_class_method(self):
        with patch("openc3.models.model.Model.get") as mock_get:
            QueueModel.get(name="TEST", scope="DEFAULT")
            mock_get.assert_called_once_with("DEFAULT__openc3__queue", "TEST")

    def test_names_class_method(self):
        with patch("openc3.models.model.Model.names") as mock_names:
            QueueModel.names(scope="DEFAULT")
            mock_names.assert_called_once_with("DEFAULT__openc3__queue")

    def test_all_class_method(self):
        with patch("openc3.models.model.Model.all") as mock_all:
            QueueModel.all(scope="DEFAULT")
            mock_all.assert_called_once_with("DEFAULT__openc3__queue")

    @patch("openc3.models.queue_model.Store")
    @patch("openc3.models.queue_model.QueueModel.get_model")
    def test_queue_command_success(self, mock_get_model, mock_store):
        mock_model = Mock()
        mock_model.state = "RUNNING"
        mock_model.notify = Mock()
        mock_get_model.return_value = mock_model
        mock_store.zrevrange.return_value = []
        mock_store.zadd = Mock()

        with patch("time.time_ns", return_value=1234567890):
            QueueModel.queue_command("TEST", command="CMD", username="user", scope="DEFAULT")

        mock_get_model.assert_called_once_with(name="TEST", scope="DEFAULT")
        mock_store.zrevrange.assert_called_once_with("DEFAULT:TEST", 0, 0, withscores=True)

        expected_data = json.dumps({"username": "user", "value": "CMD", "timestamp": 1234567890})
        mock_store.zadd.assert_called_once_with("DEFAULT:TEST", {expected_data: 1.0})
        mock_model.notify.assert_called_once_with(kind="command")

    @patch("openc3.models.queue_model.Store")
    @patch("openc3.models.queue_model.QueueModel.get_model")
    def test_queue_command_with_existing_items(self, mock_get_model, mock_store):
        mock_model = Mock()
        mock_model.state = "RUNNING"
        mock_model.notify = Mock()
        mock_get_model.return_value = mock_model
        mock_store.zrevrange.return_value = [("data", 5.0)]
        mock_store.zadd = Mock()

        QueueModel.queue_command("TEST", command="CMD", username="user", scope="DEFAULT")

        mock_store.zadd.assert_called_once()
        args = mock_store.zadd.call_args[0]
        self.assertEqual(args[0], "DEFAULT:TEST")
        cmd_data = json.loads(list(args[1].keys())[0])
        self.assertEqual(cmd_data["username"], "user")
        self.assertEqual(cmd_data["value"], "CMD")
        self.assertEqual(list(args[1].values())[0], 6.0)  # index should be 1 more than existing max

    @patch("openc3.models.queue_model.QueueModel.get_model")
    def test_queue_command_queue_not_found(self, mock_get_model):
        mock_get_model.return_value = None

        with self.assertRaises(QueueError) as context:
            QueueModel.queue_command("NONEXISTENT", command="CMD", username="user", scope="DEFAULT")

        self.assertIn("Queue 'NONEXISTENT' not found in scope 'DEFAULT'", str(context.exception))

    @patch("openc3.models.queue_model.QueueModel.get_model")
    def test_queue_command_disabled_queue(self, mock_get_model):
        mock_model = Mock()
        mock_model.state = "DISABLE"
        mock_get_model.return_value = mock_model

        with self.assertRaises(QueueError) as context:
            QueueModel.queue_command("TEST", command="CMD", username="user", scope="DEFAULT")

        self.assertIn("Queue 'TEST' is disabled", str(context.exception))

    def test_as_json(self):
        queue = QueueModel(name="TEST", scope="DEFAULT", state="HOLD")
        queue.updated_at = 1234567890

        result = queue.as_json()

        expected = {"name": "TEST", "scope": "DEFAULT", "state": "HOLD", "updated_at": 1234567890}
        self.assertEqual(result, expected)

    @patch("openc3.topics.queue_topic.QueueTopic.write_notification")
    def test_notify(self, mock_write_notification):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        queue.notify(kind="test")

        mock_write_notification.assert_called_once()
        args = mock_write_notification.call_args
        notification = args[0][0]
        self.assertEqual(notification["kind"], "test")
        self.assertIn("data", notification)
        self.assertEqual(args[1]["scope"], "DEFAULT")

    def test_queue_topic_integration(self):
        self.assertEqual(QueueTopic.PRIMARY_KEY, "openc3_queue")


if __name__ == "__main__":
    unittest.main()
