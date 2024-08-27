require 'spec_helper'
require 'openc3/interfaces/tcpip_server_interface'
=begin

This test suite covers the specified methods of the TcpipServerInterface class. It includes tests for:

1. connect
2. read_queue_size
3. write_queue_size
4. num_clients
5. start_raw_logging
6. stop_raw_logging
7. change_raw_logging
8. start_listen_thread
9. listen_thread_body
10. start_read_thread
11. check_for_dead_clients
12. write_to_clients

Note that some of these methods are private, so we're using `send` to test them directly. Also, this test suite makes heavy use of mocking and stubbing to isolate the behavior of the TcpipServerInterface class from its dependencies.

To run these tests, you'll need to have RSpec set up in your project and ensure that all the necessary dependencies are available. You may need to adjust some of the test setup based on the actual implementation details of your TcpipServerInterface class and its dependencies.
=end


module OpenC3
  describe TcpipServerInterface do
    before(:each) do
      @interface = TcpipServerInterface.new(8080, 8081, 5.0, 5.0)
    end

    describe "#connect" do
      it "creates listen threads and sets connected to true" do
        expect(@interface).to receive(:start_listen_thread).with(8080, true, false)
        expect(@interface).to receive(:start_listen_thread).with(8081, false, true)
        @interface.connect
        expect(@interface.connected?).to be true
      end
    end

    describe "#read_queue_size" do
      it "returns the size of the read queue" do
        expect(@interface.read_queue_size).to eq(0)
        @interface.instance_variable_get(:@read_queue).push(1)
        expect(@interface.read_queue_size).to eq(1)
      end
    end

    describe "#write_queue_size" do
      it "returns the size of the write queue" do
        expect(@interface.write_queue_size).to eq(0)
        @interface.instance_variable_get(:@write_queue).push(1)
        expect(@interface.write_queue_size).to eq(1)
      end
    end

    describe "#num_clients" do
      it "returns the number of unique clients" do
        interface1 = double("interface1")
        interface2 = double("interface2")
        @interface.instance_variable_set(:@write_interface_infos, [
          TcpipServerInterface::InterfaceInfo.new(interface1, "host1", "1.1.1.1", 8080)
        ])
        @interface.instance_variable_set(:@read_interface_infos, [
          TcpipServerInterface::InterfaceInfo.new(interface2, "host2", "2.2.2.2", 8081)
        ])
        expect(@interface.num_clients).to eq(2)
      end
    end

    describe "#start_raw_logging" do
      it "enables raw logging" do
        @interface.start_raw_logging
        expect(@interface.instance_variable_get(:@raw_logging_enabled)).to be true
      end
    end

    describe "#stop_raw_logging" do
      it "disables raw logging" do
        @interface.stop_raw_logging
        expect(@interface.instance_variable_get(:@raw_logging_enabled)).to be false
      end
    end

    describe "#change_raw_logging" do
      it "changes raw logging state for all interfaces" do
        stream_log_pair = double("stream_log_pair")
        @interface.stream_log_pair = stream_log_pair
        interface_info = double("interface_info")
        allow(interface_info).to receive(:interface).and_return(double("interface", stream_log_pair: stream_log_pair))
        @interface.instance_variable_set(:@write_interface_infos, [interface_info])
        @interface.instance_variable_set(:@read_interface_infos, [interface_info])
        
        expect(stream_log_pair).to receive(:start).twice
        @interface.send(:change_raw_logging, :start)
      end
    end

    describe "#start_listen_thread" do
      it "creates a listen socket and thread" do
        allow(Socket).to receive(:new).and_return(double("socket").as_null_object)
        expect(Thread).to receive(:new)
        @interface.send(:start_listen_thread, 8080, true, false)
      end
    end

    describe "#listen_thread_body" do
      it "accepts connections and creates interface info" do
        socket = double("socket")
        allow(socket).to receive(:accept_nonblock).and_return([double("client_socket"), double("address")])
        allow(Socket).to receive(:unpack_sockaddr_in).and_return([8080, "127.0.0.1"])
        allow(Socket).to receive(:lookup_hostname_from_ip).and_return("localhost")
        
        expect(StreamInterface).to receive(:new).and_return(double("interface").as_null_object)
        @interface.send(:listen_thread_body, socket, true, false, double("thread_reader"))
        expect(@interface.instance_variable_get(:@write_interface_infos).size).to eq(1)
      end
    end

    describe "#start_read_thread" do
      it "creates a read thread for the interface" do
        interface_info = TcpipServerInterface::InterfaceInfo.new(double("interface"), "host", "1.1.1.1", 8080)
        expect(Thread).to receive(:new)
        @interface.send(:start_read_thread, interface_info)
      end
    end

    describe "#check_for_dead_clients" do
      it "removes disconnected clients" do
        interface_info = TcpipServerInterface::InterfaceInfo.new(double("interface", stream: double("stream", write_socket: double("socket"))), "host", "1.1.1.1", 8080)
        @interface.instance_variable_set(:@write_interface_infos, [interface_info])
        allow(interface_info.interface.stream.write_socket).to receive(:recvfrom_nonblock).and_raise(Errno::ECONNRESET)
        @interface.send(:check_for_dead_clients)
        expect(@interface.instance_variable_get(:@write_interface_infos)).to be_empty
      end
    end

    describe "#write_to_clients" do
      it "writes data to all connected clients" do
        interface = double("interface")
        expect(interface).to receive(:write).with("test_data")
        interface_info = TcpipServerInterface::InterfaceInfo.new(interface, "host", "1.1.1.1", 8080)
        @interface.instance_variable_set(:@write_interface_infos, [interface_info])
        @interface.send(:write_to_clients, :write, "test_data")
      end
    end
  end
end
