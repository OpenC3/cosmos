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
require 'openc3/interfaces/http_client_interface'

module OpenC3
  describe HttpClientInterface do
    before(:all) do
      @api_resource = '/api/resource'
      @application_json = 'application/json'
      @content_type = 'Content-Type'
      @example_com = 'example.com'
      @packet_data = 'packet data'
    end

    before(:each) do
      @interface = HttpClientInterface.new(@example_com, 8080, 'https', 10, 15, 5, true)
    end

    describe "#initialize" do
      it "sets all the instance variables" do
        i = HttpClientInterface.new('localhost', '8080', 'https', '10', '11', '12')
        expect(i.name).to eql "HttpClientInterface"
        expect(i.instance_variable_get(:@hostname)).to eql 'localhost'
        expect(i.instance_variable_get(:@port)).to eql 8080
      end

      it "initializes with default parameters" do
        interface = HttpClientInterface.new(@example_com)
        expect(interface.instance_variable_get(:@hostname)).to eq(@example_com)
        expect(interface.instance_variable_get(:@port)).to eq(80)
        expect(interface.instance_variable_get(:@protocol)).to eq('http')
      end

      it "initializes with custom parameters" do
        expect(@interface.instance_variable_get(:@hostname)).to eq(@example_com)
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

      it "builds a human readable connection string" do
        i = HttpClientInterface.new('localhost', '80', 'http', '10', '11', '12')
        expect(i.connection_string).to eql "http://localhost"

        i = HttpClientInterface.new('machine', '443', 'https', '10', '11', '12')
        expect(i.connection_string).to eql "https://machine"

        i = HttpClientInterface.new('127.0.0.1', '8080', 'http', '10', '11', '12')
        expect(i.connection_string).to eql "http://127.0.0.1:8080"
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
    end

    describe "#write_interface" do
      before(:each) do
        @mock_http = double('faraday')
        @interface.instance_variable_set(:@http, @mock_http)
      end

      it "handles DELETE requests" do
        data = ""
        extra = {
          'HTTP_METHOD' => 'delete',
          'HTTP_URI' => '/api/resource/1',
          'HTTP_QUERIES' => { 'confirm' => 'true' },
          'HTTP_HEADERS' => { 'Authorization' => 'Bearer token' }
        }

        mock_response = double('response')
        allow(mock_response).to receive(:headers).and_return({})
        allow(mock_response).to receive(:status).and_return(204)
        allow(mock_response).to receive(:body).and_return('')
        expect(@interface.instance_variable_get(:@http)).to receive(:delete) do |args, &block|
          expect(args).to eql "#{@api_resource}/1"
          # Not sure how to test block here
        end.and_return(mock_response)

        @interface.write_interface(data, extra)
        expect(@interface.instance_variable_get(:@response_queue).pop).to eq(['', {
          'HTTP_REQUEST' => [data, extra],
          'HTTP_STATUS' => 204
        }])
      end

      it "handles GET requests" do
        expect(@mock_http).to receive(:get).and_return(double('response', headers: {}, status: 200, body: 'response'))
        data, extra = @interface.write_interface('', { 'HTTP_METHOD' => 'get', 'HTTP_URI' => '/test' })
        expect(@interface.instance_variable_get(:@response_queue).pop).to eq(['response', { 'HTTP_REQUEST' => ['', { 'HTTP_METHOD' => 'get', 'HTTP_URI' => '/test' }], 'HTTP_STATUS' => 200 }])
      end

      it "handles POST requests" do
        data = '{"post": "data"}'
        extra = {
          'HTTP_METHOD' => 'post',
          'HTTP_URI' => @api_resource,
          'HTTP_QUERIES' => { 'param' => 'value' },
          'HTTP_HEADERS' => { @content_type => 'application/json' }
        }

        mock_response = double('response')
        allow(mock_response).to receive(:headers).and_return({@content_type => @application_json})
        allow(mock_response).to receive(:status).and_return(201)
        allow(mock_response).to receive(:body).and_return('{"id": 1}')

        expect(@interface.instance_variable_get(:@http)).to receive(:post)
          .and_yield(double('request').as_null_object)
          .and_return(mock_response)

        @interface.write_interface(data, extra)
        expect(@interface.instance_variable_get(:@response_queue).pop).to eq(['{"id": 1}', {
          'HTTP_REQUEST' => [data, extra],
          'HTTP_HEADERS' => {@content_type => @application_json},
          'HTTP_STATUS' => 201
        }])
      end

      it "handles PUT requests" do
        data = '{"put": "data"}'
        extra = {
          'HTTP_METHOD' => 'put',
          'HTTP_URI' => "#{@api_resource}/1",
          'HTTP_QUERIES' => { 'param' => 'value' },
          'HTTP_HEADERS' => { @content_type => @application_json }
        }

        mock_response = double('response')
        allow(mock_response).to receive(:headers).and_return({@content_type => @application_json})
        allow(mock_response).to receive(:status).and_return(200)
        allow(mock_response).to receive(:body).and_return('{"updated": true}')

        expect(@interface.instance_variable_get(:@http)).to receive(:put)
          .and_yield(double('request').as_null_object)
          .and_return(mock_response)

        @interface.write_interface(data, extra)
        expect(@interface.instance_variable_get(:@response_queue).pop).to eq(['{"updated": true}', {
          'HTTP_REQUEST' => [data, extra],
          'HTTP_HEADERS' => {@content_type => @application_json},
          'HTTP_STATUS' => 200
        }])
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
        packet = @interface.convert_data_to_packet('success', { 'HTTP_STATUS' => 200, 'HTTP_REQUEST' => ['', {'HTTP_REQUEST_TARGET_NAME' => 'TARGET', 'HTTP_PACKET' => 'SUCCESS' }]})
        expect(packet.target_name).to eq('TARGET')
        expect(packet.packet_name).to eq('SUCCESS')
      end

      it "sets error packet name for error responses" do
        packet = @interface.convert_data_to_packet('error', { 'HTTP_STATUS' => 404, 'HTTP_REQUEST' => ['', {'HTTP_REQUEST_TARGET_NAME' => 'TARGET', 'HTTP_ERROR_PACKET' => 'ERROR' }]})
        expect(packet.target_name).to eq('TARGET')
        expect(packet.packet_name).to eq('ERROR')
      end
    end

    describe "#convert_packet_to_data" do
      it "converts a packet to data and extra hash" do
        packet = double('packet')
        allow(packet).to receive(:buffer).and_return( @packet_data )
        allow(packet).to receive(:read).with('HTTP_PATH').and_return(@api_resource)
        allow(packet).to receive(:target_name).and_return('TARGET')
        allow(packet).to receive(:packet_name).and_return('PACKET')
        allow(packet).to receive(:extra).and_return(nil)

        data, extra = @interface.convert_packet_to_data(packet)

        expect(data).to eq( @packet_data )
        expect(extra['HTTP_REQUEST_TARGET_NAME']).to eq('TARGET')
        uri_str = extra['HTTP_URI'].encode('ASCII-8BIT', 'UTF-8')
        expect(uri_str).to eq("https://example.com:8080#{@api_resource}")
      end

      it "preserves existing extra data" do
        packet = double('packet')
        allow(packet).to receive(:buffer).and_return( @packet_data )
        allow(packet).to receive(:read).with('HTTP_PATH').and_return(@api_resource)
        allow(packet).to receive(:target_name).and_return('TARGET')
        allow(packet).to receive(:packet_name).and_return('PACKET')
        allow(packet).to receive(:extra).and_return({'EXISTING' => 'DATA'})

        data, extra = @interface.convert_packet_to_data(packet)

        expect(data).to eq( @packet_data )
        expect(extra['EXISTING']).to eq('DATA')
        uri_str = extra['HTTP_URI'].encode('ASCII-8BIT', 'UTF-8')

        expect(uri_str).to eq("https://example.com:8080#{@api_resource}")
        expect(extra['HTTP_REQUEST_TARGET_NAME']).to eq('TARGET')
      end
    end
  end
end
