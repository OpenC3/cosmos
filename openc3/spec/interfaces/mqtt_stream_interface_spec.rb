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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/interfaces/mqtt_stream_interface'

module OpenC3
  describe MqttStreamInterface do
    MQTT_CLIENT = 'MQTT::Client'.freeze

    before(:all) do
      setup_system()
    end

    describe "initialize" do
      it "sets all the instance variables" do
        i = MqttStreamInterface.new('localhost', '1883', false, 'write_topic', 'read_topic')
        expect(i.name).to eql "MqttStreamInterface"
        expect(i.instance_variable_get(:@hostname)).to eql 'localhost'
        expect(i.instance_variable_get(:@port)).to eql 1883
        expect(i.instance_variable_get(:@write_topic)).to eql 'write_topic'
        expect(i.instance_variable_get(:@read_topic)).to eql 'read_topic'
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        i = MqttStreamInterface.new('localhost', '1883', false, 'write_topic', 'read_topic')
        expect(i.connection_string).to eql "localhost:1883 (ssl: false) write topic: write_topic read topic: read_topic"
        i = MqttStreamInterface.new('localhost', '1883', true, 'write_topic', 'read_topic')
        expect(i.connection_string).to eql "localhost:1883 (ssl: true) write topic: write_topic read topic: read_topic"
      end
    end

    describe "connect" do
      it "sets various ssl settings based on options" do
        double = double(MQTT_CLIENT)
        expect(double).to receive(:ack_timeout=).with(10.0)
        expect(double).to receive(:host=).with('localhost')
        expect(double).to receive(:port=).with(1883)
        expect(double).to receive(:username=).with('test_user')
        expect(double).to receive(:password=).with('test_pass')
        expect(double).to receive(:ssl=).with(false)
        expect(double).to receive(:ssl=).with(true).twice
        expect(double).to receive(:cert_file=)
        expect(double).to receive(:key_file=)
        expect(double).to receive(:ca_file=)
        expect(double).to receive(:connect)
        expect(double).to receive(:connected?).and_return(true)
        # inst_tlm.txt declares META TOPIC on the first 2 packets
        expect(double).to receive(:subscribe).with('read_topic')
        allow(MQTT::Client).to receive(:new).and_return(double)

        i = MqttStreamInterface.new('localhost', '1883', false, 'write_topic', 'read_topic')
        i.set_option('USERNAME', ['test_user'])
        i.set_option('PASSWORD', ['test_pass'])
        i.set_option('CERT', ['cert_content'])
        i.set_option('KEY', ['key_content'])
        i.set_option('CA_FILE', ['ca_file_content'])
        i.set_option('ACK_TIMEOUT', ['10.0'])
        i.connect()
        expect(i.connected?).to be true
      end

      it "sets ssl even without cert_file, key_file, or ca_file" do
        double = double(MQTT_CLIENT).as_null_object
        expect(double).to receive(:ssl=).with(true)
        expect(double).to receive(:connected?).and_return(true)
        allow(MQTT::Client).to receive(:new).and_return(double)

        i = MqttStreamInterface.new('localhost', '1883', true, 'write_topic', 'read_topic')
        i.connect()
        expect(i.connected?).to be true
      end
    end

    describe "disconnect" do
      it "disconnects the mqtt client" do
        double = double(MQTT_CLIENT).as_null_object
        expect(double).to receive(:connect)
        expect(double).to receive(:disconnect)
        allow(MQTT::Client).to receive(:new).and_return(double)

        i = MqttStreamInterface.new('localhost', '1883')
        i.connect()
        i.disconnect()
        expect(i.connected?).to be false
        i.disconnect() # Safe to call twice
      end
    end

    describe "read" do
      it "reads a message from the mqtt client" do
        double = double(MQTT_CLIENT).as_null_object
        expect(double).to receive(:connect)
        expect(double).to receive(:connected?).and_return(true)
        expect(double).to receive(:get).and_return(['HEALTH_STATUS', "\x00\x01\x02\x03\x04\x05"])
        expect(double).to receive(:get).and_return(['ADCS', "\x06\x07\x08\x09\x0A\x0B"])
        allow(MQTT::Client).to receive(:new).and_return(double)

        i = MqttStreamInterface.new('localhost', '1883', false, 'write_topic', 'read_topic')
        i.connect()
        packet = i.read()
        expect(packet.target_name).to be_nil
        expect(packet.packet_name).to be_nil
        expect(packet.buffer).to eql "\x00\x01\x02\x03\x04\x05"
        packet = i.read()
        expect(packet.target_name).to be_nil
        expect(packet.packet_name).to be_nil
        expect(packet.buffer).to eql "\x06\x07\x08\x09\x0A\x0B"
      end

      it "disconnects if the mqtt client returns no data" do
        double = double(MQTT_CLIENT).as_null_object
        expect(double).to receive(:connect)
        expect(double).to receive(:connected?).and_return(true)
        expect(double).to receive(:get).and_return(['HEALTH_STATUS', nil])
        allow(MQTT::Client).to receive(:new).and_return(double)

        capture_io do |stdout|
          i = MqttStreamInterface.new('localhost', '1883', false, 'write_topic', 'read_topic')
          i.connect()
          i.read()
          expect(stdout.string).to match(/read returned nil/)
          expect(stdout.string).to match(/read_interface requested disconnect/)
        end
      end
    end

    describe "write" do
      it "writes a message to the mqtt client" do
        double = double(MQTT_CLIENT).as_null_object
        expect(double).to receive(:connect)
        expect(double).to receive(:connected?).and_return(true)
        allow(MQTT::Client).to receive(:new).and_return(double)

        i = MqttStreamInterface.new('localhost', '1883', false, 'write_topic', 'read_topic')
        i.connect()
        pkt = System.commands.packet('INST', 'COLLECT')
        pkt.restore_defaults()
        expect(double).to receive(:publish).with('write_topic', pkt.buffer)
        i.write(pkt)
      end
    end
  end
end
