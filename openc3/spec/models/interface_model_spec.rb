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
require 'openc3/models/interface_model'

module OpenC3
  describe InterfaceModel do
    before(:each) do
      mock_redis()
    end

    describe "self.get" do
      it "returns the specified interface" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT",
                                   connect_on_startup: false, auto_reconnect: false) # Set a few things to check
        model.create
        model = InterfaceModel.new(name: "SPEC_INT", scope: "DEFAULT",
                                   connect_on_startup: true, auto_reconnect: true) # Set to opposite of TEST_INT
        model.create
        test = InterfaceModel.get(name: "TEST_INT", scope: "DEFAULT")
        expect(test["name"]).to eq "TEST_INT"
        expect(test["connect_on_startup"]).to be false
        expect(test["auto_reconnect"]).to be false
      end

      it "works with same named routers" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT",
                                   connect_on_startup: false, auto_reconnect: false) # Set a few things to check
        model.create
        model = RouterModel.new(name: "TEST_INT", scope: "DEFAULT",
                                connect_on_startup: true, auto_reconnect: true) # Set to opposite
        model.create
        test = InterfaceModel.get(name: "TEST_INT", scope: "DEFAULT")
        expect(test["name"]).to eq "TEST_INT"
        expect(test["connect_on_startup"]).to be false
        expect(test["auto_reconnect"]).to be false
        test = RouterModel.get(name: "TEST_INT", scope: "DEFAULT")
        expect(test["name"]).to eq "TEST_INT"
        expect(test["connect_on_startup"]).to be true
        expect(test["auto_reconnect"]).to be true
      end
    end

    describe "self.names" do
      it "returns all interface names" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")
        model.create
        model = InterfaceModel.new(name: "SPEC_INT", scope: "DEFAULT")
        model.create
        model = InterfaceModel.new(name: "OTHER_INT", scope: "OTHER")
        model.create
        names = InterfaceModel.names(scope: "DEFAULT")
        # contain_exactly doesn't care about ordering and neither do we
        expect(names).to contain_exactly("TEST_INT", "SPEC_INT")
        names = InterfaceModel.names(scope: "OTHER")
        expect(names).to contain_exactly("OTHER_INT")
      end
    end

    describe "self.all" do
      it "returns all the parsed interfaces" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT",
                                   connect_on_startup: false, auto_reconnect: false) # Set a few things to check
        model.create
        model = InterfaceModel.new(name: "SPEC_INT", scope: "DEFAULT",
                                   connect_on_startup: true, auto_reconnect: true) # Set to opposite of TEST_INT
        model.create
        all = InterfaceModel.all(scope: "DEFAULT")
        expect(all.keys).to contain_exactly("TEST_INT", "SPEC_INT")
        expect(all["TEST_INT"]["connect_on_startup"]).to be false
        expect(all["TEST_INT"]["auto_reconnect"]).to be false
        expect(all["SPEC_INT"]["connect_on_startup"]).to be true
        expect(all["SPEC_INT"]["auto_reconnect"]).to be true
      end
    end

    describe "self.handle_config" do
      it "only recognizes INTERFACE" do
        parser = double("ConfigParser").as_null_object
        expect(parser).to receive(:verify_num_parameters)
        InterfaceModel.handle_config(parser, "INTERFACE", ["TEST_INT"], scope: "DEFAULT")
        expect { InterfaceModel.handle_config(parser, "ROUTER", ["TEST_INT"], scope: "DEFAULT") }.to raise_error(ConfigParser::Error)
      end
    end

    describe "initialize" do
      it "requires name and scope" do
        expect { InterfaceModel.new(name: "TEST_INT") }.to raise_error(ArgumentError)
        expect { InterfaceModel.new(scope: "TEST_INT") }.to raise_error(ArgumentError)
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")
        expect(model.name).to eql "TEST_INT"
      end
    end

    describe "create" do
      it "stores model based on scope and class name" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")
        model.create
        keys = Store.scan(0)
        # This is an implementation detail but Redis keys are pretty critical so test it
        expect(keys[1]).to include("DEFAULT__openc3_interfaces").at_most(1).times
        # 21/07/2021 - G this needed to be changed to contain OPENC3__TOKEN
      end
    end

    describe "handle_config" do
      it "raise on unknown keywords" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")
        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts "UNKNOWN"
        tf.close
        parser.parse_file(tf.path) do |keyword, params|
          expect { model.handle_config(parser, keyword, params) }.to raise_error(/Unknown keyword/)
        end
        tf.unlink
      end

      it "raise on badly formatted keywords" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")
        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts "PROTOCOL OTHER ReadProtocol"
        tf.close
        parser.parse_file(tf.path) do |keyword, params|
          expect { model.handle_config(parser, keyword, params) }.to raise_error("Invalid protocol type: OTHER")
        end
        tf.unlink
      end

      it "parses tool specific keywords" do
        TargetModel.new(name: "TARGET1", scope: "DEFAULT").create
        TargetModel.new(name: "TARGET2", scope: "DEFAULT").create
        TargetModel.new(name: "TARGET3", scope: "DEFAULT").create
        TargetModel.new(name: "TARGET4", scope: "DEFAULT").create
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")

        parser = ConfigParser.new
        tf = Tempfile.new
        tf.puts "MAP_TARGET TARGET1"
        tf.puts "MAP_TARGET TARGET2"
        tf.puts "MAP_CMD_TARGET TARGET3"
        tf.puts "MAP_TLM_TARGET TARGET4"
        tf.puts "DONT_CONNECT"
        tf.puts "DONT_RECONNECT"
        tf.puts "RECONNECT_DELAY 10"
        tf.puts "DISABLE_DISCONNECT"
        tf.puts "OPTION NAME1 VALUE1"
        tf.puts "OPTION NAME2 VALUE2"
        tf.puts "PROTOCOL READ ReadProtocol 1 2 3"
        tf.puts "PROTOCOL WRITE WriteProtocol"
        tf.puts "DONT_LOG"
        tf.puts "LOG_STREAM"
        tf.close
        parser.parse_file(tf.path) do |keyword, params|
          model.handle_config(parser, keyword, params)
        end
        json = model.as_json(:allow_nan => true)
        expect(json['target_names']).to include("TARGET1", "TARGET2", "TARGET3", "TARGET4")
        expect(json['cmd_target_names']).to include("TARGET1", "TARGET2", "TARGET3")
        expect(json['tlm_target_names']).to include("TARGET1", "TARGET2", "TARGET4")
        expect(json['connect_on_startup']).to be false
        expect(json['auto_reconnect']).to be false
        expect(json['reconnect_delay']).to eql 10.0
        expect(json['disable_disconnect']).to be true
        expect(json['options']).to include(["NAME1", "VALUE1"], ["NAME2", "VALUE2"])
        expect(json['protocols']).to include(["READ", "ReadProtocol", "1", "2", "3"], ["WRITE", "WriteProtocol"])
        expect(json['log']).to be false
        expect(json['log_stream']).to eq []
        tf.unlink
      end
    end

    describe "build" do
      it "instantiates the interface" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT", config_params: ["interface.rb"])
        interface = model.build
        expect(interface.class).to eq Interface
        expect(interface.stream_log_pair).to be nil
        # Now instantiate a more complex option
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT",
                                   config_params: %w(tcpip_client_interface.rb 127.0.0.1 8080 8081 10.0 nil BURST 4 0xDEADBEEF))
        interface = model.build
        expect(interface.class).to eq TcpipClientInterface
      end
    end

    describe "as_json" do
      it "encodes all the input parameters" do
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT")
        json = model.as_json(:allow_nan => true)
        # Check the defaults
        expect(json['name']).to eq "TEST_INT"
        expect(json['config_params']).to eq []
        expect(json['target_names']).to eq []
        expect(json['cmd_target_names']).to eq []
        expect(json['tlm_target_names']).to eq []
        expect(json['connect_on_startup']).to eq true
        expect(json['auto_reconnect']).to eq true
        expect(json['reconnect_delay']).to eq 5.0
        expect(json['disable_disconnect']).to eq false
        expect(json['options']).to eq []
        expect(json['secret_options']).to eq []
        expect(json['protocols']).to eq []
        expect(json['log']).to eq true
        expect(json['log_stream']).to eq nil
        expect(json['plugin']).to eq nil
        expect(json['needs_dependencies']).to eq false
        expect(json['secrets']).to eq []

        params = model.method(:initialize).parameters
        params.each do |type, name|
          # Scope isn't included in as_json as it is part of the key used to get the model
          next if name == :scope

          expect(json.key?(name.to_s)).to be true
        end
      end
    end

    describe "deploy, undeploy" do
      it "creates and deploys a MicroserviceModel" do
        dir = Dir.pwd
        variables = { "test" => "example" }

        intmodel = double(InterfaceStatusModel)
        expect(intmodel).to receive(:destroy)
        expect(InterfaceStatusModel).to receive(:get_model).and_return(intmodel)
        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:create)
        expect(umodel).to receive(:deploy).with(dir, variables)
        expect(umodel).to receive(:destroy)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel)
        expect(MicroserviceModel).to receive(:new).and_return(umodel)
        model = InterfaceModel.new(name: "TEST_INT", scope: "DEFAULT", plugin: "PLUG")
        model.create
        model.deploy(dir, variables)
        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'created'
        expect(config[0][1]['type']).to eql 'interface'
        expect(config[0][1]['name']).to eql 'TEST_INT'
        expect(config[0][1]['plugin']).to eql 'PLUG'

        model.undeploy
        config = ConfigTopic.read(scope: 'DEFAULT')
        expect(config[0][1]['kind']).to eql 'deleted'
        expect(config[0][1]['type']).to eql 'interface'
        expect(config[0][1]['name']).to eql 'TEST_INT'
        expect(config[0][1]['plugin']).to eql 'PLUG'
      end
    end

    describe "map_target, unmap_target" do
      before(:each) do
        TargetModel.new(name: "TARGET1", scope: "DEFAULT").create
        TargetModel.new(name: "TARGET2", scope: "DEFAULT").create
        TargetModel.new(name: "TARGET3", scope: "DEFAULT").create
        TargetModel.new(name: "TARGET4", scope: "DEFAULT").create
        InterfaceModel.new(name: "TEST1_INT", scope: "DEFAULT", plugin: "PLUG", target_names: ["TARGET1", "TARGET2"], cmd_target_names: ["TARGET1"], tlm_target_names: ["TARGET2"]).create
        InterfaceModel.new(name: "TEST2_INT", scope: "DEFAULT", plugin: "PLUG", target_names: ["TARGET3", "TARGET4"], cmd_target_names: ["TARGET3", "TARGET4"], tlm_target_names: ["TARGET3", "TARGET4"]).create
        InterfaceModel.new(name: "TEST3_INT", scope: "DEFAULT", plugin: "PLUG", target_names: ["TARGET1", "TARGET2"], cmd_target_names: ["TARGET2"], tlm_target_names: ["TARGET1"]).create
      end

      it "should complain about unknown targets" do
        model1 = InterfaceModel.get_model(name: "TEST1_INT", scope: "DEFAULT")
        expect { model1.map_target("TARGET5") }.to raise_error(RuntimeError, "Target TARGET5 does not exist")

        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)
        expect { model1.unmap_target("TARGET5") }.not_to raise_error # Unmap doesn't care
      end

      it "should unmap targets from other interfaces by default" do
        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model2.map_target("TARGET1")

        model1 = InterfaceModel.get_model(name: "TEST1_INT", scope: "DEFAULT")
        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model3 = InterfaceModel.get_model(name: "TEST3_INT", scope: "DEFAULT")

        expect(model1.target_names).to eq ["TARGET2"]
        expect(model1.cmd_target_names).to eq []
        expect(model1.tlm_target_names).to eq ["TARGET2"]
        expect(model2.target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.cmd_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.tlm_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model3.target_names).to eq ["TARGET2"]
        expect(model3.cmd_target_names).to eq ["TARGET2"]
        expect(model3.tlm_target_names).to eq []
      end

      it "should unmap cmd targets from other interfaces by default" do
        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model2.map_target("TARGET1", cmd_only: true)

        model1 = InterfaceModel.get_model(name: "TEST1_INT", scope: "DEFAULT")
        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model3 = InterfaceModel.get_model(name: "TEST3_INT", scope: "DEFAULT")

        expect(model1.target_names).to eq ["TARGET2"]
        expect(model1.cmd_target_names).to eq []
        expect(model1.tlm_target_names).to eq ["TARGET2"]
        expect(model2.target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.cmd_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.tlm_target_names).to eq ["TARGET3", "TARGET4"]
        expect(model3.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model3.cmd_target_names).to eq ["TARGET2"]
        expect(model3.tlm_target_names).to eq ["TARGET1"]
      end

      it "should unmap tlm targets from other interfaces by default" do
        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model2.map_target("TARGET1", tlm_only: true)

        model1 = InterfaceModel.get_model(name: "TEST1_INT", scope: "DEFAULT")
        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model3 = InterfaceModel.get_model(name: "TEST3_INT", scope: "DEFAULT")

        expect(model1.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model1.cmd_target_names).to eq ["TARGET1"]
        expect(model1.tlm_target_names).to eq ["TARGET2"]
        expect(model2.target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.cmd_target_names).to eq ["TARGET3", "TARGET4"]
        expect(model2.tlm_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model3.target_names).to eq ["TARGET2"]
        expect(model3.cmd_target_names).to eq ["TARGET2"]
        expect(model3.tlm_target_names).to eq []
      end

      it "should not unmap targets from other interfaces if disabled" do
        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model2.map_target("TARGET1", unmap_old: false)

        model1 = InterfaceModel.get_model(name: "TEST1_INT", scope: "DEFAULT")
        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model3 = InterfaceModel.get_model(name: "TEST3_INT", scope: "DEFAULT")

        expect(model1.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model1.cmd_target_names).to eq ["TARGET1"]
        expect(model1.tlm_target_names).to eq ["TARGET2"]
        expect(model2.target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.cmd_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.tlm_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model3.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model3.cmd_target_names).to eq ["TARGET2"]
        expect(model3.tlm_target_names).to eq ["TARGET1"]
      end

      it "should not unmap cmd targets from other interfaces if disabled" do
        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model2.map_target("TARGET1", cmd_only: true, unmap_old: false)

        model1 = InterfaceModel.get_model(name: "TEST1_INT", scope: "DEFAULT")
        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model3 = InterfaceModel.get_model(name: "TEST3_INT", scope: "DEFAULT")

        expect(model1.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model1.cmd_target_names).to eq ["TARGET1"]
        expect(model1.tlm_target_names).to eq ["TARGET2"]
        expect(model2.target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.cmd_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.tlm_target_names).to eq ["TARGET3", "TARGET4"]
        expect(model3.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model3.cmd_target_names).to eq ["TARGET2"]
        expect(model3.tlm_target_names).to eq ["TARGET1"]
      end

      it "should not unmap tlm targets from other interfaces if disabled" do
        # double MicroserviceModel because we're not testing that here
        umodel = double(MicroserviceModel)
        expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
        expect(umodel).to receive(:update).at_least(:once)
        expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model2.map_target("TARGET1", tlm_only: true, unmap_old: false)

        model1 = InterfaceModel.get_model(name: "TEST1_INT", scope: "DEFAULT")
        model2 = InterfaceModel.get_model(name: "TEST2_INT", scope: "DEFAULT")
        model3 = InterfaceModel.get_model(name: "TEST3_INT", scope: "DEFAULT")

        expect(model1.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model1.cmd_target_names).to eq ["TARGET1"]
        expect(model1.tlm_target_names).to eq ["TARGET2"]
        expect(model2.target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model2.cmd_target_names).to eq ["TARGET3", "TARGET4"]
        expect(model2.tlm_target_names).to eq ["TARGET3", "TARGET4", "TARGET1"]
        expect(model3.target_names).to eq ["TARGET1", "TARGET2"]
        expect(model3.cmd_target_names).to eq ["TARGET2"]
        expect(model3.tlm_target_names).to eq ["TARGET1"]
      end
    end
  end
end
