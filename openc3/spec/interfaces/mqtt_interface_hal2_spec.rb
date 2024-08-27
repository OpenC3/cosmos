
require 'spec_helper'
require 'openc3/interfaces/mqtt_interface'
require 'openc3/packets/packet'
require 'openc3/system/system'

module OpenC3
  describe MqttInterface do
    before(:each) do
      @interface = MqttInterface.new('localhost', 1883, false)
      allow(System).to receive_message_chain(:telemetry, :all).and_return({
        'TARGET' => {
          'PACKET' => OpenC3::Packet.new('TARGET', 'PACKET', :TLM, {
            'meta' => { 'TOPIC' => ['test/topic'] }
          })
        }
      })
    end

    describe "#initialize" do
      it "initializes with default values" do
        expect(@interface.instance_variable_get(:@hostname)).to eq('localhost')
        expect(@interface.instance_variable_get(:@port)).to eq(1883)
        expect(@interface.instance_variable_get(:@ssl)).to eq(false)
      end

      it "initializes with custom values" do
        interface = MqttInterface.new('example.com', 8883, true)
        expect(interface.instance_variable_get(:@hostname)).to eq('example.com')
        expect(interface.instance_variable_get(:@port)).to eq(8883)
        expect(interface.instance_variable_get(:@ssl)).to eq(true)
      end
    end

    describe "#connection_string" do
      it "returns the correct connection string" do
        expect(@interface.connection_string).to eq("localhost:1883 (ssl: false)")
      end
    end

    describe "#connect" do
      it "connects to the MQTT server and subscribes to topics" do
        mock_client = double('MQTT::Client')
        allow(MQTT::Client).to receive(:new).and_return(mock_client)
        expect(mock_client).to receive(:host=).with('localhost')
        expect(mock_client).to receive(:port=).with(1883)
        expect(mock_client).to receive(:ssl=).with(false)
        expect(mock_client).to receive(:connect)
        expect(mock_client).to receive(:subscribe).with('test/topic')
        expect(Logger).to receive(:info).with("#{@interface.name}: Subscribing to test/topic")
        @interface.connect
      end
    end

    describe "#connected?" do
      it "returns true when connected" do
        mock_client = double('MQTT::Client', connected?: true)
        @interface.instance_variable_set(:@client, mock_client)
        expect(@interface.connected?).to be true
      end

      it "returns false when not connected" do
        expect(@interface.connected?).to be false
      end
    end

    describe "#disconnect" do
      it "disconnects from the MQTT server" do
        mock_client = double('MQTT::Client')
        expect(mock_client).to receive(:disconnect)
        @interface.instance_variable_set(:@client, mock_client)
        @interface.disconnect
        expect(@interface.instance_variable_get(:@client)).to be_nil
      end
    end

    describe "#read" do
      it "reads and identifies packets" do
        packet = OpenC3::Packet.new('TARGET', 'PACKET', :TLM)
        @interface.instance_variable_set(:@read_topics, ['test/topic'])
        allow(@interface).to receive(:super).and_return(packet)
        result = @interface.read
        expect(result).to be_a(OpenC3::Packet)
        expect(result.target_name).to eq('TARGET')
        expect(result.packet_name).to eq('PACKET')
      end
    end

    describe "#write" do
      it "writes packets to the correct topics" do
        packet = OpenC3::Packet.new('TARGET', 'PACKET', :CMD, {
          'meta' => { 'TOPIC' => ['test/topic'] }
        })
        expect(@interface).to receive(:super).with(packet)
        @interface.write(packet)
        expect(@interface.instance_variable_get(:@write_topics)).to eq(['test/topic'])
      end

      it "raises an error if no topic is specified" do
        packet = OpenC3::Packet.new('TARGET', 'PACKET', :CMD)
        expect { @interface.write(packet) }.to raise_error(RuntimeError, /requires a META TOPIC or TOPICS/)
      end
    end

    describe "#read_interface" do
      it "reads data from the MQTT client" do
        mock_client = double('MQTT::Client')
        allow(mock_client).to receive(:get).and_return(['test/topic', 'test_data'])
        @interface.instance_variable_set(:@client, mock_client)
        data, extra = @interface.read_interface
        expect(data).to eq('test_data')
        expect(extra).to be_nil
        expect(@interface.instance_variable_get(:@read_topics)).to eq(['test/topic'])
      end

      it "returns nil if no data is read" do
        mock_client = double('MQTT::Client')
        allow(mock_client).to receive(:get).and_return(['test/topic', nil])
        @interface.instance_variable_set(:@client, mock_client)
        expect(Logger).to receive(:info).with("#{@interface.name}: read returned nil")
        expect(@interface.read_interface).to be_nil
      end
    end

    describe "#write_interface" do
      it "writes data to the MQTT client" do
        mock_client = double('MQTT::Client')
        expect(mock_client).to receive(:publish).with('test/topic', 'test_data')
        @interface.instance_variable_set(:@client, mock_client)
        @interface.instance_variable_set(:@write_topics, ['test/topic'])
        data, extra = @interface.write_interface('test_data')
        expect(data).to eq('test_data')
        expect(extra).to be_nil
      end
    end

    describe "#set_option" do
      it "sets username option" do
        @interface.set_option('USERNAME', ['test_user'])
        expect(@interface.instance_variable_get(:@username)).to eq('test_user')
      end

      it "sets password option" do
        @interface.set_option('PASSWORD', ['test_pass'])
        expect(@interface.instance_variable_get(:@password)).to eq('test_pass')
      end

      it "sets cert option" do
        @interface.set_option('CERT', ['test_cert'])
        expect(@interface.instance_variable_get(:@cert)).to eq('test_cert')
      end

      it "sets key option" do
        @interface.set_option('KEY', ['test_key'])
        expect(@interface.instance_variable_get(:@key)).to eq('test_key')
      end

      it "sets ca_file option" do
        @interface.set_option('CA_FILE', ['test_ca_file'])
        expect(@interface.instance_variable_get(:@ca_file)).to be_a(Tempfile)
        expect(File.read(@interface.instance_variable_get(:@ca_file).path)).to eq('test_ca_file')
      end
    end
  end
end
```

This RSpec test program covers all the public methods of the `MqttInterface` class and aims to maximize coverage. It includes tests for:

1. Initialization with default and custom values
2. Connection string generation
3. Connecting to the MQTT server
4. Checking connection status
5. Disconnecting from the MQTT server
6. Reading and identifying packets
7. Writing packets to topics
8. Reading from the MQTT client
9. Writing to the MQTT client
10. Setting various options (USERNAME, PASSWORD, CERT, KEY, CA_FILE)

The tests use mocking and stubbing to isolate the `MqttInterface` class and avoid actual network connections. Make sure to have the necessary dependencies (including RSpec and the OpenC3 framework) installed before running these tests.

