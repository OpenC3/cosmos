# encoding: ascii-8bit

require 'spec_helper'
require 'openc3/interfaces/mqtt_interface'
=begin
This expanded test suite covers all the methods in the MqttInterface class and includes various scenarios to maximize coverage. Here's a summary of the additions and improvements:

1. Added more detailed tests for the `initialize` method, including type conversion for port and ssl.
2. Expanded the `connect` method tests to verify MQTT client creation and connection.
3. Added tests for the `disconnect` method.
4. Added tests for the `connected?` method.
5. Expanded tests for the `read` method, covering different scenarios.
6. Added tests for the `write` method.
7. Added tests for the `write_raw` method.

This test suite uses RSpec's mocking capabilities to simulate the MQTT client behavior without actually connecting to an MQTT broker. This allows for more controlled and faster tests.

To run these tests, make sure you have the necessary dependencies installed and the `spec_helper.rb` file is properly set up. Then, you can run the tests using the `rspec` command in the terminal from the directory containing this test file.
=end

module OpenC3
  describe MqttInterface do
    before(:all) do
      setup_system()
    end

    let(:valid_hostname) { 'localhost' }
    let(:valid_port) { '1883' }
    let(:valid_ssl) { 'false' }

    describe "initialize" do
      it "sets all the instance variables" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect(interface.name).to eq "MqttInterface"
        expect(interface.instance_variable_get(:@hostname)).to eq valid_hostname
        expect(interface.instance_variable_get(:@port)).to eq 1883
        expect(interface.instance_variable_get(:@ssl)).to eq false
        expect(interface.instance_variable_get(:@connect_timeout)).to eq 5
        expect(interface.instance_variable_get(:@read_timeout)).to eq 5
        expect(interface.instance_variable_get(:@write_timeout)).to eq 5
        expect(interface.instance_variable_get(:@keepalive)).to eq 60
        expect(interface.instance_variable_get(:@client)).to be_nil
      end

      it "converts port to integer" do
        interface = MqttInterface.new(valid_hostname, '8080', valid_ssl)
        expect(interface.instance_variable_get(:@port)).to eq 8080
      end

      it "converts ssl string to boolean" do
        interface = MqttInterface.new(valid_hostname, valid_port, 'true')
        expect(interface.instance_variable_get(:@ssl)).to eq true
      end
    end

    describe "connection_string" do
      it "builds a human readable connection string" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect(interface.connection_string).to eq "localhost:1883 (ssl: false)"

        interface = MqttInterface.new('1.2.3.4', '8080', 'true')
        expect(interface.connection_string).to eq "1.2.3.4:8080 (ssl: true)"
      end
    end

    describe "connect" do
      let(:mock_client) { double('MQTT::Client') }

      before do
        allow(MQTT::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:connect)
      end

      it "creates a new MQTT client and connects" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect(MQTT::Client).to receive(:new).with(
          host: valid_hostname,
          port: 1883,
          ssl: false,
          connect_timeout: 5,
          read_timeout: 5,
          write_timeout: 5,
          keep_alive: 60
        )
        expect(mock_client).to receive(:connect)
        interface.connect
      end

      it "sets the client instance variable" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        interface.connect
        expect(interface.instance_variable_get(:@client)).to eq mock_client
      end
    end

    describe "disconnect" do
      let(:mock_client) { double('MQTT::Client') }

      it "disconnects the client if connected" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        interface.instance_variable_set(:@client, mock_client)
        expect(mock_client).to receive(:disconnect)
        interface.disconnect
      end

      it "does nothing if client is not connected" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect { interface.disconnect }.not_to raise_error
      end
    end

    describe "connected?" do
      let(:mock_client) { double('MQTT::Client') }

      it "returns true if client is connected" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        interface.instance_variable_set(:@client, mock_client)
        allow(mock_client).to receive(:connected?).and_return(true)
        expect(interface.connected?).to be true
      end

      it "returns false if client is not connected" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect(interface.connected?).to be false
      end
    end

    describe "read" do
      let(:mock_client) { double('MQTT::Client') }

      before do
        allow(MQTT::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:connect)
      end

      it "connects if not connected" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect(interface).to receive(:connect)
        allow(mock_client).to receive(:get).and_return(nil)
        interface.read
      end

      it "returns nil if no message is available" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        interface.connect
        allow(mock_client).to receive(:get).and_return(nil)
        expect(interface.read).to be_nil
      end

      it "returns a packet if a message is available" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        interface.connect
        allow(mock_client).to receive(:get).and_return(['topic', 'message'])
        packet = interface.read
        expect(packet.topic).to eq 'topic'
        expect(packet.buffer).to eq 'message'
      end
    end

    describe "write" do
      let(:mock_client) { double('MQTT::Client') }

      before do
        allow(MQTT::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:connect)
      end

      it "connects if not connected" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect(interface).to receive(:connect)
        allow(mock_client).to receive(:publish)
        interface.write(Packet.new(nil, 'topic', 'message'))
      end

      it "publishes the message" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        interface.connect
        expect(mock_client).to receive(:publish).with('topic', 'message')
        interface.write(Packet.new(nil, 'topic', 'message'))
      end
    end

    describe "write_raw" do
      let(:mock_client) { double('MQTT::Client') }

      before do
        allow(MQTT::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:connect)
      end

      it "connects if not connected" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        expect(interface).to receive(:connect)
        allow(mock_client).to receive(:publish)
        interface.write_raw('topic', 'message')
      end

      it "publishes the raw message" do
        interface = MqttInterface.new(valid_hostname, valid_port, valid_ssl)
        interface.connect
        expect(mock_client).to receive(:publish).with('topic', 'message')
        interface.write_raw('topic', 'message')
      end
    end
  end
end
