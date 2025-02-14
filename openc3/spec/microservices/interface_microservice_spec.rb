# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/api/interface_api'
require 'openc3/script/extract'
require 'openc3/interfaces/interface'
require 'openc3/utilities/authorization'
require 'openc3/microservices/interface_microservice'
require 'openc3/topics/telemetry_decom_topic'

module OpenC3
  describe InterfaceMicroservice do
    before(:each) do
      # This must be here in order to work when running more than this individual file
      class TestInterface < Interface
        def initialize(hostname = "default", port = 12345)
          @hostname = hostname
          @port = port
          @connected = false
          super()
        end

        def read_allowed?
          raise 'test-error' if $read_allowed_raise
          super
        end

        def connection_string
          "#{@hostname}:#{@port}"
        end

        def connect
          sleep 0.001
          super
          @data = "\x00"
          @connected = true
          raise 'test-error' if $connect_raise
        end

        def connected?
          @connected
        end

        def disconnect
          sleep 0.001
          $disconnect_count += 1
          @data = nil # Upon disconnect the read_interface should return nil
          sleep $disconnect_delay
          @connected = false
          super
        end

        def read_interface
          sleep 0.001
          raise 'test-error' if $read_interface_raise
          sleep 0.1
          @data
        end

        def write_interface(data, extra = nil)
          sleep 0.001
          @data = data
        end
      end

      mock_redis()
      setup_system()

      %w(INST).each do |target|
        model = TargetModel.new(folder_name: target, name: target, scope: "DEFAULT")
        model.create
        model.update_store(System.new([target], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      end

      packet = System.telemetry.packet('INST', 'HEALTH_STATUS')
      packet.received_time = Time.now.sys
      packet.stored = false
      packet.check_limits
      TelemetryDecomTopic.write_packet(packet, scope: "DEFAULT")
      sleep(0.01) # Allow the write to happen

      allow(System).to receive(:setup_targets).and_return(nil)
      @interface = double("Interface").as_null_object
      allow(@interface).to receive(:connected?).and_return(true)
      allow(System).to receive(:targets).and_return({ "INST" => @interface })

      model = InterfaceModel.new(name: "INST_INT", scope: "DEFAULT", target_names: ["INST"], cmd_target_names: ["INST"], tlm_target_names: ["INST"], config_params: ["TestInterface"])
      model.create
      model = MicroserviceModel.new(folder_name: "INST", name: "DEFAULT__INTERFACE__INST_INT", scope: "DEFAULT", target_names: ["INST"])
      model.create

      # Initialize the CVT so the setting of the packet_count can work
      System.telemetry.packets("INST").each do |_packet_name, packet|
        json_hash = CvtModel.build_json_from_packet(packet)
        CvtModel.set(json_hash, target_name: packet.target_name, packet_name: packet.packet_name, scope: "DEFAULT")
      end

      class ApiTest
        include Extract
        include Api
        include Authorization
      end
      @api = ApiTest.new

      $connect_raise = false
      $read_allowed_raise = false
      $read_interface_raise = false
      $disconnect_delay = 0
      $disconnect_count = 0
      sleep 0.01
    end

    after(:each) do
      sleep 0.1
      kill_leftover_threads()
    end

    describe "initialize" do
      it "creates an interface, updates status, and starts cmd thread" do
        init_threads = Thread.list.count
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
        config = im.instance_variable_get(:@config)
        expect(config['name']).to eql "DEFAULT__INTERFACE__INST_INT"
        interface = im.instance_variable_get(:@interface)
        expect(interface.name).to eql "INST_INT"
        expect(interface.state).to eql "ATTEMPTING"
        expect(interface.target_names).to eql ["INST"]
        expect(interface.cmd_target_names).to eql ["INST"]
        expect(interface.tlm_target_names).to eql ["INST"]
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["name"]).to eql "INST_INT"
        expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
        # Each interface microservice starts 3 threads: microservice_status_thread in microservice.rb
        # and the InterfaceCmdHandlerThread in interface_microservice.rb
        # and a metrics thread
        expect(Thread.list.count - init_threads).to eql 3

        im.shutdown
        sleep 0.1 # Allow threads to exit
        expect(Thread.list.count).to eql init_threads
      end

      it "preserves existing packet counts" do
        # Initialize the telemetry topic with a non-zero RECEIVED_COUNT
        System.telemetry.packets("INST").each do |_packet_name, packet|
          packet.received_time = Time.now
          packet.received_count = 10
          TelemetryTopic.write_packet(packet, scope: 'DEFAULT')
        end
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
        System.telemetry.packets("INST").each do |_packet_name, packet|
          expect(packet.read("RECEIVED_COUNT")).to eql 10
        end
        im.shutdown
        sleep 0.1 # Allow threads to exit
      end
    end

    describe "run" do
      it "handles exceptions in connect" do
        $connect_raise = true
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
        interface = im.instance_variable_get(:@interface)
        interface.reconnect_delay = 0.01 # Override the reconnect delay to be quick

        capture_io do |stdout|
          Thread.new { im.run }
          sleep 0.01
          expect(stdout.string).to include("Connect default:12345")
          expect(stdout.string).to_not include("Connection Success")
          expect(stdout.string).to include("Connection default:12345 failed due to RuntimeError : test-error")
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"

          $connect_raise = false
          sleep 0.01 # Allow it to reconnect successfully
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["INST_INT"]["state"]).to eql "CONNECTED"
          im.shutdown
        end
      end

      it "handles exceptions while reading" do
        $read_interface_raise = true
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql("ATTEMPTING")
        interface = im.instance_variable_get(:@interface)
        interface.reconnect_delay = 0.01 # Override the reconnect delay to be quick
        capture_io do |stdout|
          Thread.new { im.run }
          sleep 0.01
          expect(stdout.string).to include("Connect default:12345")
          expect(stdout.string).to include("Connection Success")
          expect(stdout.string).to include("Connection Lost: RuntimeError : test-error")

          $read_interface_raise = false
          sleep 0.01 # Allow to reconnect
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["INST_INT"]["state"]).to eql "CONNECTED"
          im.shutdown
        end
      end

      it "sends a command to the interface" do
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql("ATTEMPTING")

        expect(CommandDecomTopic).to receive(:write_packet) do |command, scope|
          expect(command.target_name).to eql("INST")
          expect(command.packet_name).to eql("ABORT")
          expect(scope).to eql({:scope => "DEFAULT"})
        end
        Thread.new { im.run }
        sleep 0.01
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "CONNECTED"

        @api.cmd("INST", "ABORT")
        sleep 0.01
        im.shutdown
      end
    end

    describe "connect" do
      it "handles parameters" do
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
        sleep 0.01
        interface = im.instance_variable_get(:@interface)
        interface.reconnect_delay = 0.01 # Override the reconnect delay to be quick
        expect(interface.instance_variable_get(:@hostname)).to eql 'default'
        expect(interface.instance_variable_get(:@port)).to eql 12345

        capture_io do |stdout|
          Thread.new { im.run }
          sleep 0.01
          expect(stdout.string).to include("Connect default:12345")
          expect(stdout.string).to include("Connection Success")
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["INST_INT"]["state"]).to eql "CONNECTED"
        end

        # Expect the interface double to have interface= called on it to set the new interface
        expect(@interface).to receive(:interface=)
        capture_io do |stdout|
          InterfaceTopic.connect_interface("INST_INT", 'test-host', 54321, scope: 'DEFAULT')
          sleep 0.2
          expect(stdout.string).to include("Connection Lost")
          expect(stdout.string).to include("Connect test-host:54321")
          expect(stdout.string).to include("Connection Success")
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["INST_INT"]["state"]).to eql "CONNECTED"
        end

        interface = im.instance_variable_get(:@interface)
        expect(interface.instance_variable_get(:@hostname)).to eql 'test-host'
        expect(interface.instance_variable_get(:@port)).to eql 54321
        im.shutdown
      end
    end

    it "handles exceptions in monitor thread" do
      $read_allowed_raise = true
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.reconnect_delay = 0.01 # Override the reconnect delay to be quick

      # Mock this because it calls exit which breaks SimpleCov
      allow(OpenC3).to receive(:handle_fatal_exception) do |exception, _message|
        expect(exception.message).to eql "test-error"
      end

      capture_io do |stdout|
        Thread.new { im.run }

        sleep 0.1 # Allow to start and immediately crash
        expect(stdout.string).to include("RuntimeError")

        sleep 0.2 # Give it time but it shouldn't connect
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to match(/DISCONNECTED|ATTEMPTING/)
        im.shutdown
      end
    end

    it "handles a clean disconnect" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.reconnect_delay = 0.01 # Override the reconnect delay to be quick

      capture_io do |stdout|
        Thread.new { im.run }
        sleep 0.01 # Allow to start
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "CONNECTED"
        expect(stdout.string).to include("Connect default:12345")
        expect(stdout.string).to include("Connection Success")

        @api.disconnect_interface("INST_INT")
        sleep 0.1 # Allow disconnect
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "DISCONNECTED"
        expect(stdout.string).to include("Disconnect requested")
        expect(stdout.string).to include("Connection Lost")

        # Wait and verify still DISCONNECTED and not ATTEMPTING
        sleep 0.2
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "DISCONNECTED"
        expect($disconnect_count).to eql 1

        im.shutdown
      end
    end

    it "handles long disconnect delays" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.reconnect_delay = 0.01 # Override the reconnect delay to be quick

      capture_io do |stdout|
        Thread.new { im.run }
        sleep 0.01 # Allow to start
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "CONNECTED"
        expect(stdout.string).to include("Connect default:12345")
        expect(stdout.string).to include("Connection Success")

        $disconnect_delay = 0.01
        @api.disconnect_interface("INST_INT")
        sleep 0.1 # Allow disconnect
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "DISCONNECTED"
        expect(stdout.string).to include("Disconnect requested")
        expect(stdout.string).to include("Connection Lost")

        # Wait and verify still DISCONNECTED and not ATTEMPTING
        sleep 0.2
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "DISCONNECTED"
        expect($disconnect_count).to eql 1

        im.shutdown
      end
    end

    it "handles a interface that doesn't allow reads" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.instance_variable_set(:@read_allowed, false)

      capture_io do |stdout|
        # Shouldn't cause error because read_interface shouldn't be called
        $read_interface_raise = true
        Thread.new { im.run }
        sleep 0.01 # Allow to start
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "CONNECTED"
        expect(stdout.string).to include("Connect default:12345")
        expect(stdout.string).to include("Connection Success")
        expect(stdout.string).to include("Starting connection maintenance")

        @api.disconnect_interface("INST_INT")
        sleep 1.1 # Allow disconnect and wait for @interface_thread_sleeper.sleep(1)
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "DISCONNECTED"
        expect(stdout.string).to match(/Disconnect requested/m)
        expect(stdout.string).to match(/Connection Lost/m)

        # Wait and verify still DISCONNECTED and not ATTEMPTING
        sleep 0.2
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["INST_INT"]["state"]).to eql "DISCONNECTED"
        expect($disconnect_count).to eql 1

        im.shutdown
      end
    end

    it "supports inject_tlm" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"

      Thread.new { im.run }
      sleep 0.01 # Allow to start
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "CONNECTED"

      Topic.update_topic_offsets(["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"])
      @api.inject_tlm("INST", "HEALTH_STATUS", { TEMP1: 10 }, type: :RAW)
      sleep 0.1
      packets = Topic.read_topics(["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"])
      expect(packets.length).to eql 1
      msg_hash = packets["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"][0][1]
      packet = System.telemetry.packet("INST", "HEALTH_STATUS")
      packet.stored = ConfigParser.handle_true_false(msg_hash["stored"])
      packet.received_time = Time.from_nsec_from_epoch(msg_hash["received_time"].to_i)
      packet.received_count = msg_hash["received_count"].to_i
      packet.buffer = msg_hash["buffer"]
      expect(packet.read("TEMP1", :RAW)).to eql 10
      im.shutdown
    end

    it "supports interface_cmd" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      expect(interface).to receive(:interface_cmd).with("DO_THE_THING", "PARAM1", 2)

      Thread.new { im.run }
      sleep 0.01 # Allow to start
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "CONNECTED"

      @api.interface_cmd("INST_INT", "DO_THE_THING", "PARAM1", 2, scope: "DEFAULT")
      im.shutdown
    end

    it "supports protocol_cmd" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      expect(interface).to receive(:protocol_cmd).with("DO_THE_OTHER_THING", "PARAM1", 2, {:index => -1, :read_write => "READ_WRITE"})

      Thread.new { im.run }
      sleep 0.01 # Allow to start
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["INST_INT"]["state"]).to eql "CONNECTED"

      @api.interface_protocol_cmd("INST_INT", "DO_THE_OTHER_THING", "PARAM1", 2, scope: "DEFAULT")
      im.shutdown
    end
  end
end
