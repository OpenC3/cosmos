# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc.
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

require 'openc3/interfaces/mqtt_interface' # For MQTT patches
require 'openc3/streams/stream'
require 'openc3/config/config_parser'

module OpenC3
  class MqttStream < Stream
    attr_reader :hostname
    attr_reader :port
    attr_reader :ssl
    attr_reader :write_topic
    attr_reader :read_topic
    attr_accessor :username
    attr_accessor :password
    attr_accessor :cert
    attr_accessor :key
    attr_accessor :ca_file

    def initialize(hostname, port = 1883, ssl = false, write_topic = nil, read_topic = nil)
      super()

      @hostname = hostname
      @port = Integer(port)
      @ssl = ConfigParser.handle_true_false(ssl)
      @write_topic = ConfigParser.handle_nil(write_topic)
      @read_topic = ConfigParser.handle_nil(read_topic)
      @connected = false

      @username = nil
      @password = nil
      @cert = nil
      @key = nil
      @ca_file = nil

      # Mutex on write is needed to protect from commands coming in from more
      # than one tool
      @write_mutex = Mutex.new
    end

    # @return [String] Returns a binary string of data from the read_topic
    def read
      raise "Attempt to read from write only stream" unless @read_topic

      # No read mutex is needed because reads happen serially
      _, data = @client.get
      if data.nil? or data.length <= 0
        Logger.info "MqttStream: read returned nil" if data.nil?
        Logger.info "MqttStream: read returned 0 bytes" if not data.nil? and data.length <= 0
        return nil
      end

      return data
    end

    # @param data [String] A binary string of data to write to the write_topic
    def write(data)
      raise "Attempt to write to read only stream" unless @write_topic

      @write_mutex.synchronize do
        @client.publish(@write_topic, data)
      end
    end

    # Connect the stream
    def connect
      @client = MQTT::Client.new
      @client.host = @hostname
      @client.port = @port
      @client.ssl = @ssl
      @client.username = @username if @username
      @client.password = @password if @password
      @client.cert = @cert if @cert
      @client.key = @key if @key
      @client.ca_file = @ca_file.path if @ca_file
      @client.connect
      @client.subscribe(@read_topic) if @read_topic
      @connected = true
    end

    def connected?
      @connected
    end

    def disconnect
      if @connected
        @client.disconnect
        @client = nil
        @connected = false
      end
    end
  end
end
