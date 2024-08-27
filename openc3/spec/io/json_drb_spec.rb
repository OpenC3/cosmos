require 'spec_helper'
require 'openc3/io/json_drb'

=begin
This test suite covers the main functionality of the JsonDRb class, including:

1. Initialization
2. Starting and stopping the service
3. Handling client connections
4. Processing requests
5. Handling various error conditions
6. Request time tracking

To run these tests, you'll need to have RSpec set up in your project and ensure that all necessary dependencies are available. You may need to adjust the `require` statements at the top of the file to match your project structure.

This test suite aims to maximize coverage of the JsonDRb class. However, you may want to add more specific tests based on your particular use cases and any additional functionality not covered in this basic set of tests.
=end

module OpenC3
  describe JsonDRb do
    let(:hostname) { '127.0.0.1' }
    let(:port) { 7777 }
    let(:object) { double('object') }

    subject(:json_drb) { JsonDRb.new }

    describe '#initialize' do
      it 'initializes with default values' do
        expect(json_drb.request_count).to eq(0)
        expect(json_drb.method_whitelist).to be_nil
        expect(json_drb.object).to be_nil
      end
    end

    describe '#num_clients' do
      it 'returns 0 when server is not running' do
        expect(json_drb.num_clients).to eq(0)
      end

      it 'returns the number of connected clients' do
        allow(json_drb).to receive(:@server).and_return(double('server', stats: '{ "backlog": 0, "running": 2 }'))
        expect(json_drb.num_clients).to eq(2)
      end
    end

    describe '#start_service' do
      it 'starts the service with given parameters' do
        expect(Rackup::Handler::Puma).to receive(:run).and_yield(double('server', running: true))
        json_drb.start_service(hostname, port, object)
        expect(json_drb.object).to eq(object)
      end

      it 'raises an error if parameters are incomplete' do
        expect { json_drb.start_service(hostname) }.to raise_error(RuntimeError, "0 or 3 parameters must be given")
      end
    end

    describe '#stop_service' do
      it 'stops the service' do
        allow(OpenC3).to receive(:kill_thread)
        json_drb.instance_variable_set(:@thread, Thread.new {})
        json_drb.stop_service
        expect(json_drb.instance_variable_get(:@thread)).to be_nil
      end
    end

    describe '#add_request_time' do
      it 'adds request time to the list' do
        json_drb.add_request_time(0.1)
        expect(json_drb.instance_variable_get(:@request_times)).to include(0.1)
      end

      it 'sets minimum request time' do
        json_drb.add_request_time(0.00001)
        expect(json_drb.instance_variable_get(:@request_times)).to include(JsonDRb::MINIMUM_REQUEST_TIME)
      end
    end

    describe '#average_request_time' do
      it 'calculates average request time' do
        json_drb.add_request_time(0.1)
        json_drb.add_request_time(0.2)
        expect(json_drb.average_request_time).to be_within(0.001).of(0.15)
      end
    end

    describe '#process_request' do
      let(:request_data) { '{"jsonrpc": "2.0", "method": "test_method", "params": [1, 2], "id": 1}' }
      let(:request_headers) { {} }
      let(:start_time) { Time.now }

      before do
        json_drb.object = object
      end

      it 'processes a valid request' do
        allow(object).to receive(:test_method).and_return("result")
        response_data, error_code = json_drb.process_request(request_data: request_data, request_headers: request_headers, start_time: start_time)
        expect(JSON.parse(response_data)['result']).to eq("result")
        expect(error_code).to be_nil
      end

      it 'handles method not found' do
        allow(object).to receive(:test_method).and_raise(NoMethodError)
        response_data, error_code = json_drb.process_request(request_data: request_data, request_headers: request_headers, start_time: start_time)
        expect(JSON.parse(response_data)['error']['code']).to eq(JsonRpcError::ErrorCode::METHOD_NOT_FOUND)
        expect(error_code).to eq(JsonRpcError::ErrorCode::METHOD_NOT_FOUND)
      end

      it 'handles invalid params' do
        allow(object).to receive(:test_method).and_raise(ArgumentError)
        response_data, error_code = json_drb.process_request(request_data: request_data, request_headers: request_headers, start_time: start_time)
        expect(JSON.parse(response_data)['error']['code']).to eq(JsonRpcError::ErrorCode::INVALID_PARAMS)
        expect(error_code).to eq(JsonRpcError::ErrorCode::INVALID_PARAMS)
      end

      it 'handles unauthorized methods' do
        json_drb.method_whitelist = ['other_method']
        response_data, error_code = json_drb.process_request(request_data: request_data, request_headers: request_headers, start_time: start_time)
        expect(JSON.parse(response_data)['error']['code']).to eq(JsonRpcError::ErrorCode::OTHER_ERROR)
        expect(error_code).to eq(JsonRpcError::ErrorCode::OTHER_ERROR)
      end
    end
  end
end
