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
import time
import threading
import unittest
from unittest.mock import Mock, patch, MagicMock

from test.test_helper import *

from openc3.models.queue_model import QueueModel, QueueError
from openc3.topics.queue_topic import QueueTopic
from openc3.models.microservice_model import MicroserviceModel
from openc3.utilities.store import Store


class TestQueueModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        self.scope = "DEFAULT"
        self.name = "TEST_QUEUE"
        self.queue_model = QueueModel(name=self.name, scope=self.scope)

    def test_primary_key(self):
        self.assertEqual(QueueModel.PRIMARY_KEY, 'openc3__queue')

    def test_initialization(self):
        queue = QueueModel(name="TEST", scope="DEFAULT", state="RUNNING")
        self.assertEqual(queue.name, "TEST")
        self.assertEqual(queue.scope, "DEFAULT")
        self.assertEqual(queue.state, "RUNNING")
        self.assertEqual(queue.microservice_name, "DEFAULT__QUEUE__TEST")
        self.assertIsInstance(queue._instance_mutex, type(threading.Lock()))

    def test_initialization_with_defaults(self):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        self.assertEqual(queue.state, "HOLD")
        # updated_at is set during create(), not __init__()
        self.assertIsNone(queue.updated_at)

    def test_get_class_method(self):
        with patch('openc3.models.model.Model.get') as mock_get:
            QueueModel.get(name="TEST", scope="DEFAULT")
            mock_get.assert_called_once_with("DEFAULT__openc3__queue", "TEST")

    def test_names_class_method(self):
        with patch('openc3.models.model.Model.names') as mock_names:
            QueueModel.names(scope="DEFAULT")
            mock_names.assert_called_once_with("DEFAULT__openc3__queue")

    def test_all_class_method(self):
        with patch('openc3.models.model.Model.all') as mock_all:
            QueueModel.all(scope="DEFAULT")
            mock_all.assert_called_once_with("DEFAULT__openc3__queue")

    @patch('openc3.models.queue_model.Store')
    @patch('openc3.models.queue_model.QueueModel.get_model')
    def test_queue_command_success(self, mock_get_model, mock_store):
        mock_model = Mock()
        mock_model.state = 'RUNNING'
        mock_model.notify = Mock()
        mock_get_model.return_value = mock_model
        mock_store.zrevrange.return_value = []
        mock_store.zadd = Mock()

        with patch('time.time_ns', return_value=1234567890):
            QueueModel.queue_command("TEST", command="CMD", username="user", scope="DEFAULT")

        mock_get_model.assert_called_once_with(name="TEST", scope="DEFAULT")
        mock_store.zrevrange.assert_called_once_with("DEFAULT:TEST", 0, 0, with_scores=True)

        expected_data = json.dumps({
            'username': 'user',
            'value': 'CMD',
            'timestamp': 1234567890
        })
        mock_store.zadd.assert_called_once_with("DEFAULT:TEST", 1.0, expected_data)
        mock_model.notify.assert_called_once_with(kind='command')

    @patch('openc3.models.queue_model.Store')
    @patch('openc3.models.queue_model.QueueModel.get_model')
    def test_queue_command_with_existing_items(self, mock_get_model, mock_store):
        mock_model = Mock()
        mock_model.state = 'RUNNING'
        mock_model.notify = Mock()
        mock_get_model.return_value = mock_model
        mock_store.zrevrange.return_value = [('data', 5.0)]
        mock_store.zadd = Mock()

        QueueModel.queue_command("TEST", command="CMD", username="user", scope="DEFAULT")

        mock_store.zadd.assert_called_once()
        args = mock_store.zadd.call_args[0]
        self.assertEqual(args[0], "DEFAULT:TEST")
        self.assertEqual(args[1], 6.0)  # 5.0 + 1

    @patch('openc3.models.queue_model.QueueModel.get_model')
    def test_queue_command_queue_not_found(self, mock_get_model):
        mock_get_model.return_value = None

        with self.assertRaises(QueueError) as context:
            QueueModel.queue_command("NONEXISTENT", command="CMD", username="user", scope="DEFAULT")

        self.assertIn("Queue 'NONEXISTENT' not found in scope 'DEFAULT'", str(context.exception))

    @patch('openc3.models.queue_model.QueueModel.get_model')
    def test_queue_command_disabled_queue(self, mock_get_model):
        mock_model = Mock()
        mock_model.state = 'DISABLE'
        mock_get_model.return_value = mock_model

        with self.assertRaises(QueueError) as context:
            QueueModel.queue_command("TEST", command="CMD", username="user", scope="DEFAULT")

        self.assertIn("Queue 'TEST' is disabled", str(context.exception))

    @patch('openc3.topics.queue_topic.QueueTopic.write_notification')
    def test_create_with_notifications(self, mock_write_notification):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        queue.create()

        mock_write_notification.assert_called_once()
        args = mock_write_notification.call_args
        notification = args[0][0]
        self.assertEqual(notification['kind'], 'created')
        self.assertEqual(args[1]['scope'], 'DEFAULT')

    @patch('openc3.topics.queue_topic.QueueTopic.write_notification')
    @patch('openc3.models.model.Model.create')
    def test_create_update_with_notifications(self, mock_super_create, mock_write_notification):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        queue.create(update=True)

        mock_super_create.assert_called_once_with(update=True, force=False, queued=False)
        mock_write_notification.assert_called_once()
        args = mock_write_notification.call_args
        notification = args[0][0]
        self.assertEqual(notification['kind'], 'updated')

    def test_as_json(self):
        queue = QueueModel(name="TEST", scope="DEFAULT", state="RUNNING")
        queue.updated_at = 1234567890

        result = queue.as_json()

        expected = {
            'name': 'TEST',
            'scope': 'DEFAULT',
            'state': 'RUNNING',
            'updated_at': 1234567890
        }
        self.assertEqual(result, expected)

    @patch('openc3.topics.queue_topic.QueueTopic.write_notification')
    def test_notify(self, mock_write_notification):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        queue.notify(kind='test')

        mock_write_notification.assert_called_once()
        args = mock_write_notification.call_args
        notification = args[0][0]
        self.assertEqual(notification['kind'], 'test')
        self.assertIn('data', notification)
        self.assertEqual(args[1]['scope'], 'DEFAULT')

    @patch('openc3.models.queue_model.Store')
    def test_insert_without_index(self, mock_store):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_store.zrevrange.return_value = []
        mock_store.zadd = Mock()

        with patch.object(queue, 'notify') as mock_notify:
            queue.insert(None, {'test': 'data'})

        mock_store.zrevrange.assert_called_once_with("DEFAULT:TEST", 0, 0, with_scores=True)
        mock_store.zadd.assert_called_once_with("DEFAULT:TEST", 1.0, '{"test": "data"}')
        mock_notify.assert_called_once_with(kind='command')

    @patch('openc3.models.queue_model.Store')
    def test_insert_with_index(self, mock_store):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_store.zadd = Mock()

        with patch.object(queue, 'notify') as mock_notify:
            queue.insert(5.0, {'test': 'data'})

        mock_store.zadd.assert_called_once_with("DEFAULT:TEST", 5.0, '{"test": "data"}')
        mock_notify.assert_called_once_with(kind='command')

    @patch('openc3.models.queue_model.Store')
    def test_remove_success(self, mock_store):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_store.zremrangebyscore.return_value = 1

        with patch.object(queue, 'notify') as mock_notify:
            result = queue.remove(5.0)

        self.assertTrue(result)
        mock_store.zremrangebyscore.assert_called_once_with("DEFAULT:TEST", 5.0, 5.0)
        mock_notify.assert_called_once_with(kind='command')

    @patch('openc3.models.queue_model.Store')
    def test_remove_failure(self, mock_store):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_store.zremrangebyscore.return_value = 0

        with patch.object(queue, 'notify') as mock_notify:
            result = queue.remove(5.0)

        self.assertFalse(result)
        mock_notify.assert_called_once_with(kind='command')

    @patch('openc3.models.queue_model.Store')
    def test_list_empty(self, mock_store):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_store.zrange.return_value = []

        result = queue.list()

        self.assertEqual(result, [])
        mock_store.zrange.assert_called_once_with("DEFAULT:TEST", 0, -1, with_scores=True)

    @patch('openc3.models.queue_model.Store')
    def test_list_with_items(self, mock_store):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_data = [
            ('{"username": "user1", "value": "cmd1"}', 1.0),
            ('{"username": "user2", "value": "cmd2"}', 2.0)
        ]
        mock_store.zrange.return_value = mock_data

        result = queue.list()

        expected = [
            {'username': 'user1', 'value': 'cmd1', 'index': 1.0},
            {'username': 'user2', 'value': 'cmd2', 'index': 2.0}
        ]
        self.assertEqual(result, expected)

    @patch('openc3.models.queue_model.MicroserviceModel')
    def test_create_microservice(self, mock_microservice_model):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_microservice = Mock()
        mock_microservice_model.return_value = mock_microservice

        queue.create_microservice(['topic1', 'topic2'])

        mock_microservice_model.assert_called_once()
        call_args = mock_microservice_model.call_args[1]
        self.assertEqual(call_args['name'], 'DEFAULT__QUEUE__TEST')
        self.assertEqual(call_args['cmd'], ['ruby', 'queue_microservice.rb', 'DEFAULT__QUEUE__TEST'])
        self.assertEqual(call_args['topics'], ['topic1', 'topic2'])
        self.assertEqual(call_args['scope'], 'DEFAULT')
        mock_microservice.create.assert_called_once()

    @patch('openc3.models.microservice_model.MicroserviceModel.get_model')
    def test_deploy_creates_microservice(self, mock_get_model):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_get_model.return_value = None  # Microservice doesn't exist

        with patch.object(queue, 'create_microservice') as mock_create:
            queue.deploy(None, None)

        expected_topics = ['DEFAULT__openc3_queue']
        mock_create.assert_called_once_with(topics=expected_topics)

    @patch('openc3.models.microservice_model.MicroserviceModel.get_model')
    def test_deploy_skips_existing_microservice(self, mock_get_model):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_get_model.return_value = Mock()  # Microservice exists

        with patch.object(queue, 'create_microservice') as mock_create:
            queue.deploy(None, None)

        mock_create.assert_not_called()

    @patch('openc3.models.microservice_model.MicroserviceModel.get_model')
    @patch('openc3.topics.queue_topic.QueueTopic.write_notification')
    @patch('time.time_ns')
    def test_undeploy_with_microservice(self, mock_time_ns, mock_write_notification, mock_get_model):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_microservice = Mock()
        mock_get_model.return_value = mock_microservice
        mock_time_ns.return_value = 1234567890

        queue.undeploy()

        mock_write_notification.assert_called_once()
        args = mock_write_notification.call_args
        notification = args[0][0]
        self.assertEqual(notification['kind'], 'undeployed')
        data = json.loads(notification['data'])
        self.assertEqual(data['name'], 'DEFAULT__QUEUE__TEST')
        self.assertEqual(data['updated_at'], 1234567890)
        mock_microservice.destroy.assert_called_once()

    @patch('openc3.models.microservice_model.MicroserviceModel.get_model')
    def test_undeploy_without_microservice(self, mock_get_model):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_get_model.return_value = None

        with patch('openc3.topics.queue_topic.QueueTopic.write_notification') as mock_write:
            queue.undeploy()

        mock_write.assert_not_called()

    @patch('openc3.models.queue_model.Store')
    def test_destroy(self, mock_store):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        mock_store.zremrangebyrank = Mock()

        with patch.object(queue, 'undeploy') as mock_undeploy:
            with patch('openc3.models.model.Model.destroy') as mock_super_destroy:
                queue.destroy()

        mock_store.zremrangebyrank.assert_called_once_with("DEFAULT:TEST", 0, -1)
        mock_super_destroy.assert_called_once()

    def test_threading_safety(self):
        queue = QueueModel(name="TEST", scope="DEFAULT")
        self.assertIsInstance(QueueModel._class_mutex, type(threading.Lock()))
        self.assertIsInstance(queue._instance_mutex, type(threading.Lock()))

    def test_queue_topic_integration(self):
        self.assertEqual(QueueTopic.PRIMARY_KEY, 'openc3_queue')


if __name__ == '__main__':
    unittest.main()