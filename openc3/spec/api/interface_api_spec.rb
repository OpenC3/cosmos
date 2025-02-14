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
require 'openc3/utilities/authorization'
require 'openc3/microservices/interface_microservice'
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

      model = InterfaceModel.new(name: "INST_INT", scope: "DEFAULT", target_names: ["INST"], cmd_target_names: ["INST"], tlm_target_names: ["INST"], config_params: ["interface.rb"])
      model.create

      # Mock out some stuff in Microservice initialize()
      dbl = double("AwsS3Client").as_null_object
      allow(Aws::S3::Client).to receive(:new).and_return(dbl)
      allow(Zip::File).to receive(:open).and_return(true)
      allow_any_instance_of(OpenC3::Interface).to receive(:connected?).and_return(true)
      @im_shutdown = false
      allow_any_instance_of(OpenC3::Interface).to receive(:read_interface) { sleep(0.01) until @im_shutdown }

      model = MicroserviceModel.new(name: "DEFAULT__INTERFACE__INST_INT", scope: "DEFAULT", target_names: ["INST"])
      model.create
      @im = InterfaceMicroservice.new("DEFAULT__INTERFACE__INST_INT")
      @im_thread = Thread.new { @im.run }
      sleep 0.01 # Allow the thread to run

      @api = ApiTest.new
    end

    after(:each) do
      @im_shutdown = true
      @im.shutdown
      sleep 0.01
    end

    describe "get_interface" do
      it "returns interface hash" do
        interface = @api.get_interface("INST_INT")
        expect(interface).to be_a Hash
        expect(interface['name']).to eql "INST_INT"
        # Verify it also includes the status
        expect(interface['state']).to eql "CONNECTED"
        expect(interface['clients']).to eql 0
      end
    end

    describe "get_interface_names" do
      it "returns all interface names" do
        model = InterfaceModel.new(name: "INT1", scope: "DEFAULT")
        model.create
        model = InterfaceModel.new(name: "INT2", scope: "DEFAULT")
        model.create
        expect(@api.get_interface_names).to eql ["INST_INT", "INT1", "INT2"]
      end
    end

    describe "connect_interface, disconnect_interface" do
      it "connects the interface" do
        expect(@api.get_interface("INST_INT")['state']).to eql "CONNECTED"
        @api.disconnect_interface("INST_INT")
        sleep 0.01
        expect(@api.get_interface("INST_INT")['state']).to eql "DISCONNECTED"
        @api.connect_interface("INST_INT")
        sleep 0.01
        expect(@api.get_interface("INST_INT")['state']).to eql "ATTEMPTING"
      end
    end

    describe "start_raw_logging_interface" do
      it "should start raw logging on the interface" do
        expect_any_instance_of(OpenC3::Interface).to receive(:start_raw_logging)
        @api.start_raw_logging_interface("INST_INT")
      end

      it "should start raw logging on all interfaces" do
        expect_any_instance_of(OpenC3::Interface).to receive(:start_raw_logging)
        @api.start_raw_logging_interface("ALL")
      end
    end

    describe "stop_raw_logging_interface" do
      it "should stop raw logging on the interface" do
        expect_any_instance_of(OpenC3::Interface).to receive(:stop_raw_logging)
        @api.stop_raw_logging_interface("INST_INT")
      end

      it "should stop raw logging on all interfaces" do
        expect_any_instance_of(OpenC3::Interface).to receive(:stop_raw_logging)
        @api.stop_raw_logging_interface("ALL")
      end
    end

    describe "get_all_interface_info" do
      it "gets interface name and all info" do
        info = @api.get_all_interface_info.sort
        expect(info[0][0]).to eq "INST_INT"
      end
    end

    describe "map_target_to_interface" do
      it "successfully maps a target to an interface" do
        TargetModel.new(name: "INST", scope: "DEFAULT").create
        TargetModel.new(name: "INST2", scope: "DEFAULT").create

        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

        model2 = InterfaceModel.new(name: "INST2_INT", scope: "DEFAULT", target_names: ["INST2"], cmd_target_names: ["INST2"], tlm_target_names: ["INST2"], config_params: ["interface.rb"])
        model2.create

        @api.map_target_to_interface("INST2", "INST_INT")

        model1 = InterfaceModel.get_model(name: "INST_INT", scope: "DEFAULT")
        model2 = InterfaceModel.get_model(name: "INST2_INT", scope: "DEFAULT")

        expect(model1.target_names).to eq ["INST", "INST2"]
        expect(model2.target_names).to eq []
      end
    end

    describe "interface_cmd" do
      it "sends a command to an interface" do
        expect_any_instance_of(OpenC3::Interface).to receive(:interface_cmd).with("cmd1")
        @api.interface_cmd("INST_INT", "cmd1")

        expect_any_instance_of(OpenC3::Interface).to receive(:interface_cmd).with("cmd1", "param1")
        @api.interface_cmd("INST_INT", "cmd1", "param1")
      end
    end

    describe "interface_protocol_cmd" do
      it "sends a command to an interface" do
        expect_any_instance_of(OpenC3::Interface).to receive(:protocol_cmd).with("cmd1", {index: -1, read_write: "READ_WRITE"})
        @api.interface_protocol_cmd("INST_INT", "cmd1")

        expect_any_instance_of(OpenC3::Interface).to receive(:protocol_cmd).with("cmd1", "param1", {index: -1, read_write: "READ_WRITE"})
        @api.interface_protocol_cmd("INST_INT", "cmd1", "param1")
      end
    end
  end
end
