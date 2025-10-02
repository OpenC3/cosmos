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
require 'openc3/interfaces/http_server_interface'
require 'openc3/packets/packet'
require 'openc3/system/system'

module OpenC3
  describe HttpServerInterface do
    before(:all) do
      setup_system()
      @localhost = '127.0.0.1'
      @socket_80 = 80 # make desktop spec not collide with dev/CI env where Cosmos is already running
      begin
        sock = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
        sock.bind(Socket.pack_sockaddr_in(80,  @localhost )) #raise if listening
        sock.close
      rescue Errno::EACCES => e;
        Logger.info("Found listener on port 80; presumably in CI\n#{e.message}")
        @socket_80 = 81
      end
    end

    before(:each) do
      @interface = HttpServerInterface.new(8000+@socket_80)
    end

    after(:each) do
      kill_leftover_threads()
    end

    describe "#initialize" do
      it "initializes with default port" do # above the privileged port range
        expect(@interface.instance_variable_get(:@port)).to eq(8000+@socket_80)
      end

      it "initializes with custom port" do
        interface = HttpServerInterface.new(8000+@socket_80)
        expect(interface.instance_variable_get(:@port)).to eq(8000+@socket_80)
      end
    end

    describe "#set_option" do
      it "sets the listen address" do
        @interface.set_option("LISTEN_ADDRESS", [ @localhost ])
        expect(@interface.instance_variable_get(:@listen_address)).to eq( @localhost )
      end
    end

    describe "#connection_string" do
      it "returns the correct connection string" do
        expect(@interface.connection_string).to eq("listening on 0.0.0.0:#{8000+@socket_80}")
      end
    end

    describe "#connect" do
      it "connects to a web server and mounts routes" do
        allow_any_instance_of(Packet).to receive(:read).with('HTTP_PATH').and_return('/test')
        allow_any_instance_of(Packet).to receive(:read).with('HTTP_STATUS').and_return(200)
        @interface.instance_variable_set(:@port, 8000+@socket_80)
        @interface.connect
        expect(@interface.instance_variable_get(:@server)).to_not be_nil
      end

      it "creates a response hook for every command packet" do
        @interface.target_names = ['INST']
        server_double = double
        allow(WEBrick::HTTPServer).to receive(:new).and_return(server_double)
        request = OpenStruct.new(header: {alpha: "bet"}, query: {what: "is"}, status: nil, body: nil)
        response = OpenStruct.new(status: nil, body: nil)
        allow(server_double).to receive(:mount_proc).with('/test').and_yield(request, response)
        expect(server_double).to receive(:start) do
          sleep(0.1)
        end
        @interface.instance_variable_set(:@port, 8000+@socket_80)
        @interface.connect
        sleep 0.2
      end
    end

    describe "#connected?" do
      it "returns true when server is present" do
        @interface.instance_variable_set(:@server, double('server'))
        expect(@interface.connected?).to be true
      end

      it "returns false when server is not present" do
        expect(@interface.connected?).to be false
      end
    end

    describe "#disconnect" do
      it "shuts down the server and clears the queue" do
        server = double('server')
        expect(server).to receive(:shutdown)
        @interface.instance_variable_set(:@server, server)
        @interface.instance_variable_set(:@request_queue, Queue.new)
        @interface.instance_variable_get(:@request_queue).push("test")
        @interface.disconnect
        expect(@interface.instance_variable_get(:@server)).to be_nil
        expect(@interface.instance_variable_get(:@request_queue).size).to eq(1)
        expect(@interface.instance_variable_get(:@request_queue).pop).to be_nil
      end
    end

    describe "#read_interface" do
      it "reads from the request queue" do
        @interface.instance_variable_set(:@request_queue, Queue.new)
        @interface.instance_variable_get(:@request_queue).push(["data", {}])
        expect(@interface).to receive(:read_interface_base).with("data", {})
        data, extra = @interface.read_interface
        expect(data).to eq("data")
        expect(extra).to eq({})
      end
    end

    describe "#write_interface" do
      it "raises an error" do
        expect { @interface.write_interface({}) }.to raise_error(RuntimeError, "Commands cannot be sent to HttpServerInterface")
      end
    end

    describe "#convert_data_to_packet" do
      it "converts data to a packet" do
        data = "test data"
        extra = {
          'HTTP_REQUEST_TARGET_NAME' => 'TARGET',
          'HTTP_REQUEST_PACKET_NAME' => 'PACKET',
          'EXTRA_INFO' => 'value'
        }
        packet = @interface.convert_data_to_packet(data, extra)
        expect(packet.target_name).to eq('TARGET')
        expect(packet.packet_name).to eq('PACKET')
        expect(packet.buffer).to eq(data)
        expect(packet.extra).to eq({'EXTRA_INFO' => 'value'})
      end
    end

    describe "#convert_packet_to_data" do
      it "raises an error" do
        expect { @interface.convert_packet_to_data(Packet.new('TGT', 'PKT')) }.to raise_error(RuntimeError, "Commands cannot be sent to HttpServerInterface")
      end
    end

    describe "details" do
      it "returns detailed interface information" do
        i = HttpServerInterface.new(8080)
        i.instance_variable_set(:@listen_address, '192.168.1.100')
        i.instance_variable_set(:@request_queue, Queue.new)

        details = i.details

        expect(details).to be_a(Hash)
        expect(details['listen_address']).to eql('192.168.1.100')
        expect(details['port']).to eql(8080)
        expect(details['request_queue_length']).to eql(0)

        # Check that base interface details are included
        expect(details['name']).to eql('HttpServerInterface')
        expect(details).to have_key('read_allowed')
        expect(details).to have_key('write_allowed')
        expect(details).to have_key('options')
      end

      it "shows current request queue length" do
        i = HttpServerInterface.new(8080)
        request_queue = Queue.new
        request_queue.push(['test1', {}])
        request_queue.push(['test2', {}])
        i.instance_variable_set(:@request_queue, request_queue)

        details = i.details

        expect(details['request_queue_length']).to eql(2)
      end

      it "handles default listen address" do
        i = HttpServerInterface.new(8080)
        i.instance_variable_set(:@request_queue, Queue.new)

        details = i.details

        expect(details['listen_address']).to eql('0.0.0.0')
        expect(details['port']).to eql(8080)
      end
    end
  end
end
