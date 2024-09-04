require 'spec_helper'
require 'openc3/interfaces/http_server_interface'
require 'openc3/packets/packet'
require 'openc3/system/system'

module OpenC3
  describe HttpServerInterface do
    before(:each) do
      @interface = HttpServerInterface.new(8080)
      allow(System).to receive(:commands).and_return(double("commands"))
      allow(System.commands).to receive(:packets).and_return({})
      allow(Logger).to receive(:error)
    end

    describe "#initialize" do
      it "initializes with default values" do
        expect(@interface.instance_variable_get(:@listen_address)).to eq('0.0.0.0')
        expect(@interface.instance_variable_get(:@port)).to eq(8080)
      end
    end

    describe "#set_option" do
      it "sets the listen address" do
        @interface.set_option("LISTEN_ADDRESS", ["127.0.0.1"])
        expect(@interface.instance_variable_get(:@listen_address)).to eq('127.0.0.1')
      end
    end

    describe "#connection_string" do
      it "returns the correct connection string" do
        expect(@interface.connection_string).to eq("listening on 0.0.0.0:8080")
      end
    end

    describe "#connect" do
      it "creates a WEBrick server and mounts routes" do
        allow(WEBrick::HTTPServer).to receive(:new).and_return(double("server").as_null_object)
        allow(@interface).to receive(:super)
        allow(Thread).to receive(:new)

        target_name = "TARGET"
        packet_name = "PACKET"
        packet = double("packet")
        allow(packet).to receive(:restore_defaults)
        allow(packet).to receive(:read).with('HTTP_PATH').and_return("/test")
        allow(packet).to receive(:read).with('HTTP_STATUS').and_return(200)
        allow(packet).to receive(:extra).and_return({'HTTP_HEADERS' => {'Content-Type' => 'application/json'}})
        allow(packet).to receive(:buffer).and_return("test body")
        allow(packet).to receive(:read).with('HTTP_PACKET').and_return("TEST_PACKET")

        allow(System.commands).to receive(:packets).and_return({target_name => {packet_name => packet}})
        allow(@interface).to receive(:target_names).and_return([target_name])

        expect_any_instance_of(WEBrick::HTTPServer).to receive(:mount_proc).with("/test")

        @interface.connect
      end
    end

    describe "#connected?" do
      it "returns true when server is present" do
        @interface.instance_variable_set(:@server, double("server"))
        expect(@interface.connected?).to be true
      end

      it "returns false when server is not present" do
        expect(@interface.connected?).to be false
      end
    end

    describe "#disconnect" do
      it "shuts down the server and clears the request queue" do
        server = double("server")
        expect(server).to receive(:shutdown)
        @interface.instance_variable_set(:@server, server)
        @interface.instance_variable_set(:@request_queue, Queue.new)
        @interface.request_queue.push("test")
        allow(@interface).to receive(:super)

        @interface.disconnect

        expect(@interface.instance_variable_get(:@server)).to be_nil
        expect(@interface.request_queue.size).to eq(1)
        expect(@interface.request_queue.pop).to be_nil
      end
    end

    describe "#read_interface" do
      it "returns data and extra from the request queue" do
        @interface.request_queue.push(["test_data", {"extra" => "info"}])
        allow(@interface).to receive(:read_interface_base)

        data, extra = @interface.read_interface

        expect(data).to eq("test_data")
        expect(extra).to eq({"extra" => "info"})
      end
    end

    describe "#write_interface" do
      it "raises an error" do
        expect { @interface.write_interface({}) }.to raise_error(RuntimeError, "Commands cannot be sent to HttpServerInterface")
      end
    end

    describe "#convert_data_to_packet" do
      it "creates a packet with HttpAccessor" do
        data = "test_data"
        extra = {
          "HTTP_REQUEST_TARGET_NAME" => "TARGET",
          "HTTP_REQUEST_PACKET_NAME" => "PACKET",
          "EXTRA_INFO" => "value"
        }

        packet = @interface.convert_data_to_packet(data, extra)

        expect(packet).to be_a(Packet)
        expect(packet.target_name).to eq("TARGET")
        expect(packet.packet_name).to eq("PACKET")
        expect(packet.accessor).to be_a(HttpAccessor)
        expect(packet.extra).to eq({"EXTRA_INFO" => "value"})
      end
    end

    describe "#convert_packet_to_data" do
      it "raises an error" do
        expect { @interface.convert_packet_to_data(double("packet")) }.to raise_error(RuntimeError, "Commands cannot be sent to HttpServerInterface")
      end
    end
  end
end

