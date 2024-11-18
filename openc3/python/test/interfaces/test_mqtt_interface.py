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
from openc3.interfaces.mqtt_interface import MqttInterface
from openc3.system.system import System


class TestMqttInterface(unittest.TestCase):
    def setUp(self):
        mock_redis(self)
        setup_system()

    def test_sets_all_the_instance_variables(self):
        i = MqttInterface("localhost", "1883")
        self.assertEqual(i.name, "MqttInterface")
        self.assertEqual(i.hostname, "localhost")
        self.assertEqual(i.port, 1883)
        self.assertEqual(i.ack_timeout, 5.0)

    def test_builds_a_human_readable_connection_string(self):
        i = MqttInterface("localhost", "1883")
        self.assertEqual(i.connection_string(), "localhost:1883")

    @patch("openc3.interfaces.mqtt_interface.mqtt.Client")
    def test_connects_to_mqtt_broker(self, mock_client):
        mock_client_instance = mock_client.return_value
        mock_client_instance.is_connected.return_value = True
        i = MqttInterface("localhost", "1883")
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
        mock_client_instance.subscribe.assert_any_call("HEALTH_STATUS")
        mock_client_instance.subscribe.assert_any_call("ADCS")

    @patch("openc3.interfaces.mqtt_interface.mqtt.Client")
    def test_disconnects_the_mqtt_client(self, mock_client):
        mock_client_instance = mock_client.return_value
        i = MqttInterface("localhost", "1883")
        i.connect()
        i.disconnect()
        self.assertFalse(i.connected())
        i.disconnect()  # Safe to call twice
        mock_client_instance.disconnect.assert_called()

    @patch("openc3.interfaces.mqtt_interface.mqtt.Client")
    def test_reads_a_message_from_the_mqtt_client(self, mock_client):
        mock_client_instance = mock_client.return_value
        i = MqttInterface("localhost", "1883")
        i.connect()
        message = Mock()
        message.topic = "HEALTH_STATUS"
        message.payload = b"\x00\x00\x00\x00\x00\x00"
        mock_client_instance.on_message(mock_client_instance, i.pkt_queue, message)
        packet = i.read()
        self.assertEqual(packet.target_name, "INST")
        self.assertEqual(packet.packet_name, "HEALTH_STATUS")

    @patch("openc3.interfaces.mqtt_interface.mqtt.Client")
    def test_writes_a_message_to_the_mqtt_client(self, mock_client):
        mock_client_instance = mock_client.return_value
        i = MqttInterface("localhost", "1883")
        i.connect()
        pkt = System.commands.packet("INST", "COLLECT")
        pkt.restore_defaults()
        i.write(pkt)
        mock_client_instance.publish.assert_called_with("COLLECT", pkt.buffer)

    @patch("openc3.interfaces.mqtt_interface.mqtt.Client")
    def test_raises_on_packets_without_meta_topic(self, _):
        i = MqttInterface("localhost", "1883")
        i.connect()
        pkt = System.commands.packet("INST", "CLEAR")
        with self.assertRaisesRegex(RuntimeError, "Command packet 'INST CLEAR' requires a META TOPIC or TOPICS"):
            i.write(pkt)
