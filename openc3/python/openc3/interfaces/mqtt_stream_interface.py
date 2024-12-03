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

import tempfile
from openc3.interfaces.stream_interface import StreamInterface
from openc3.config.config_parser import ConfigParser
from openc3.streams.mqtt_stream import MqttStream


# Base class for interfaces that send and receive messages over MQTT
class MqttStreamInterface(StreamInterface):
    # @param hostname [String] MQTT server to connect to
    # @param port [Integer] MQTT port
    def __init__(self, hostname, port=1883, ssl=False, write_topic=None, read_topic=None, protocol_type=None, protocol_args=[]):
        super().__init__(protocol_type, protocol_args)
        self.hostname = hostname
        self.port = int(port)
        self.ssl = ConfigParser.handle_true_false(ssl)
        self.write_topic = ConfigParser.handle_none(write_topic)
        self.read_topic = ConfigParser.handle_none(read_topic)
        self.ack_timeout = 5.0
        self.username = None
        self.password = None
        self.cert = None
        self.key = None
        self.ca_file = None
        self.keyfile_password = None

    def connection_string(self):
        result = f"{self.hostname}:{self.port} (ssl: {self.ssl})"
        if self.write_topic is not None:
            result += f" write topic: {self.write_topic}"
        if self.read_topic is not None:
            result += f" read topic: {self.read_topic}"
        return result

    # Creates a new {SerialStream} using the parameters passed in the constructor
    def connect(self):
        self.stream = MqttStream(self.hostname, self.port, self.ssl, self.write_topic, self.read_topic, self.ack_timeout)
        if self.username:
            self.stream.username = self.username
        if self.password:
            self.stream.password = self.password
        if self.cert:
            self.stream.cert = self.cert
        if self.key:
            self.stream.key = self.key
        if self.ca_file:
            self.stream.ca_file = self.ca_file
        if self.keyfile_password:
            self.stream.keyfile_password = self.keyfile_password
        super().connect()

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
