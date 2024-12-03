# Copyright 2024 OpenC3, Inc.
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

import unittest
from unittest.mock import patch, Mock, ANY
from test.test_helper import mock_redis, setup_system
from openc3.interfaces.mqtt_stream_interface import MqttStreamInterface
from openc3.system.system import System


class TestMqttStreamInterface(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_sets_all_the_instance_variables(self):
        i = MqttStreamInterface("localhost", "1883", False, "write_topic", "read_topic")
        self.assertEqual(i.name, "MqttStreamInterface")
        self.assertEqual(i.hostname, "localhost")
        self.assertEqual(i.ssl, False)
        self.assertEqual(i.port, 1883)
        self.assertEqual(i.write_topic, "write_topic")
        self.assertEqual(i.read_topic, "read_topic")

    def test_builds_a_human_readable_connection_string(self):
        i = MqttStreamInterface("localhost", "1883", False, "write_topic", "read_topic")
        self.assertEqual(i.connection_string(), "localhost:1883 (ssl: False) write topic: write_topic read topic: read_topic")
        i = MqttStreamInterface("localhost", "1883", True, "write_topic", "read_topic")
        self.assertEqual(i.connection_string(), "localhost:1883 (ssl: True) write topic: write_topic read topic: read_topic")

    @patch("openc3.streams.mqtt_stream.mqtt.Client")
    def test_connects_to_mqtt_broker(self, mock_client):
        mock_client_instance = mock_client.return_value
        mock_client_instance.is_connected.return_value = True
        i = MqttStreamInterface("localhost", "1883", False, "write_topic", "read_topic")
        i.set_option("ACK_TIMEOUT", ["10.0"])
        i.set_option("USERNAME", ["test_user"])
        i.set_option("PASSWORD", ["test_pass"])
        i.set_option("CERT", ["cert_content"])
        i.set_option("KEY", ["key_content"])
        i.set_option("CA_FILE", ["ca_file_content"])
        i.connect()
        self.assertTrue(i.connected())
        self.assertEqual(i.ack_timeout, 10.0)
        mock_client_instance.username_pw_set.assert_called_with("test_user", "test_pass")
        mock_client_instance.tls_set.assert_called_with(ca_certs=ANY, certfile=ANY, keyfile=ANY)
        mock_client_instance.loop_start.assert_called_once()
        mock_client_instance.connect.assert_called_with("localhost", 1883)
        mock_client_instance.is_connected.assert_called()
        # Manually call the callback
        reason_code = Mock()
        reason_code.is_failure = False
        mock_client_instance.on_connect(mock_client_instance, None, None, reason_code, None)
        mock_client_instance.subscribe.assert_called_with("read_topic")

    @patch("openc3.streams.mqtt_stream.mqtt.Client")
    def test_disconnects_the_mqtt_client(self, mock_client):
        mock_client_instance = mock_client.return_value
        i = MqttStreamInterface("localhost", "1883", False, "write_topic", "read_topic")
        i.connect()
        i.disconnect()
        self.assertFalse(i.connected())
        i.disconnect()  # Safe to call twice
        mock_client_instance.disconnect.assert_called()

    @patch("openc3.streams.mqtt_stream.mqtt.Client")
    def test_reads_a_message_from_the_mqtt_client(self, mock_client):
        mock_client_instance = mock_client.return_value
        i = MqttStreamInterface("localhost", "1883", False, "write_topic", "read_topic")
        i.connect()
        message = Mock()
        message.topic = "read_topic"
        message.payload = b"\x00\x01\x02\x03\x04\x05"
        mock_client_instance.on_message(mock_client_instance, i.stream.pkt_queue, message)
        packet = i.read()
        self.assertIsNone(packet.target_name)
        self.assertIsNone(packet.packet_name)
        self.assertEqual(packet.buffer, b"\x00\x01\x02\x03\x04\x05")

    @patch("openc3.streams.mqtt_stream.mqtt.Client")
    def test_writes_a_message_to_the_mqtt_client(self, mock_client):
        mock_client_instance = mock_client.return_value
        i = MqttStreamInterface("localhost", "1883", False, "write_topic", "read_topic")
        i.connect()
        pkt = System.commands.packet("INST", "COLLECT")
        pkt.restore_defaults()
        i.write(pkt)
        mock_client_instance.publish.assert_called_with("write_topic", pkt.buffer)
