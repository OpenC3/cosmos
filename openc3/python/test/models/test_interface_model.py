# Copyright 2023 OpenC3, Inc.
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

import unittest
from unittest.mock import *
from test.test_helper import *
from openc3.models.interface_model import InterfaceModel
from openc3.models.router_model import RouterModel


class TestInterfaceModel(unittest.TestCase):
    def setUp(self):
        mock_redis(self)

    def test_returns_the_specified_interface(self):
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            connect_on_startup=False,
            auto_reconnect=False,
        )  # Set a few things to check
        model.create()
        model = InterfaceModel(
            name="SPEC_INT",
            scope="DEFAULT",
            connect_on_startup=True,
            auto_reconnect=True,
        )  # Set to opposite of TEST_INT
        model.create()
        test = InterfaceModel.get(name="TEST_INT", scope="DEFAULT")
        self.assertEqual(test["name"], "TEST_INT")
        self.assertFalse(test["connect_on_startup"])
        self.assertFalse(test["auto_reconnect"])

    def test_works_with_same_named_routers(self):
        model = InterfaceModel(
            name="TEST_INT",
            scope="DEFAULT",
            connect_on_startup=False,
            auto_reconnect=False,
        )  # Set a few things to check
        model.create()
        print("router model new")
        model = RouterModel(
            name="TEST_INT",
            scope="DEFAULT",
            connect_on_startup=True,
            auto_reconnect=True,
        )  # Set to opposite
        model.create()
        test = InterfaceModel.get(name="TEST_INT", scope="DEFAULT")
        self.assertEqual(test["name"], "TEST_INT")
        self.assertFalse(test["connect_on_startup"])
        self.assertFalse(test["auto_reconnect"])
        test = RouterModel.get(name="TEST_INT", scope="DEFAULT")
        self.assertEqual(test["name"], "TEST_INT")
        self.assertTrue(test["connect_on_startup"])
        self.assertTrue(test["auto_reconnect"])


#     def test_returns_all_interface_names(self):
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT")
#         model.create()
#         model = InterfaceModel(name= "SPEC_INT", scope= "DEFAULT")
#         model.create()
#         model = InterfaceModel(name= "OTHER_INT", scope= "OTHER")
#         model.create()
#         names = InterfaceModel.names(scope= "DEFAULT")
#         # contain_exactly doesn't care about ordering and neither do we
#         expect(names).to contain_exactly("TEST_INT", "SPEC_INT")
#         names = InterfaceModel.names(scope= "OTHER")
#         expect(names).to contain_exactly("OTHER_INT")

# class Self.all(unittest.TestCase):
#     def test_returns_all_the_parsed_interfaces(self):
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT",
#                                    connect_on_startup= False, auto_reconnect= False) # Set a few things to check
#         model.create()
#         model = InterfaceModel(name= "SPEC_INT", scope= "DEFAULT",
#                                    connect_on_startup= True, auto_reconnect= True) # Set to opposite of TEST_INT
#         model.create()
#         all = InterfaceModel.all(scope= "DEFAULT")
#         expect(all.keys).to contain_exactly("TEST_INT", "SPEC_INT")
#         self.assertFalse(all["TEST_INT"]["connect_on_startup"])
#         self.assertFalse(all["TEST_INT"]["auto_reconnect"])
#         self.assertTrue(all["SPEC_INT"]["connect_on_startup"])
#         self.assertTrue(all["SPEC_INT"]["auto_reconnect"])

# class Self.handleConfig(unittest.TestCase):
#     def test_only_recognizes_interface(self):
#         parser = double("ConfigParser").as_null_object
#         expect(parser).to receive(:verify_num_parameters)
#         InterfaceModel.handle_config(parser, "INTERFACE", ["TEST_INT"], scope= "DEFAULT")
#         { InterfaceModel.handle_config(parser, "ROUTER", ["TEST_INT"], scope= "DEFAULT") }.to raise_error(ConfigParser='E'rror)

# class Initialize(unittest.TestCase):
#     def test_requires_name_and_scope(self):
#         { InterfaceModel(name= "TEST_INT") }.to raise_error(ArgumentError)
#         { InterfaceModel(scope= "TEST_INT") }.to raise_error(ArgumentError)
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT")
#         self.assertEqual(model.name,  "TEST_INT")

# class Create(unittest.TestCase):
#     def test_stores_model_based_on_scope_and_class_name(self):
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT")
#         model.create()
#         keys = Store.scan(0)
#         # This is an implementation detail but Redis keys are pretty critical so test it
#         self.assertIn(["DEFAULT__openc3_interfaces").at_most(1], keys[1])
#         # 21/07/2021 - G this needed to be changed to contain OPENC3__TOKEN

# class HandleConfig(unittest.TestCase):
#     def test_raise_on_unknown_keywords(self):
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT")
#         parser = ConfigParser()
#         tf = Tempfile()
#         tf.puts "UNKNOWN"
#         tf.seek(0)
#         parser.parse_file(tf.name) do |keyword, params|
#           { model.handle_config(parser, keyword, params) }.to raise_error(/Unknown keyword/)
#         tf.close()

#     def test_raise_on_badly_formatted_keywords(self):
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT")
#         parser = ConfigParser()
#         tf = Tempfile()
#         tf.puts "PROTOCOL OTHER ReadProtocol"
#         tf.seek(0)
#         parser.parse_file(tf.name) do |keyword, params|
#           { model.handle_config(parser, keyword, params) }.to raise_error("Invalid protocol type= OTHER")
#         tf.close()

#     def test_parses_tool_specific_keywords(self):
#         TargetModel(name= "TARGET1", scope= "DEFAULT").create()
#         TargetModel(name= "TARGET2", scope= "DEFAULT").create()
#         TargetModel(name= "TARGET3", scope= "DEFAULT").create()
#         TargetModel(name= "TARGET4", scope= "DEFAULT").create()
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT")

#         parser = ConfigParser()
#         tf = Tempfile()
#         tf.puts "MAP_TARGET TARGET1"
#         tf.puts "MAP_TARGET TARGET2"
#         tf.puts "MAP_CMD_TARGET TARGET3"
#         tf.puts "MAP_TLM_TARGET TARGET4"
#         tf.puts "DONT_CONNECT"
#         tf.puts "DONT_RECONNECT"
#         tf.puts "RECONNECT_DELAY 10"
#         tf.puts "DISABLE_DISCONNECT"
#         tf.puts "OPTION NAME1 VALUE1"
#         tf.puts "OPTION NAME2 VALUE2"
#         tf.puts "PROTOCOL READ ReadProtocol 1 2 3"
#         tf.puts "PROTOCOL WRITE WriteProtocol"
#         tf.puts "LOG_STREAM"
#         tf.seek(0)
#         parser.parse_file(tf.name) do |keyword, params|
#           model.handle_config(parser, keyword, params)
#         json = model.as_json()
#         self.assertIn(["TARGET1", "TARGET2", "TARGET3", "TARGET4"], json['target_names'])
#         self.assertIn(["TARGET1", "TARGET2", "TARGET3"], json['cmd_target_names'])
#         self.assertIn(["TARGET1", "TARGET2", "TARGET4"], json['tlm_target_names'])
#         self.assertFalse(json['connect_on_startup'])
#         self.assertFalse(json['auto_reconnect'])
#         self.assertEqual(json['reconnect_delay'],  10.0)
#         self.assertTrue(json['disable_disconnect'])
#         self.assertIn([["NAME1", "VALUE1"], ["NAME2", "VALUE2"]], json['options'])
#         self.assertIn([["READ", "ReadProtocol", "1", "2", "3"], ["WRITE", "WriteProtocol"]], json['protocols'])
#         self.assertEqual(json['log_stream'],  [])
#         tf.close()

# class Build(unittest.TestCase):
#     def test_instantiates_the_interface(self):
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT", config_params= ["interface.rb"])
#         interface = model.build
#         self.assertEqual(interface.__class__.__name__,  Interface)
#         self.assertEqual(interface.stream_log_pair, None)
#         # Now instantiate a more complex option
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT",
#                                    config_params= %w(tcpip_client_interface.rb 127.0.0.1 8080 8081 10.0 None BURST 4 0xDEADBEEF))
#         interface = model.build
#         self.assertEqual(interface.__class__.__name__,  TcpipClientInterface)

# class AsJson(unittest.TestCase):
#     def test_encodes_all_the_input_parameters(self):
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT")
#         json = model.as_json()
#         # Check the defaults
#         self.assertEqual(json['name'],  "TEST_INT")
#         self.assertEqual(json['config_params'],  [])
#         self.assertEqual(json['target_names'],  [])
#         self.assertEqual(json['cmd_target_names'],  [])
#         self.assertEqual(json['tlm_target_names'],  [])
#         self.assertEqual(json['connect_on_startup'],  True)
#         self.assertEqual(json['auto_reconnect'],  True)
#         self.assertEqual(json['reconnect_delay'],  5.0)
#         self.assertEqual(json['disable_disconnect'],  False)
#         self.assertEqual(json['options'],  [])
#         self.assertEqual(json['secret_options'],  [])
#         self.assertEqual(json['protocols'],  [])
#         self.assertEqual(json['log_stream'],  None)
#         self.assertEqual(json['plugin'],  None)
#         self.assertEqual(json['needs_dependencies'],  False)
#         self.assertEqual(json['secrets'],  [])
#         self.assertEqual(json['cmd'],  ["ruby", "interface_microservice.rb", "DEFAULT__INTERFACE__TEST_INT"])
#         self.assertEqual(json['env'], ({}))
#         self.assertEqual(json['work_dir'],  '/openc3/lib/openc3/microservices')
#         self.assertEqual(json['ports'],  [])
#         self.assertEqual(json['container'],  None)
#         self.assertEqual(json['prefix'],  None)

#         params = model.method(:initialize).parameters
#         for type, name in params:
#           # Scope isn't included in as_json as it is part of the key used to get the model
#           if name == :scope:
#               next

#           self.assertTrue(json.key?( str(name)))

# class Deploy, undeploy(unittest.TestCase):
#     def test_creates_and_deploys_a_microservicemodel(self):
#         dir = Dir.pwd
#         variables = { "test" : "example" }

#         intmodel = double(InterfaceStatusModel)
#         expect(intmodel).to receive(:destroy)
#         expect(InterfaceStatusModel).to receive(:get_model).and_return(intmodel)
#         # double MicroserviceModel because we're not testing that here
#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:create)
#         expect(umodel).to receive(:deploy).with(dir, variables)
#         expect(umodel).to receive(:destroy)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel)
#         expect(MicroserviceModel).to receive(:new).and_return(umodel)
#         model = InterfaceModel(name= "TEST_INT", scope= "DEFAULT", plugin= "PLUG")
#         model.create()
#         model.deploy(dir, variables)
#         config = ConfigTopic.read(scope= 'DEFAULT')
#         self.assertEqual(config[0][1]['kind'],  'created')
#         self.assertEqual(config[0][1]['type'],  'interface')
#         self.assertEqual(config[0][1]['name'],  'TEST_INT')
#         self.assertEqual(config[0][1]['plugin'],  'PLUG')

#         model.undeploy
#         config = ConfigTopic.read(scope= 'DEFAULT')
#         self.assertEqual(config[0][1]['kind'],  'deleted')
#         self.assertEqual(config[0][1]['type'],  'interface')
#         self.assertEqual(config[0][1]['name'],  'TEST_INT')
#         self.assertEqual(config[0][1]['plugin'],  'PLUG')

# class MapTarget, unmapTarget(unittest.TestCase):
#     def setUp(self):
#         TargetModel(name= "TARGET1", scope= "DEFAULT").create()
#         TargetModel(name= "TARGET2", scope= "DEFAULT").create()
#         TargetModel(name= "TARGET3", scope= "DEFAULT").create()
#         TargetModel(name= "TARGET4", scope= "DEFAULT").create()
#         InterfaceModel(name= "TEST1_INT", scope= "DEFAULT", plugin= "PLUG", target_names= ["TARGET1", "TARGET2"], cmd_target_names= ["TARGET1"], tlm_target_names= ["TARGET2"]).create()
#         InterfaceModel(name= "TEST2_INT", scope= "DEFAULT", plugin= "PLUG", target_names= ["TARGET3", "TARGET4"], cmd_target_names= ["TARGET3", "TARGET4"], tlm_target_names= ["TARGET3", "TARGET4"]).create()
#         InterfaceModel(name= "TEST3_INT", scope= "DEFAULT", plugin= "PLUG", target_names= ["TARGET1", "TARGET2"], cmd_target_names= ["TARGET2"], tlm_target_names= ["TARGET1"]).create()

#     def test_should_complain_about_unknown_targets(self):
#         model1 = InterfaceModel.get_model(name= "TEST1_INT", scope= "DEFAULT")
#         with self.assertRaisesRegex(AttributeError, f"Target TARGET5 does not exist"):
#              model1.map_target("TARGET5")

#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
#         expect(umodel).to receive(:update).at_least(:once)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)
#         { model1.unmap_target("TARGET5") }.not_to raise_error # Unmap doesn't care

#     def test_should_unmap_targets_from_other_interfaces_by_default(self):
#         # double MicroserviceModel because we're not testing that here
#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
#         expect(umodel).to receive(:update).at_least(:once)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model2.map_target("TARGET1")

#         model1 = InterfaceModel.get_model(name= "TEST1_INT", scope= "DEFAULT")
#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model3 = InterfaceModel.get_model(name= "TEST3_INT", scope= "DEFAULT")

#         self.assertEqual(model1.target_names,  ["TARGET2"])
#         self.assertEqual(model1.cmd_target_names,  [])
#         self.assertEqual(model1.tlm_target_names,  ["TARGET2"])
#         self.assertEqual(model2.target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.cmd_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.tlm_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model3.target_names,  ["TARGET2"])
#         self.assertEqual(model3.cmd_target_names,  ["TARGET2"])
#         self.assertEqual(model3.tlm_target_names,  [])

#     def test_should_unmap_cmd_targets_from_other_interfaces_by_default(self):
#         # double MicroserviceModel because we're not testing that here
#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
#         expect(umodel).to receive(:update).at_least(:once)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model2.map_target("TARGET1", cmd_only= True)

#         model1 = InterfaceModel.get_model(name= "TEST1_INT", scope= "DEFAULT")
#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model3 = InterfaceModel.get_model(name= "TEST3_INT", scope= "DEFAULT")

#         self.assertEqual(model1.target_names,  ["TARGET2"])
#         self.assertEqual(model1.cmd_target_names,  [])
#         self.assertEqual(model1.tlm_target_names,  ["TARGET2"])
#         self.assertEqual(model2.target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.cmd_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.tlm_target_names,  ["TARGET3", "TARGET4"])
#         self.assertEqual(model3.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model3.cmd_target_names,  ["TARGET2"])
#         self.assertEqual(model3.tlm_target_names,  ["TARGET1"])

#     def test_should_unmap_tlm_targets_from_other_interfaces_by_default(self):
#         # double MicroserviceModel because we're not testing that here
#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
#         expect(umodel).to receive(:update).at_least(:once)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model2.map_target("TARGET1", tlm_only= True)

#         model1 = InterfaceModel.get_model(name= "TEST1_INT", scope= "DEFAULT")
#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model3 = InterfaceModel.get_model(name= "TEST3_INT", scope= "DEFAULT")

#         self.assertEqual(model1.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model1.cmd_target_names,  ["TARGET1"])
#         self.assertEqual(model1.tlm_target_names,  ["TARGET2"])
#         self.assertEqual(model2.target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.cmd_target_names,  ["TARGET3", "TARGET4"])
#         self.assertEqual(model2.tlm_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model3.target_names,  ["TARGET2"])
#         self.assertEqual(model3.cmd_target_names,  ["TARGET2"])
#         self.assertEqual(model3.tlm_target_names,  [])

#     def test_should_not_unmap_targets_from_other_interfaces_if_disabled(self):
#         # double MicroserviceModel because we're not testing that here
#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
#         expect(umodel).to receive(:update).at_least(:once)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model2.map_target("TARGET1", unmap_old= False)

#         model1 = InterfaceModel.get_model(name= "TEST1_INT", scope= "DEFAULT")
#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model3 = InterfaceModel.get_model(name= "TEST3_INT", scope= "DEFAULT")

#         self.assertEqual(model1.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model1.cmd_target_names,  ["TARGET1"])
#         self.assertEqual(model1.tlm_target_names,  ["TARGET2"])
#         self.assertEqual(model2.target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.cmd_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.tlm_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model3.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model3.cmd_target_names,  ["TARGET2"])
#         self.assertEqual(model3.tlm_target_names,  ["TARGET1"])

#     def test_should_not_unmap_cmd_targets_from_other_interfaces_if_disabled(self):
#         # double MicroserviceModel because we're not testing that here
#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
#         expect(umodel).to receive(:update).at_least(:once)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model2.map_target("TARGET1", cmd_only= True, unmap_old= False)

#         model1 = InterfaceModel.get_model(name= "TEST1_INT", scope= "DEFAULT")
#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model3 = InterfaceModel.get_model(name= "TEST3_INT", scope= "DEFAULT")

#         self.assertEqual(model1.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model1.cmd_target_names,  ["TARGET1"])
#         self.assertEqual(model1.tlm_target_names,  ["TARGET2"])
#         self.assertEqual(model2.target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.cmd_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.tlm_target_names,  ["TARGET3", "TARGET4"])
#         self.assertEqual(model3.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model3.cmd_target_names,  ["TARGET2"])
#         self.assertEqual(model3.tlm_target_names,  ["TARGET1"])

#     def test_should_not_unmap_tlm_targets_from_other_interfaces_if_disabled(self):
#         # double MicroserviceModel because we're not testing that here
#         umodel = double(MicroserviceModel)
#         expect(umodel).to receive(:target_names).and_return([]).at_least(:once)
#         expect(umodel).to receive(:update).at_least(:once)
#         expect(MicroserviceModel).to receive(:get_model).and_return(umodel).at_least(:once)

#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model2.map_target("TARGET1", tlm_only= True, unmap_old= False)

#         model1 = InterfaceModel.get_model(name= "TEST1_INT", scope= "DEFAULT")
#         model2 = InterfaceModel.get_model(name= "TEST2_INT", scope= "DEFAULT")
#         model3 = InterfaceModel.get_model(name= "TEST3_INT", scope= "DEFAULT")

#         self.assertEqual(model1.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model1.cmd_target_names,  ["TARGET1"])
#         self.assertEqual(model1.tlm_target_names,  ["TARGET2"])
#         self.assertEqual(model2.target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model2.cmd_target_names,  ["TARGET3", "TARGET4"])
#         self.assertEqual(model2.tlm_target_names,  ["TARGET3", "TARGET4", "TARGET1"])
#         self.assertEqual(model3.target_names,  ["TARGET1", "TARGET2"])
#         self.assertEqual(model3.cmd_target_names,  ["TARGET2"])
#         self.assertEqual(model3.tlm_target_names,  ["TARGET1"])
