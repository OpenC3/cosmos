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
        expect(router['state']).to match(/CONNECTED|ATTEMPTING/)
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

    describe "map_target_to_router" do
      it "successfully maps a single target to a router" do
        TargetModel.new(name: "INST", scope: "DEFAULT").create
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        # Mock the router model's map_target method
        expect_any_instance_of(RouterModel).to receive(:map_target).with("INST2", cmd_only: false, tlm_only: false, unmap_old: true)

        result = @api.map_target_to_router("INST2", "ROUTE_INT")
        expect(result).to be_nil
      end

      it "successfully maps multiple targets to a router" do
        TargetModel.new(name: "INST", scope: "DEFAULT").create
        TargetModel.new(name: "INST2", scope: "DEFAULT").create
        TargetModel.new(name: "INST3", scope: "DEFAULT").create

        # Mock the router model's map_target method for multiple calls
        expect_any_instance_of(RouterModel).to receive(:map_target).with("INST2", cmd_only: false, tlm_only: false, unmap_old: true)
        expect_any_instance_of(RouterModel).to receive(:map_target).with("INST3", cmd_only: false, tlm_only: false, unmap_old: true)

        @api.map_target_to_router(["INST2", "INST3"], "ROUTE_INT")
      end

      it "maps target with cmd_only option" do
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        expect_any_instance_of(RouterModel).to receive(:map_target).with("INST2", cmd_only: true, tlm_only: false, unmap_old: true)

        @api.map_target_to_router("INST2", "ROUTE_INT", cmd_only: true)
      end

      it "maps target with tlm_only option" do
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        expect_any_instance_of(RouterModel).to receive(:map_target).with("INST2", cmd_only: false, tlm_only: true, unmap_old: true)

        @api.map_target_to_router("INST2", "ROUTE_INT", tlm_only: true)
      end

      it "maps target with unmap_old set to false" do
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        expect_any_instance_of(RouterModel).to receive(:map_target).with("INST2", cmd_only: false, tlm_only: false, unmap_old: false)

        @api.map_target_to_router("INST2", "ROUTE_INT", unmap_old: false)
      end

      it "raises error for non-existent router" do
        expect { @api.map_target_to_router("INST", "NONEXISTENT_ROUTER") }.to raise_error(/does not exist/)
      end

      it "returns nil on successful map" do
        TargetModel.new(name: "INST2", scope: "DEFAULT").create
        
        expect_any_instance_of(RouterModel).to receive(:map_target)
        result = @api.map_target_to_router("INST2", "ROUTE_INT")
        
        expect(result).to be_nil
      end
    end

    describe "unmap_target_from_router" do
      it "successfully unmaps a single target from a router" do
        TargetModel.new(name: "INST", scope: "DEFAULT").create
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        # Setup router with multiple targets
        model = RouterModel.get_model(name: "ROUTE_INT", scope: "DEFAULT")
        model.target_names = ["INST", "INST2"]
        model.update

        # Mock the router model's unmap_target method
        expect_any_instance_of(RouterModel).to receive(:unmap_target).with("INST2", cmd_only: false, tlm_only: false)

        @api.unmap_target_from_router("INST2", "ROUTE_INT")
      end

      it "successfully unmaps multiple targets from a router" do
        TargetModel.new(name: "INST", scope: "DEFAULT").create
        TargetModel.new(name: "INST2", scope: "DEFAULT").create
        TargetModel.new(name: "INST3", scope: "DEFAULT").create

        # Setup router with multiple targets
        model = RouterModel.get_model(name: "ROUTE_INT", scope: "DEFAULT")
        model.target_names = ["INST", "INST2", "INST3"]
        model.update

        # Mock the router model's unmap_target method for multiple calls
        expect_any_instance_of(RouterModel).to receive(:unmap_target).with("INST2", cmd_only: false, tlm_only: false)
        expect_any_instance_of(RouterModel).to receive(:unmap_target).with("INST3", cmd_only: false, tlm_only: false)

        @api.unmap_target_from_router(["INST2", "INST3"], "ROUTE_INT")
      end

      it "unmaps target with cmd_only option" do
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        expect_any_instance_of(RouterModel).to receive(:unmap_target).with("INST2", cmd_only: true, tlm_only: false)

        @api.unmap_target_from_router("INST2", "ROUTE_INT", cmd_only: true)
      end

      it "unmaps target with tlm_only option" do
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        expect_any_instance_of(RouterModel).to receive(:unmap_target).with("INST2", cmd_only: false, tlm_only: true)

        @api.unmap_target_from_router("INST2", "ROUTE_INT", tlm_only: true)
      end

      it "raises error for non-existent router" do
        expect { @api.unmap_target_from_router("INST", "NONEXISTENT_ROUTER") }.to raise_error(/does not exist/)
      end

      it "returns nil on successful unmap" do
        TargetModel.new(name: "INST2", scope: "DEFAULT").create
        
        expect_any_instance_of(RouterModel).to receive(:unmap_target)
        result = @api.unmap_target_from_router("INST2", "ROUTE_INT")
        
        expect(result).to be_nil
      end
    end

    describe "router_target_enable" do
      it "enables a target on a router" do
        expect(RouterTopic).to receive(:router_target_enable).with("ROUTE_INT", "INST", cmd_only: false, tlm_only: false, scope: "DEFAULT")
        @api.router_target_enable("ROUTE_INT", "INST")

        expect(RouterTopic).to receive(:router_target_enable).with("ROUTE_INT", "INST", cmd_only: true, tlm_only: false, scope: "DEFAULT")
        @api.router_target_enable("ROUTE_INT", "INST", cmd_only: true)

        expect(RouterTopic).to receive(:router_target_enable).with("ROUTE_INT", "INST", cmd_only: false, tlm_only: true, scope: "DEFAULT")
        @api.router_target_enable("ROUTE_INT", "INST", tlm_only: true)
      end
    end

    describe "router_target_disable" do
      it "disables a target on a router" do
        expect(RouterTopic).to receive(:router_target_disable).with("ROUTE_INT", "INST", cmd_only: false, tlm_only: false, scope: "DEFAULT")
        @api.router_target_disable("ROUTE_INT", "INST")

        expect(RouterTopic).to receive(:router_target_disable).with("ROUTE_INT", "INST", cmd_only: true, tlm_only: false, scope: "DEFAULT")
        @api.router_target_disable("ROUTE_INT", "INST", cmd_only: true)

        expect(RouterTopic).to receive(:router_target_disable).with("ROUTE_INT", "INST", cmd_only: false, tlm_only: true, scope: "DEFAULT")
        @api.router_target_disable("ROUTE_INT", "INST", tlm_only: true)
      end
    end

    describe "router_details" do
      it "gets router details" do
        expect(RouterTopic).to receive(:router_details).with("ROUTE_INT", scope: "DEFAULT")
        @api.router_details("ROUTE_INT")
      end
    end
  end
end
