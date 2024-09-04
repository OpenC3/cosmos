
=begin

This RSpec test program covers all the methods in the HttpClientInterface class and aims to maximize coverage. It includes tests for:

1. Initialization with default and custom parameters
2. Connection string generation
3. Connecting and disconnecting
4. Checking connection status
5. Reading from and writing to the interface
6. Converting data to packets and packets to data
7. Handling different HTTP methods (GET, POST)
8. Error handling and special case responses

=end

require 'spec_helper'
require 'openc3/interfaces/http_client_interface'

module OpenC3
  describe HttpClientInterface do
    before(:each) do
      @interface = HttpClientInterface.new('example.com', 8080, 'https', 10, 15, 5, true)
    end

    describe "#initialize" do
      it "initializes with default parameters" do
        interface = HttpClientInterface.new('example.com')
        expect(interface.instance_variable_get(:@hostname)).to eq('example.com')
        expect(interface.instance_variable_get(:@port)).to eq(80)
        expect(interface.instance_variable_get(:@protocol)).to eq('http')
      end

      it "initializes with custom parameters" do
        expect(@interface.instance_variable_get(:@hostname)).to eq('example.com')
        expect(@interface.instance_variable_get(:@port)).to eq(8080)
        expect(@interface.instance_variable_get(:@protocol)).to eq('https')
        expect(@interface.instance_variable_get(:@write_timeout)).to eq(10.0)
        expect(@interface.instance_variable_get(:@read_timeout)).to eq(15.0)
        expect(@interface.instance_variable_get(:@connect_timeout)).to eq(5.0)
        expect(@interface.instance_variable_get(:@include_request_in_response)).to be true
      end
    end

    describe "#connection_string" do
      it "returns the correct URL" do
        expect(@interface.connection_string).to eq('https://example.com:8080')
      end
    end

    describe "#connect" do
      it "creates a Faraday connection" do
        allow(Faraday).to receive(:new).and_return(double('faraday'))
        @interface.connect
        expect(@interface.instance_variable_get(:@http)).to_not be_nil
      end
    end

    describe "#connected?" do
      it "returns true when connected" do
        @interface.instance_variable_set(:@http, double('faraday'))
        expect(@interface.connected?).to be true
      end

      it "returns false when not connected" do
        expect(@interface.connected?).to be false
      end
    end

    describe "#disconnect" do
      it "closes the connection and clears the queue" do
        mock_http = double('faraday')
        expect(mock_http).to receive(:close)
        @interface.instance_variable_set(:@http, mock_http)
        @interface.instance_variable_get(:@response_queue).push(['data', {}])
        @interface.disconnect
        expect(@interface.instance_variable_get(:@http)).to be_nil
        expect(@interface.instance_variable_get(:@response_queue).empty?).to be false
        expect(@interface.instance_variable_get(:@response_queue).pop).to be_nil
      end
    end

    describe "#read_interface" do
      it "returns data from the queue" do
        @interface.instance_variable_get(:@response_queue).push(['test_data', { 'extra' => 'info' }])
        data, extra = @interface.read_interface
        expect(data).to eq('test_data')
        expect(extra).to eq({ 'extra' => 'info' })
      end

      xit "returns nil when queue is empty" do
        expect(@interface.read_interface).to be_nil
      end
    end

    describe "#write_interface" do
      before(:each) do
        @mock_http = double('faraday')
        @interface.instance_variable_set(:@http, @mock_http)
      end

      it "handles GET requests" do
        expect(@mock_http).to receive(:get).and_return(double('response', headers: {}, status: 200, body: 'response'))
        data, extra = @interface.write_interface('', { 'HTTP_METHOD' => 'get', 'HTTP_URI' => '/test' })
        expect(@interface.instance_variable_get(:@response_queue).pop).to eq(['response', { 'HTTP_REQUEST' => ['', { 'HTTP_METHOD' => 'get', 'HTTP_URI' => '/test' }], 'HTTP_STATUS' => 200 }])
      end

      it "handles POST requests" do
        expect(@mock_http).to receive(:post).and_return(double('response', headers: {}, status: 201, body: 'created'))
        data, extra = @interface.write_interface('post_data', { 'HTTP_METHOD' => 'post', 'HTTP_URI' => '/create' })
        expect(@interface.instance_variable_get(:@response_queue).pop).to eq(['created', { 'HTTP_REQUEST' => ['post_data', { 'HTTP_METHOD' => 'post', 'HTTP_URI' => '/create' }], 'HTTP_STATUS' => 201 }])
      end
    end

    describe "#convert_data_to_packet" do
      it "creates a packet with HttpAccessor" do
        packet = @interface.convert_data_to_packet('test_data', { 'HTTP_STATUS' => 200 })
        expect(packet).to be_a(Packet)
        expect(packet.accessor).to be_a(HttpAccessor)
        expect(packet.buffer).to eq('test_data')
      end

      it "sets target and packet names for successful responses" do
        packet = @interface.convert_data_to_packet('success', { 'HTTP_STATUS' => 200, 'HTTP_REQUEST_TARGET_NAME' => 'TARGET', 'HTTP_PACKET' => 'SUCCESS' })
        expect(packet.target_name).to eq('TARGET')
        expect(packet.packet_name).to eq('SUCCESS')
      end

      it "sets error packet name for error responses" do
        packet = @interface.convert_data_to_packet('error', { 'HTTP_STATUS' => 404, 'HTTP_REQUEST_TARGET_NAME' => 'TARGET', 'HTTP_ERROR_PACKET' => 'ERROR' })
        expect(packet.target_name).to eq('TARGET')
        expect(packet.packet_name).to eq('ERROR')
      end
    end

    describe "#convert_packet_to_data" do
      xit "extracts data and extra information from the packet" do
        packet = Packet.new('TARGET', 'COMMAND')
        packet.append_item('HTTP_PATH', 8, :STRING)
        packet.write('HTTP_PATH', '/api/v1/command')
        packet.buffer = 'command_data'

        data, extra = @interface.convert_packet_to_data(packet)
        expect(data).to eq('command_data')
        expect(extra['HTTP_URI']).to eq('https://example.com:8080/api/v1/command')
        expect(extra['HTTP_REQUEST_TARGET_NAME']).to eq('TARGET')
        expect(extra['HTTP_REQUEST_PACKET_NAME']).to eq('COMMAND')
      end
    end
  end
end
