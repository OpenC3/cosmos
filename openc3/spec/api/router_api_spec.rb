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
require 'openc3/api/router_api'
require 'openc3/script/extract'
require 'openc3/utilities/authorization'
require 'openc3/microservices/router_microservice'
require 'openc3/utilities/aws_bucket'

module OpenC3
  describe Api do
    class ApiTest
      include Extract
      include Api
      include Authorization
    end

    before(:each) do
      mock_redis()
      setup_system()

      model = RouterModel.new(name: "ROUTE_INT", scope: "DEFAULT", target_names: ["INST"], config_params: ["interface.rb"])
      model.create

      # Mock out some stuff in Microservice initialize()
      dbl = double("AwsS3Client").as_null_object
      allow(Aws::S3::Client).to receive(:new).and_return(dbl)
      allow(Zip::File).to receive(:open).and_return(true)
      allow_any_instance_of(OpenC3::Interface).to receive(:connected?).and_return(true)
      @im_shutdown = false
      allow_any_instance_of(OpenC3::Interface).to receive(:read_interface) { sleep(0.01) until @im_shutdown }

      model = MicroserviceModel.new(name: "DEFAULT__INTERFACE__ROUTE_INT", scope: "DEFAULT", target_names: ["INST"])
      model.create
      @im = RouterMicroservice.new("DEFAULT__INTERFACE__ROUTE_INT")
      @im_thread = Thread.new { @im.run }
      sleep(0.01) # Allow the thread to run

      @api = ApiTest.new
    end

    after(:each) do
      @im_shutdown = true
      @im.shutdown
      @im_thread.join()
    end

    describe "get_router" do
      it "returns router hash" do
        router = @api.get_router("ROUTE_INT")
        expect(router).to be_a Hash
        expect(router['name']).to eql "ROUTE_INT"
        # Verify it also includes the status
        expect(router['state']).to eql "CONNECTED"
        expect(router['clients']).to eql 0
      end
    end

    describe "get_router_names" do
      it "returns all router names" do
        model = RouterModel.new(name: "INT1", scope: "DEFAULT")
        model.create
        model = RouterModel.new(name: "INT2", scope: "DEFAULT")
        model.create
        expect(@api.get_router_names).to eql ["INT1", "INT2", "ROUTE_INT"]
      end
    end

    describe "connect_router, disconnect_router" do
      it "connects the router" do
        expect(@api.get_router("ROUTE_INT")['state']).to eql "CONNECTED"
        @api.disconnect_router("ROUTE_INT")
        sleep(0.1)
        expect(@api.get_router("ROUTE_INT")['state']).to eql "DISCONNECTED"
        @api.connect_router("ROUTE_INT")
        sleep(0.1)
        expect(@api.get_router("ROUTE_INT")['state']).to eql "ATTEMPTING"
      end
    end

    describe "start_raw_logging_router" do
      it "should start raw logging on the router" do
        expect_any_instance_of(OpenC3::Interface).to receive(:start_raw_logging)
        @api.start_raw_logging_router("ROUTE_INT")
      end

      it "should start raw logging on all routers" do
        expect_any_instance_of(OpenC3::Interface).to receive(:start_raw_logging)
        @api.start_raw_logging_router("ALL")
      end
    end

    describe "stop_raw_logging_router" do
      it "should stop raw logging on the router" do
        expect_any_instance_of(OpenC3::Interface).to receive(:stop_raw_logging)
        @api.stop_raw_logging_router("ROUTE_INT")
      end

      it "should stop raw logging on all routers" do
        expect_any_instance_of(OpenC3::Interface).to receive(:stop_raw_logging)
        @api.stop_raw_logging_router("ALL")
      end
    end

    describe "get_all_router_info" do
      it "gets router name and all info" do
        info = @api.get_all_router_info.sort
        expect(info[0][0]).to eq "ROUTE_INT"
      end
    end

    describe "router_cmd" do
      it "sends a command to an router_cmd" do
        # Ultimately the router_cmd is still routed to interface_cmd on the interface
        expect_any_instance_of(OpenC3::Interface).to receive(:interface_cmd).with("cmd1")
        @api.router_cmd("ROUTE_INT", "cmd1")

        expect_any_instance_of(OpenC3::Interface).to receive(:interface_cmd).with("cmd1", "param1")
        @api.router_cmd("ROUTE_INT", "cmd1", "param1")
      end
    end

    describe "router_protocol_cmd" do
      it "sends a command to an interface" do
        expect_any_instance_of(OpenC3::Interface).to receive(:protocol_cmd).with("cmd1", {index: -1, read_write: "READ_WRITE"})
        @api.router_protocol_cmd("ROUTE_INT", "cmd1")

        expect_any_instance_of(OpenC3::Interface).to receive(:protocol_cmd).with("cmd1", "param1", {index: -1, read_write: "READ_WRITE"})
        @api.router_protocol_cmd("ROUTE_INT", "cmd1", "param1")
      end
    end
  end
end
