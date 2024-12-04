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

# You can quickly setup an unauthenticated MQTT server in Docker with
# docker run -it -p 1883:1883 eclipse-mosquitto:2.0.15 mosquitto -c /mosquitto-no-auth.conf
# You can also test against encrypted and authenticated servers at https://test.mosquitto.org/

from time import sleep
import queue
import tempfile
from openc3.interfaces.interface import Interface
from openc3.system.system import System
from openc3.utilities.logger import Logger
from openc3.config.config_parser import ConfigParser

# See https://eclipse.dev/paho/files/paho.mqtt.python/html/client.html
import paho.mqtt.client as mqtt


# Base class for interfaces that send and receive messages over MQTT
class MqttInterface(Interface):
    # @param hostname [String] MQTT server to connect to
    # @param port [Integer] MQTT port
    def __init__(self, hostname, port=1883, ssl=False):
        super().__init__()
        self.hostname = hostname
        self.port = int(port)
        self.ssl = ConfigParser.handle_true_false(ssl)
        self.ack_timeout = 5.0
        self.username = None
        self.password = None
        self.cert = None
        self.key = None
        self.ca_file = None
        self.keyfile_password = None

        self.read_topics = []
        self.write_topics = []
        self.pkt_queue = queue.Queue()

        # Build list of packets by topic
        self.read_packets_by_topic = {}
        for _, target_packets in System.telemetry.all().items():
            for _, packet in target_packets.items():
                topics = packet.meta.get("TOPIC")
                if not topics:
                    topics = packet.meta.get("TOPICS")
                if topics:
                    for topic in topics:
                        self.read_packets_by_topic[topic] = packet

    def connection_string(self):
        return f"{self.hostname}:{self.port} (ssl: {self.ssl})"

    # Connects the interface to its target(s)
    def connect(self):
        self.read_topics = []
        self.write_topics = []
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
        super().connect()

    def on_connect(self, client, userdata, flags, reason_code, properties):
        if reason_code.is_failure:
            Logger.error(f"MQTT failed to connect: {reason_code}")
        else:
            # we should always subscribe from on_connect callback to be sure
            # our subscribed is persisted across reconnections.
            for topic, _ in self.read_packets_by_topic.items():
                client.subscribe(topic)

    # @return [Boolean] Whether the MQTT client is connected
    def connected(self):
        if self.client:
            return self.client.is_connected()
        else:
            return False

    # Disconnects the interface from its target(s)
    def disconnect(self):
        self.pkt_queue.put(None)
        if self.client:
            self.client.disconnect()
            self.client = None
        super().disconnect()

    def read(self):
        packet = super().read()
        if packet is not None:
            topic = self.read_topics.pop(0)
            identified_packet = self.read_packets_by_topic.get(topic)
            if identified_packet:
                identified_packet = identified_packet.clone()
                identified_packet.buffer = packet.buffer
                packet = identified_packet
            packet.received_time = None
        return packet

    def write(self, packet):
        self.write_mutex.acquire()
        topics = packet.meta.get("TOPIC")
        if not topics:
            topics = packet.meta.get("TOPICS")
        if topics:
            for topic in topics:
                self.write_topics.append(topic)
                super().write(packet)
        else:
            raise RuntimeError(
                f"Command packet '{packet.target_name} {packet.packet_name}' requires a META TOPIC or TOPICS"
            )
        self.write_mutex.release()

    def on_message(self, client, userdata, message):
        # userdata is set via user_data_set
        self.read_topics.append(message.topic)
        userdata.put(message.payload)

    def read_interface(self):
        data = self.pkt_queue.get(block=True)
        extra = None
        if data is not None:
            self.read_interface_base(data, extra)
        return (data, extra)

    # Writes to the client
    # @param data [String] Raw packet data
    def write_interface(self, data, extra=None):
        self.write_interface_base(data, extra)
        try:
            topic = self.write_topics.pop(0)
        except IndexError:
            raise RuntimeError(f"write_interface called with no topics: {self.write_topics}")
        info = self.client.publish(topic, data)
        # This more closely matches the ruby implementation
        info.wait_for_publish(timeout=self.ack_timeout)

    # Supported Options
    # USERNAME - Username for Mqtt Server
    # PASSWORD - Password for Mqtt Server
    # CERT - Public Key for Client Cert Auth
    # KEY - Private Key for Client Cert Auth
    # CA_FILE - Certificate Authority for Client Cert Auth
    # KEYFILE_PASSWORD - Password for encrypted cert and key files
    # (see Interface#set_option)
    def set_option(self, option_name, option_values):
        super().set_option(option_name, option_values)
        match option_name.upper():
            case "ACK_TIMEOUT":
                self.ack_timeout = float(option_values[0])
            case "USERNAME":
                self.username = option_values[0]
            case "PASSWORD":
                self.password = option_values[0]
            case "CERT":
                # CERT must be given as a file
                self.cert = tempfile.NamedTemporaryFile(mode="w+", delete=False)
                self.cert.write(option_values[0])
                self.cert.close()
            case "KEY":
                # KEY must be given as a file
                self.key = tempfile.NamedTemporaryFile(mode="w+", delete=False)
                self.key.write(option_values[0])
                self.key.close()
            case "CA_FILE":
                # CA_FILE must be given as a file
                self.ca_file = tempfile.NamedTemporaryFile(mode="w+", delete=False)
                self.ca_file.write(option_values[0])
                self.ca_file.close()
            case "KEYFILE_PASSWORD":
                self.keyfile_password = option_values[0]
