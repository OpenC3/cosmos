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

require 'spec_helper'
require 'openc3/api/interface_api'
require 'openc3/script/extract'
require 'openc3/interfaces/interface'
require 'openc3/utilities/authorization'
require 'openc3/microservices/interface_microservice'

module OpenC3
  describe InterfaceMicroservice do
    class ApiTest
      include Extract
      include Api
      include Authorization
    end

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
    end

    before(:each) do
      mock_redis()
      setup_system()

      allow(System).to receive(:setup_targets).and_return(nil)
      @interface = double("Interface").as_null_object
      allow(@interface).to receive(:connected?).and_return(true)
      allow(System).to receive(:targets).and_return({ "TEST" => @interface })

      model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT", target_names: ["TEST"], config_params: ["TestInterface"])
      model.create
      model = MicroserviceModel.new(folder_name: "TEST", name: "DEFAULT__INTERFACE__TEST_INT", scope: "DEFAULT", target_names: ["TEST"])
      model.create

      @api = ApiTest.new

      $connect_raise = false
      $read_allowed_raise = false
      $read_interface_raise = false
      $disconnect_delay = 0
      $disconnect_count = 0
    end

    after(:each) do
      sleep 0.1
      kill_leftover_threads
    end

    describe "initialize" do
      it "creates an interface, updates status, and starts cmd thread" do
        init_threads = Thread.list.count
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
        config = im.instance_variable_get(:@config)
        expect(config['name']).to eql "DEFAULT__INTERFACE__TEST_INT"
        interface = im.instance_variable_get(:@interface)
        expect(interface.name).to eql "TEST_INT"
        expect(interface.state).to eql "ATTEMPTING"
        expect(interface.target_names).to eql ["TEST"]
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["name"]).to eql "TEST_INT"
        expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
        # Each interface microservice starts 2 threads: microservice_status_thread in microservice.rb
        # and the InterfaceCmdHandlerThread in interface_microservice.rb
        expect(Thread.list.count - init_threads).to eql 2

        im.shutdown
        sleep 0.1 # Allow threads to exit
        expect(Thread.list.count).to eql init_threads
      end
    end

    describe "run" do
      it "handles exceptions in connect" do
        $connect_raise = true
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
        interface = im.instance_variable_get(:@interface)
        interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

        capture_io do |stdout|
          im_thread = Thread.new { im.run }
          sleep 1
          expect(stdout.string).to include("Connecting ...")
          expect(stdout.string).to_not include("Connection Success")
          expect(stdout.string).to include("Connection Failed: RuntimeError : test-error")
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"

          $connect_raise = false
          sleep 1 # Allow it to reconnect successfully
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["TEST_INT"]["state"]).to eql "CONNECTED"
          im.shutdown
        end
      end

      it "handles exceptions while reading" do
        $read_interface_raise = true
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
        interface = im.instance_variable_get(:@interface)
        interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

        capture_io do |stdout|
          im_thread = Thread.new { im.run }
          sleep 1
          expect(stdout.string).to include("Connecting ...")
          expect(stdout.string).to include("Connection Success")
          expect(stdout.string).to include("Connection Lost: RuntimeError : test-error")
          expect($disconnect_count).to eql 1

          $read_interface_raise = false
          sleep 1 # Allow to reconnect
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["TEST_INT"]["state"]).to eql "CONNECTED"
          im.shutdown
        end
      end
    end

    describe "connect" do
      it "handles parameters" do
        im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
        interface = im.instance_variable_get(:@interface)
        interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick
        expect(interface.instance_variable_get(:@hostname)).to eql 'default'
        expect(interface.instance_variable_get(:@port)).to eql 12345

        capture_io do |stdout|
          im_thread = Thread.new { im.run }
          sleep 1
          expect(stdout.string).to include("Connecting ...")
          expect(stdout.string).to include("Connection Success")
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["TEST_INT"]["state"]).to eql "CONNECTED"
        end

        # Expect the interface double to have interface= called on it to set the new interface
        expect(@interface).to receive(:interface=)
        capture_io do |stdout|
          InterfaceTopic.connect_interface("TEST_INT", 'test-host', 54321, scope: 'DEFAULT')
          sleep 1
          expect(stdout.string).to include("Connection Lost")
          expect(stdout.string).to include("Connecting ...")
          expect(stdout.string).to include("Connection Success")
          all = InterfaceStatusModel.all(scope: "DEFAULT")
          expect(all["TEST_INT"]["state"]).to eql "CONNECTED"
        end

        interface = im.instance_variable_get(:@interface)
        expect(interface.instance_variable_get(:@hostname)).to eql 'test-host'
        expect(interface.instance_variable_get(:@port)).to eql 54321
        im.shutdown
      end
    end

    it "handles exceptions in monitor thread" do
      $read_allowed_raise = true
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

      capture_io do |stdout|
        im_thread = Thread.new { im.run }
        sleep 0.1 # Allow to start and immediately crash
        expect(stdout.string).to include("RuntimeError")

        sleep 1 # Give it time but it shouldn't connect
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
        expect(im_thread.alive?).to be true

        im.shutdown
      end
    end

    it "handles a clean disconnect" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

      capture_io do |stdout|
        im_thread = Thread.new { im.run }
        sleep 0.5 # Allow to start
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "CONNECTED"
        expect(stdout.string).to include("Connecting ...")
        expect(stdout.string).to include("Connection Success")

        @api.disconnect_interface("TEST_INT")
        sleep 1 # Allow disconnect
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "DISCONNECTED"
        expect(stdout.string).to include("Disconnect requested")
        expect(stdout.string).to include("Connection Lost")

        # Wait and verify still DISCONNECTED and not ATTEMPTING
        sleep 0.5
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "DISCONNECTED"
        expect($disconnect_count).to eql 1

        im.shutdown
      end
    end

    it "handles long disconnect delays" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.reconnect_delay = 0.1 # Override the reconnect delay to be quick

      capture_io do |stdout|
        im_thread = Thread.new { im.run }
        sleep 0.5 # Allow to start
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "CONNECTED"
        expect(stdout.string).to include("Connecting ...")
        expect(stdout.string).to include("Connection Success")

        $disconnect_delay = 0.5
        @api.disconnect_interface("TEST_INT")
        sleep 1 # Allow disconnect
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "DISCONNECTED"
        expect(stdout.string).to include("Disconnect requested")
        expect(stdout.string).to include("Connection Lost")

        # Wait and verify still DISCONNECTED and not ATTEMPTING
        sleep 0.5
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "DISCONNECTED"
        expect($disconnect_count).to eql 1

        im.shutdown
      end
    end

    it "handles a interface that doesn't allow reads" do
      im = InterfaceMicroservice.new("DEFAULT__INTERFACE__TEST_INT")
      all = InterfaceStatusModel.all(scope: "DEFAULT")
      expect(all["TEST_INT"]["state"]).to eql "ATTEMPTING"
      interface = im.instance_variable_get(:@interface)
      interface.instance_variable_set(:@read_allowed, false)

      capture_io do |stdout|
        # Shouldn't cause error because read_interface shouldn't be called
        $read_interface_raise = true
        im_thread = Thread.new { im.run }
        sleep 0.5 # Allow to start
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "CONNECTED"
        expect(stdout.string).to include("Connecting ...")
        expect(stdout.string).to include("Connection Success")
        expect(stdout.string).to include("Starting connection maintenance")

        @api.disconnect_interface("TEST_INT")
        sleep 2 # Allow disconnect and wait for @interface_thread_sleeper.sleep(1)
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "DISCONNECTED"
        expect(stdout.string).to match(/Disconnect requested/m)
        expect(stdout.string).to match(/Connection Lost/m)

        # Wait and verify still DISCONNECTED and not ATTEMPTING
        sleep 0.5
        all = InterfaceStatusModel.all(scope: "DEFAULT")
        expect(all["TEST_INT"]["state"]).to eql "DISCONNECTED"
        expect($disconnect_count).to eql 1

        im.shutdown
      end
    end
  end
end
