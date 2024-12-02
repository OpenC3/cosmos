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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import threading
import queue
from time import sleep
from openc3.config.config_parser import ConfigParser
from openc3.utilities.logger import Logger

# See https://eclipse.dev/paho/files/paho.mqtt.python/html/client.html
import paho.mqtt.client as mqtt


class MqttStream:
    def __init__(self, hostname, port=1883, ssl=False, write_topic=None, read_topic=None, ack_timeout=5):
        super().__init__()

        self.hostname = hostname
        self.port = int(port)
        self.ssl = ConfigParser.handle_true_false(ssl)
        self.write_topic = ConfigParser.handle_none(write_topic)
        self.read_topic = ConfigParser.handle_none(read_topic)
        self.ack_timeout = float(ack_timeout)
        self.pkt_queue = queue.Queue()

        self.username = None
        self.password = None
        self.cert = None
        self.key = None
        self.ca_file = None
        self.keyfile_password = None

        # Mutex on write is needed to protect from commands coming in from more than one tool
        self.write_mutex = threading.RLock()

    # Connect the stream
    def connect(self):
        self.pkt_queue.empty()

        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
        self.client.user_data_set(self.pkt_queue)  # passed to on_message

        if self.ssl:
            self.client.tls_set()
        if self.username and self.password:
            self.client.username_pw_set(self.username, self.password)
        # You still need the ca_file if you're using your own cert and key
        if self.cert and self.key and self.ca_file:
            if self.keyfile_password:
                self.client.tls_set(
                    ca_certs=self.ca_file.name,
                    certfile=self.cert.name,
                    keyfile=self.key.name,
                    keyfile_password=self.keyfile_password,
                )
            else:
                self.client.tls_set(ca_certs=self.ca_file.name, certfile=self.cert.name, keyfile=self.key.name)
        elif self.ca_file:
            self.client.tls_set(ca_certs=self.ca_file.name)

        self.client.loop_start()
        # Connect doesn't fully establish the connection, it just sends the CONNECT packet
        # When the client loop receives an ONNACK packet from the broker in response to the CONNECT packet
        # it calls the on_connect callback and updates the client state to connected (is_connected() returns True)
        self.client.connect(self.hostname, self.port)
        i = 0
        while not self.client.is_connected() and i < (self.ack_timeout * 100):
            sleep(0.01)
            i += 1

    def on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            Logger.error(f"MQTT failed to connect: {reason_code}")
        else:
            # we should always subscribe from on_connect callback to be sure
            # our subscribed is persisted across reconnections.
            if self.read_topic:
                client.subscribe(self.read_topic)

    def connected(self):
        if self.client:
            return self.client.is_connected()
        else:
            return False

    def disconnect(self):
        if self.client:
            self.client.disconnect()
            self.client = None

    def on_message(self, client, userdata, message):
        # userdata is set via user_data_set
        userdata.put(message.payload)

    # @return [String] Returns a binary string of data from the read_topic
    def read(self):
        if not self.read_topic:
            raise RuntimeError("Attempt to read from write only stream")

        # No read mutex is needed because reads happen serially
        data = self.pkt_queue.get(block=True)
        if data is None or len(data) <= 0:
            if data is None:
                Logger.info("MqttStream: read returned None")
            if data is not None and len(data) <= 0:
                Logger.info("MqttStream: read returned 0 bytes")
            return None

        return data

    # @param data [String] A binary string of data to write to the write_topic
    def write(self, data):
        if not self.write_topic:
            raise RuntimeError("Attempt to write to read only stream")

        self.write_mutex.acquire()
        self.client.publish(self.write_topic, data)
        self.write_mutex.release()
