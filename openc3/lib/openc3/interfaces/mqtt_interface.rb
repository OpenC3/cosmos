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

require 'openc3/interfaces/interface'
require 'openc3/config/config_parser'
require 'mqtt'

# Patches to the Ruby MQTT library so that it will work reliably with COSMOS
saved_verbose = $VERBOSE
$VERBOSE = nil
module MQTT
  class Client
    def get(topic = nil, options = {})
      if block_given?
        get_packet(topic) do |packet|
          yield(packet.topic, packet.payload) unless packet.retain && options[:omit_retained]
        end
      else
        loop do
          # Wait for one packet to be available
          packet = get_packet(topic)
          return nil unless packet # Patch for COSMOS
          return packet.topic, packet.payload unless packet.retain && options[:omit_retained]
        end
      end
    end

    def get_packet(topic = nil)
      # Subscribe to a topic, if an argument is given
      subscribe(topic) unless topic.nil?

      if block_given?
        # Loop forever!
        loop do
          packet = @read_queue.pop
          return nil unless packet # Patch for COSMOS
          yield(packet)
          puback_packet(packet) if packet.qos > 0
        end
      else
        # Wait for one packet to be available
        packet = @read_queue.pop
        return nil unless packet # Patch for COSMOS
        puback_packet(packet) if packet.qos > 0
        return packet
      end
    end

    def disconnect(send_msg = true)
      # Stop reading packets from the socket first
      @read_thread.kill if @read_thread && @read_thread.alive?
      @read_thread = nil

      @read_queue << nil # Patch for COSMOS

      # Close the socket if it is open
      if connected?
        if send_msg
          packet = MQTT::Packet::Disconnect.new
          send_packet(packet)
        end
        @socket.close unless @socket.nil?
        @socket = nil
      end
    end

  end
end
$VERBOSE = saved_verbose

module OpenC3
  # Base class for interfaces that send and receive messages over MQTT
  class MqttInterface < Interface
    # @param hostname [String] MQTT server to connect to
    # @param port [Integer] MQTT port
    # @param ssl [Boolean] Whether to use SSL
    def initialize(hostname, port = 1883, ssl = false)
      super()
      @hostname = hostname
      @port = Integer(port)
      @ssl = ConfigParser.handle_true_false(ssl)
      @ack_timeout = 5.0
      @username = nil
      @password = nil
      @cert = nil
      @key = nil
      @ca_file = nil

      @write_topics = []
      @read_topics = []

      # Build list of packets by topic
      @read_packets_by_topic = {}
      System.telemetry.all.each do |_target_name, target_packets|
        target_packets.each do |_packet_name, packet|
          topics = packet.meta['TOPIC']
          topics = packet.meta['TOPICS'] unless topics
          if topics
            topics.each do |topic|
              @read_packets_by_topic[topic] = packet
            end
          end
        end
      end
    end

    def connection_string
      return "#{@hostname}:#{@port} (ssl: #{@ssl})"
    end

    # Connects the interface to its target(s)
    def connect
      @write_topics = []
      @read_topics = []
      @client = MQTT::Client.new
      @client.ack_timeout = @ack_timeout
      @client.host = @hostname
      @client.port = @port
      @client.username = @username if @username
      @client.password = @password if @password
      @client.ssl = @ssl
      if @cert and @key
        @client.ssl = true
        @client.cert_file = @cert.path
        @client.key_file = @key.path
      end
      if @ca_file
        @client.ssl = true
        @client.ca_file = @ca_file.path
      end
      @client.connect
      @read_packets_by_topic.each do |topic, _|
        Logger.info "#{@name}: Subscribing to #{topic}"
        @client.subscribe(topic)
      end
      super()
    end

    # @return [Boolean] Whether the MQTT client is connected
    def connected?
      if @client
        return @client.connected?
      else
        return false
      end
    end

    # Disconnects the interface from its target(s)
    def disconnect
      if @client
        @client.disconnect
        @client = nil
      end
      super()
    end

    def read
      packet = super()
      topic = @read_topics.shift
      return nil unless packet
      identified_packet = @read_packets_by_topic[topic]
      if identified_packet
        identified_packet = identified_packet.dup
        identified_packet.buffer = packet.buffer
        packet = identified_packet
      end
      packet.received_time = nil
      return packet
    end

    def write(packet)
      @write_mutex.synchronize do
        topics = packet.meta['TOPIC']
        topics = packet.meta['TOPICS'] unless topics
        if topics
          topics.each do |topic|
            @write_topics << topic
            super(packet)
          end
        else
          raise "Command packet '#{packet.target_name} #{packet.packet_name}' requires a META TOPIC or TOPICS"
        end
      end
    end

    # Reads from the client
    def read_interface
      topic, data = @client.get
      if data.nil? or data.length <= 0
        Logger.info "#{@name}: read returned nil" if data.nil?
        Logger.info "#{@name}: read returned 0 bytes" if not data.nil? and data.length <= 0
        return nil
      end
      @read_topics << topic
      extra = nil
      read_interface_base(data, extra)
      return data, extra
    rescue IOError # Disconnected
      return nil
    end

    # Writes to the client
    # @param data [String] Raw packet data
    def write_interface(data, extra = nil)
      write_interface_base(data, extra)
      topic = @write_topics.shift
      @client.publish(topic, data)
      return data, extra
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

    def details
      result = super()
      result['hostname'] = @hostname
      result['port'] = @port
      result['ssl'] = @ssl
      result['ack_timeout'] = @ack_timeout
      result['username'] = @username
      result['password'] = 'Set' if @password
      result['cert'] = 'Set' if @cert
      result['key'] = 'Set' if @key
      result['ca_file'] = 'Set' if @ca_file
      result['options'].delete('PASSWORD')
      result['options'].delete('CERT')
      result['options'].delete('KEY')
      result['options'].delete('CA_FILE')
      result['read_packets_by_topic'] = @read_packets_by_topic
      return result
    end
  end
end
