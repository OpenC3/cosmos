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

require 'openc3/interfaces/interface'
require 'openc3/config/config_parser'
require 'mqtt'

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
      @client = MQTT::Client.new
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
      @client.host = @hostname
      @client.port = @port
      @client.ssl = @ssl
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
      @client.connected?
    end

    # Disconnects the interface from its target(s)
    def disconnect
      @client.disconnect
      super()
    end

    def read
      topic = @read_topics.shift
      packet = super()
      identified_packet = @read_packets_by_topic[topic]
      if identified_packet
        identified_packet = identified_packet.dup
        identified_packet.buffer = packet.buffer
        packet = identified_packet
      end
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
  end
end
