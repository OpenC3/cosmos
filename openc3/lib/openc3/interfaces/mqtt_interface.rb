# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
    # @param ssl [Boolean] Use SSL true/false
    def initialize(hostname, port = 1883, ssl = false)
      super()
      @hostname = hostname
      @port = Integer(port)
      @ssl = ConfigParser.handle_true_false(ssl)
      @username = nil
      @password = nil
      @cert = nil
      @key = nil
      @ca_file = nil

      @write_topics = []
      @read_topics = []

      # Build list of packets by topic
      @read_packets_by_topic = {}
      System.telemetry.all.each do |target_name, target_packets|
        target_packets.each do |packet_name, packet|
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

    # Connects the interface to its target(s)
    def connect
      @write_topics = []
      @read_topics = []
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
      @read_packets_by_topic.each do |topic, _|
        Logger.info "#{@name}: Subscribing to #{topic}"
        @client.subscribe(topic)
      end
      super()
    end

    # @return [Boolean] Whether the active ports (read and/or write) have
    #   created sockets. Since UDP is connectionless, creation of the sockets
    #   is used to determine connection.
    def connected?
      if @client
        return @client.connected?
      else
        return false
      end
    end

    # Disconnects the interface from its target(s)
    def disconnect
      @client.disconnect
      @client = nil
      super()
    end

    def read
      topic = @read_topics.shift
      packet = super()
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
      topics = packet.meta['TOPIC']
      topics = packet.meta['TOPICS'] unless topics
      if topics
        topics.each do |topic|
          @write_topics << topic
          super(packet)
        end
      else
        raise "Command packet #{packet.target_name} #{packet.packet_name} requires a META TOPIC or TOPICS"
      end
    end

    # Reads from the socket if the read_port is defined
    def read_interface
      topic, data = @client.get
      if data.nil? or data.length <= 0
        Logger.info "#{@name}: read returned nil" if data.nil?
        Logger.info "#{@name}: read returned 0 bytes" if not data.nil? and data.length <= 0
        return nil
      end
      @read_topics << topic
      read_interface_base(data)
      return data
    rescue IOError # Disconnected
      return nil
    end

    # Writes to the socket
    # @param data [String] Raw packet data
    def write_interface(data)
      write_interface_base(data)
      topic = @write_topics.shift
      @client.publish(topic, data)
      data
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
      when 'USERNAME'
        @username = option_values[0]
      when 'PASSWORD'
        @password = option_values[0]
      when 'CERT'
        @cert = option_values[0]
      when 'KEY'
        @key = option_values[0]
      when 'CA_FILE'
        # CA_FILE must be given as a file
        @ca_file = Tempfile.new('ca_file')
        @ca_file.write(option_values[0])
        @ca_file.close
      end
    end
  end
end
