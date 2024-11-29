# encoding: ascii-8bit

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

require 'openc3/interfaces/stream_interface'
require 'openc3/streams/mqtt_stream'
require 'openc3/config/config_parser'

module OpenC3
  class MqttStreamInterface < StreamInterface
    # @param hostname [String] MQTT server to connect to
    # @param port [Integer] MQTT port
    # @param write_topic [String] MQTT publish topic
    # @param read_topic [String] MQTT receive topic
    def initialize(hostname, port = 1883, ssl = false, write_topic = nil, read_topic = nil, protocol_type = nil, *protocol_args)
      super(protocol_type, protocol_args)
      @hostname = hostname
      @port = Integer(port)
      @ssl = ConfigParser.handle_true_false(ssl)
      @write_topic = ConfigParser.handle_nil(write_topic)
      @read_topic = ConfigParser.handle_nil(read_topic)
      @ack_timeout = 5.0
      @username = nil
      @password = nil
      @cert = nil
      @key = nil
      @ca_file = nil
    end

    def connection_string
      result = "#{@hostname}:#{@port} (ssl: #{@ssl})"
      result += " write topic: #{@write_topic}" if @write_topic
      result += " read topic: #{@read_topic}" if @read_topic
      return result
    end

    # Creates a new {SerialStream} using the parameters passed in the constructor
    def connect
      @stream = MqttStream.new(@hostname, @port, @ssl, @write_topic, @read_topic, @ack_timeout)
      @stream.username = @username if @username
      @stream.password = @password if @password
      @stream.cert = @cert if @cert
      @stream.key = @key if @key
      @stream.ca_file = @ca_file if @ca_file
      super()
    end

    # Supported Options
    # USERNAME - Username for Mqtt Server
    # PASSWORD - Password for Mqtt Server
    # CERT - Public Key for Client Cert Auth
    # KEY - Private Key for Client Cert Auth
    # CA_FILE - Certificate Authority for Client Cert Auth
    # (see Interface#set_option)
    def set_option(option_name, option_values)
      super(option_name, option_values)
      case option_name.upcase
      when 'ACK_TIMEOUT'
        @ack_timeout = Float(option_values[0])
      when 'USERNAME'
        @username = option_values[0]
      when 'PASSWORD'
        @password = option_values[0]
      when 'CERT'
        # CERT must be given as a file
        @cert = Tempfile.new('cert')
        @cert.write(option_values[0])
        @cert.close
      when 'KEY'
        # KEY must be given as a file
        @key = Tempfile.new('key')
        @key.write(option_values[0])
        @key.close
      when 'CA_FILE'
        # CA_FILE must be given as a file
        @ca_file = Tempfile.new('ca_file')
        @ca_file.write(option_values[0])
        @ca_file.close
      end
    end
  end
end
