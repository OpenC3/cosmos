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

# require 'spec_helper'
# require 'openc3/api/cmd_api'
# require 'openc3/microservices/interface_microservice'
# require 'openc3/script/extract'
# require 'openc3/utilities/authorization'
# require 'openc3/microservices/decom_microservice'
# require 'openc3/models/target_model'
# require 'openc3/models/interface_model'
# require 'openc3/topics/telemetry_decom_topic'


class TestCmdApi(unittest.TestCase):
  describe Api do
class ApiTest:
      include Extract
      include Api
      include Authorization

    def setUp(self):
      redis = mock_redis()
      setup_system()

      require 'openc3/models/target_model'
      model = TargetModel(folder_name= 'INST', name= 'INST', scope= "DEFAULT")
      model.create
      model.update_store(System(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      model = InterfaceModel(name= "INST_INT", scope= "DEFAULT", target_names= ["INST"], cmd_target_names= ["INST"], tlm_target_names= ["INST"], config_params= ["interface.rb"])
      model.create
      model = InterfaceStatusModel(name= "INST_INT", scope= "DEFAULT", state= "ACTIVE")
      model.create

      # Create an Interface we can use in the InterfaceCmdHandlerThread
      # It has to have a valid list of target_names as that is what 'receive_commands'
      # in the Store uses to determine which topics to read
      self.interface = Interface()
      self.interface.name = "INST_INT"
      self.interface.target_names = %w[INST]
      self.interface.cmd_target_names = %w[INST]
      self.interface.tlm_target_names = %w[INST]

      # Stub to make the InterfaceCmdHandlerThread happy
      self.interface_data = ''
      allow(self.interface).to receive(:connected?).and_return(True)
      allow(self.interface).to receive(:write_interface) { |data| self.interface_data = data }
      self.thread = InterfaceCmdHandlerThread(self.interface, None, scope= 'DEFAULT')
      self.process = True # Allow the command to be processed or not

      allow(redis).to receive(:xread).and_wrap_original do |m, *args|
        # Only use the first two arguments as the last argument is keyword block:
        result = None
        if self.process:
            result = m.call(*args[0..1])
        # Create a slight delay to simulate the blocking call
        if result and len(result) == 0:
            sleep 0.001
        result

      self.int_thread = Thread() { self.thread.run }
      sleep 0.01 # Allow thread to spin up
      self.api = ApiTest()

    after(:each) do
      InterfaceTopic.shutdown(self.interface, scope= 'DEFAULT')
      count = 0
      while self.int_thread.alive? or count < 100 do
        sleep 0.01
        count += 1

    def test_cmd_unknown(method):
      { self.api.send(method, "BLAH COLLECT with TYPE NORMAL") }.to raise_error(/does not exist/)
      { self.api.send(method, "INST UNKNOWN with TYPE NORMAL") }.to raise_error(/does not exist/)
      # expect { @api.send(method, "INST COLLECT with BLAH NORMAL") }.to raise_error(/does not exist/)
      { self.api.send(method, "BLAH", "COLLECT", "TYPE" : "NORMAL") }.to raise_error(/does not exist/)
      { self.api.send(method, "INST", "UNKNOWN", "TYPE" : "NORMAL") }.to raise_error(/does not exist/)
      # expect { @api.send(method, "INST", "COLLECT", "BLAH"=>"NORMAL") }.to raise_error(/does not exist/)

class Cmd(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd)

    def test_processes_a_string(self):
        target_name, cmd_name, params = self.api.cmd("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_complains_if_parameters_are_not_separated_by_commas(self):
        { self.api.cmd("INST COLLECT with TYPE NORMAL DURATION 5") }.to raise_error(/Missing comma/)

    def test_complains_if_parameters_dont_have_values(self):
        { self.api.cmd("INST COLLECT with TYPE") }.to raise_error(/Missing value/)

    def test_processes_parameters(self):
        target_name, cmd_name, params = self.api.cmd("inst", "Collect", "TYPE" : "NORMAL", "Duration" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_processes_commands_without_parameters(self):
        target_name, cmd_name, params = self.api.cmd("INST", "ABORT")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'ABORT')
        self.assertEqual(params, {})

    def test_complains_about_too_many_parameters(self):
        { self.api.cmd("INST", "COLLECT", "TYPE", "DURATION") }.to raise_error(/Invalid number of arguments/)

    def test_warns_about_required_parameters(self):
        { self.api.cmd("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_warns_about_out_of_range_parameters(self):
        { self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 1000") }.to raise_error(/not in valid range/)

    def test_warns_about_hazardous_parameters(self):
        { self.api.cmd("INST COLLECT with TYPE SPECIAL") }.to raise_error(/Hazardous/)

    def test_warns_about_hazardous_commands(self):
        { self.api.cmd("INST CLEAR") }.to raise_error(/Hazardous/)

    def test_times_out_if_the_interface_does_not_process_the_command(self):
        { self.api.cmd("INST", "ABORT", timeout= True) }.to raise_error("Invalid timeout parameter= True. Must be numeric.")
        { self.api.cmd("INST", "ABORT", timeout= False) }.to raise_error("Invalid timeout parameter= False. Must be numeric.")
        { self.api.cmd("INST", "ABORT", timeout= "YES") }.to raise_error("Invalid timeout parameter= YES. Must be numeric.")
        try:
          self.process = False
          { self.api.cmd("INST", "ABORT") }.to raise_error("Timeout of 5s waiting for cmd ack")
          { self.api.cmd("INST", "ABORT", timeout= 1) }.to raise_error("Timeout of 1s waiting for cmd ack")
        ensure
          self.process = True

    def test_does_not_log_a_message_if_the_packet_has_disable_messages(self):
        message = None
        allow(Logger).to receive(:info) do |args|
          message = args
        self.api.cmd("INST ABORT")
        self.assertEqual(message,  'cmd("INST ABORT")')
        message = None
        self.api.cmd("INST ABORT", log_message= False) # Don't log
        self.assertEqual(message, None)
        self.api.cmd("INST SETPARAMS") # This has DISABLE_MESSAGES applied
        self.assertEqual(message, None)
        self.api.cmd("INST SETPARAMS", log_message= True) # Force message
        self.assertEqual(message,  'cmd("INST SETPARAMS")')
        message = None
        # Send bad log_message parameters
        { self.api.cmd("INST SETPARAMS", log_message= 0) }.to raise_error("Invalid log_message parameter= 0. Must be True or False.")
        { self.api.cmd("INST SETPARAMS", log_message= "YES") }.to raise_error("Invalid log_message parameter= YES. Must be True or False.")
        self.api.cmd("INST SETPARAMS", log_message= None) # This actually works because None is the default
        self.assertEqual(message, None)

class CmdNoRangeCheck(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd_no_range_check)

    def test_processes_a_string(self):
        target_name, cmd_no_range_check_name, params = self.api.cmd_no_range_check("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_range_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_processes_parameters(self):
        target_name, cmd_no_range_check_name, params = self.api.cmd_no_range_check("Inst", "collect", "TYPE" : "NORMAL", "duration" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_range_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_warns_about_required_parameters(self):
        { self.api.cmd_no_range_check("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_does_not_warn_about_out_of_range_parameters(self):
        { self.api.cmd_no_range_check("INST COLLECT with TYPE NORMAL, DURATION 1000") }.to_not raise_error

    def test_warns_about_hazardous_parameters(self):
        { self.api.cmd_no_range_check("INST COLLECT with TYPE SPECIAL") }.to raise_error(/Hazardous/)

    def test_warns_about_hazardous_commands(self):
        { self.api.cmd_no_range_check("INST CLEAR") }.to raise_error(/Hazardous/)

class CmdNoHazardousCheck(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd_no_hazardous_check)

    def test_processes_a_string(self):
        target_name, cmd_no_hazardous_check_name, params = self.api.cmd_no_hazardous_check("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_hazardous_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_processes_parameters(self):
        target_name, cmd_no_hazardous_check_name, params = self.api.cmd_no_hazardous_check("INST", "COLLECT", "TYPE" : "NORMAL", "DURATION" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_hazardous_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_processes_parameters_that_are_strings(self):
        target_name, cmd_name, params = self.api.cmd_no_hazardous_check("INST ASCIICMD with STRING 'ARM LASER'")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'ASCIICMD')
        self.assertIn(['STRING' : 'ARM LASER'], params)

    def test_warns_about_required_parameters(self):
        { self.api.cmd_no_hazardous_check("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_warns_about_out_of_range_parameters(self):
        { self.api.cmd_no_hazardous_check("INST COLLECT with TYPE NORMAL, DURATION 1000") }.to raise_error(/not in valid range/)

    def test_does_not_warn_about_hazardous_parameters(self):
        { self.api.cmd_no_hazardous_check("INST COLLECT with TYPE SPECIAL") }.to_not raise_error

    def test_does_not_warn_about_hazardous_commands(self):
        { self.api.cmd_no_hazardous_check("INST CLEAR") }.to_not raise_error

    def test_does_not_log_a_message_if_the_parameter_state_has_disable_messages(self):
        message = None
        allow(Logger).to receive(:info) do |args|
          message = args
        self.api.cmd_no_hazardous_check("INST ASCIICMD with STRING 'ARM LASER'")
        self.assertEqual(message,  'cmd("INST ASCIICMD with STRING \'ARM LASER\'")')
        message = None
        self.api.cmd_no_hazardous_check("INST ASCIICMD with STRING 'ARM LASER'", log_message= False) # Don't log
        self.assertEqual(message, None)
        self.api.cmd_no_hazardous_check("INST ASCIICMD with STRING 'NOOP'") # This has DISABLE_MESSAGES
        self.assertEqual(message, None)
        self.api.cmd_no_hazardous_check("INST ASCIICMD with STRING 'NOOP'", log_message= True) # Force log
        self.assertEqual(message,  'cmd("INST ASCIICMD with STRING \'NOOP\'")')

class CmdNoChecks(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd_no_checks)

    def test_processes_a_string(self):
        target_name, cmd_no_checks_name, params = self.api.cmd_no_checks("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_checks_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_processes_parameters(self):
        target_name, cmd_no_checks_name, params = self.api.cmd_no_checks("INST", "COLLECT", "TYPE" : "NORMAL", "DURATION" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_checks_name,  'COLLECT')
        self.assertIn(['TYPE' : 'NORMAL', 'DURATION' : 5], params)

    def test_warns_about_required_parameters(self):
        { self.api.cmd_no_checks("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_does_not_warn_about_out_of_range_parameters(self):
        { self.api.cmd_no_checks("INST COLLECT with TYPE NORMAL, DURATION 1000") }.to_not raise_error

    def test_does_not_warn_about_hazardous_parameters(self):
        { self.api.cmd_no_checks("INST COLLECT with TYPE SPECIAL") }.to_not raise_error

    def test_does_not_warn_about_hazardous_commands(self):
        { self.api.cmd_no_checks("INST CLEAR") }.to_not raise_error

class CmdRaw(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd_raw)

    def test_processes_a_string(self):
        target_name, cmd_name, params = self.api.cmd_raw("inst Collect with type 0, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_complains_if_parameters_are_not_separated_by_commas(self):
        { self.api.cmd_raw("INST COLLECT with TYPE 0 DURATION 5") }.to raise_error(/Missing comma/)

    def test_complains_if_parameters_dont_have_values(self):
        { self.api.cmd_raw("INST COLLECT with TYPE") }.to raise_error(/Missing value/)

    def test_processes_parameters(self):
        target_name, cmd_name, params = self.api.cmd_raw("inst", "Collect", "type" : 0, "Duration" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_processes_commands_without_parameters(self):
        target_name, cmd_name, params = self.api.cmd_raw("INST", "ABORT")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'ABORT')
        self.assertEqual(params, {})

    def test_complains_about_too_many_parameters(self):
        { self.api.cmd_raw("INST", "COLLECT", "TYPE", "DURATION") }.to raise_error(/Invalid number of arguments/)

    def test_warns_about_required_parameters(self):
        { self.api.cmd_raw("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_warns_about_out_of_range_parameters(self):
        { self.api.cmd_raw("INST COLLECT with TYPE 0, DURATION 1000") }.to raise_error(/not in valid range/)

    def test_warns_about_hazardous_parameters(self):
        { self.api.cmd_raw("INST COLLECT with TYPE 1") }.to raise_error(/Hazardous/)

    def test_warns_about_hazardous_commands(self):
        { self.api.cmd_raw("INST CLEAR") }.to raise_error(/Hazardous/)

class CmdNoRangeCheck(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd_raw_no_range_check)

    def test_processes_a_string(self):
        target_name, cmd_no_range_check_name, params = self.api.cmd_raw_no_range_check("inst Collect with type 0, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_range_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_processes_parameters(self):
        target_name, cmd_no_range_check_name, params = self.api.cmd_raw_no_range_check("inst", "Collect", "type" : 0, "Duration" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_range_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_warns_about_required_parameters(self):
        { self.api.cmd_raw_no_range_check("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_does_not_warn_about_out_of_range_parameters(self):
        { self.api.cmd_raw_no_range_check("INST COLLECT with TYPE 0, DURATION 1000") }.to_not raise_error

    def test_warns_about_hazardous_parameters(self):
        { self.api.cmd_raw_no_range_check("INST COLLECT with TYPE 1") }.to raise_error(/Hazardous/)

    def test_warns_about_hazardous_commands(self):
        { self.api.cmd_raw_no_range_check("INST CLEAR") }.to raise_error(/Hazardous/)

class CmdRawNoHazardousCheck(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd_raw_no_hazardous_check)

    def test_processes_a_string(self):
        target_name, cmd_no_hazardous_check_name, params = self.api.cmd_raw_no_hazardous_check("inst Collect with type 0, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_hazardous_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_processes_parameters(self):
        target_name, cmd_no_hazardous_check_name, params = self.api.cmd_raw_no_hazardous_check("inst", "Collect", "type" : 0, "Duration" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_hazardous_check_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_processes_parameters_that_are_strings(self):
        target_name, cmd_name, params = self.api.cmd_raw_no_hazardous_check("INST ASCIICMD with STRING 'ARM LASER'")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_name,  'ASCIICMD')
        self.assertIn(['STRING' : 'ARM LASER'], params)

    def test_warns_about_required_parameters(self):
        { self.api.cmd_raw_no_hazardous_check("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_warns_about_out_of_range_parameters(self):
        { self.api.cmd_raw_no_hazardous_check("INST COLLECT with TYPE 0, DURATION 1000") }.to raise_error(/not in valid range/)

    def test_does_not_warn_about_hazardous_parameters(self):
        { self.api.cmd_raw_no_hazardous_check("INST COLLECT with TYPE 1") }.to_not raise_error

    def test_does_not_warn_about_hazardous_commands(self):
        { self.api.cmd_raw_no_hazardous_check("INST CLEAR") }.to_not raise_error

class CmdRawNoChecks(unittest.TestCase):
    def test_complains_about_unknown_targets_commands_and_parameters(self):
        test_cmd_unknown(:cmd_raw_no_checks)

    def test_processes_a_string(self):
        target_name, cmd_no_checks_name, params = self.api.cmd_raw_no_checks("inst Collect with type 0, Duration 5")
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_checks_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_processes_parameters(self):
        target_name, cmd_no_checks_name, params = self.api.cmd_raw_no_checks("inst", "Collect", "type" : 0, "Duration" : 5)
        self.assertEqual(target_name,  'INST')
        self.assertEqual(cmd_no_checks_name,  'COLLECT')
        self.assertIn(['TYPE' : 0, 'DURATION' : 5], params)

    def test_warns_about_required_parameters(self):
        { self.api.cmd_raw_no_checks("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_does_not_warn_about_out_of_range_parameters(self):
        { self.api.cmd_raw_no_checks("INST COLLECT with TYPE 0, DURATION 1000") }.to_not raise_error

    def test_does_not_warn_about_hazardous_parameters(self):
        { self.api.cmd_raw_no_checks("INST COLLECT with TYPE 1") }.to_not raise_error

    def test_does_not_warn_about_hazardous_commands(self):
        { self.api.cmd_raw_no_checks("INST CLEAR") }.to_not raise_error

class BuildCommand(unittest.TestCase):
    def setUp(self):
        model = MicroserviceModel(name= "DEFAULT__DECOM__INST_INT", scope= "DEFAULT",
          topics= ["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"], target_names= ['INST'])
        model.create
        self.dm = DecomMicroservice("DEFAULT__DECOM__INST_INT")
        self.dm_thread = Thread() { self.dm.run }
        sleep(0.1)

      after(:each) do
        self.dm.shutdown
        sleep(0.1)

    def test_complains_about_unknown_targets(self):
        { self.api.build_command("BLAH COLLECT") }.to raise_error(/Timeout of 5s waiting for cmd ack. Does target 'BLAH' exist?/)

    def test_complains_about_unknown_commands(self):
        { self.api.build_command("INST", "BLAH") }.to raise_error(/does not exist/)

    def test_processes_a_string(self):
        cmd = self.api.build_command("inst Collect with type NORMAL, Duration 5")
        self.assertEqual(cmd['target_name'],  'INST')
        self.assertEqual(cmd['packet_name'],  'COLLECT')
        self.assertEqual(cmd['buffer'],  "\x13\xE7\xC0\x00\x00\x00\x00\x01\x00\x00self.\xA0\x00\x00\xAB\x00\x00\x00\x00")

    def test_complains_if_parameters_are_not_separated_by_commas(self):
        { self.api.build_command("INST COLLECT with TYPE NORMAL DURATION 5") }.to raise_error(/Missing comma/)

    def test_complains_if_parameters_dont_have_values(self):
        { self.api.build_command("INST COLLECT with TYPE") }.to raise_error(/Missing value/)

    def test_processes_parameters(self):
        cmd = self.api.build_command("inst", "Collect", "TYPE" : "NORMAL", "Duration" : 5)
        self.assertEqual(cmd['target_name'],  'INST')
        self.assertEqual(cmd['packet_name'],  'COLLECT')
        self.assertEqual(cmd['buffer'],  "\x13\xE7\xC0\x00\x00\x00\x00\x01\x00\x00self.\xA0\x00\x00\xAB\x00\x00\x00\x00")

    def test_processes_commands_without_parameters(self):
        cmd = self.api.build_command("INST", "ABORT")
        self.assertEqual(cmd['target_name'],  'INST')
        self.assertEqual(cmd['packet_name'],  'ABORT')
        self.assertEqual(cmd['buffer'],  "\x13\xE7\xC0\x00\x00\x00\x00\x02" # Pkt ID 2)

        cmd = self.api.build_command("INST CLEAR")
        self.assertEqual(cmd['target_name'],  'INST')
        self.assertEqual(cmd['packet_name'],  'CLEAR')
        self.assertEqual(cmd['buffer'],  "\x13\xE7\xC0\x00\x00\x00\x00\x03" # Pkt ID 3)

    def test_complains_about_too_many_parameters(self):
        { self.api.build_command("INST", "COLLECT", "TYPE", "DURATION") }.to raise_error(/Invalid number of arguments/)

    def test_warns_about_required_parameters(self):
        { self.api.build_command("INST COLLECT with DURATION 5") }.to raise_error(/Required/)

    def test_warns_about_out_of_range_parameters(self):
        { self.api.build_command("INST COLLECT with TYPE NORMAL, DURATION 1000") }.to raise_error(/not in valid range/)
        cmd = self.api.build_command("INST COLLECT with TYPE NORMAL, DURATION 1000", range_check= False)
        self.assertEqual(cmd['target_name'],  'INST')
        self.assertEqual(cmd['packet_name'],  'COLLECT')

class GetCmdBuffer(unittest.TestCase):
    def test_complains_about_unknown_commands(self):
        { self.api.get_cmd_buffer("INST", "BLAH") }.to raise_error(/does not exist/)

    def test_returns_None_if_the_command_has_not_yet_been_sent(self):
        self.assertIsNone(self.api.get_cmd_buffer("INST", "ABORT"))

    def test_returns_a_command_packet_buffer(self):
        self.api.cmd("INST ABORT")
        output = self.api.get_cmd_buffer("inst", "Abort")
        self.assertEqual(output["buffer"][6..7].unpack("n")[0],  2)
        self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        output = self.api.get_cmd_buffer("INST", "COLLECT")
        self.assertEqual(output["buffer"][6..7].unpack("n")[0],  1)

class SendRaw(unittest.TestCase):
    def test_raises_on_unknown_interfaces(self):
        { self.api.send_raw("BLAH_INT", "\x00\x01\x02\x03") }.to raise_error("Interface 'BLAH_INT' does not exist")

    def test_sends_raw_data_to_an_interface(self):
        self.api.send_raw("inst_int", "\x00\x01\x02\x03")
        sleep 0.1
        self.assertEqual(self.interface_data,  "\x00\x01\x02\x03")

    describe 'get_all_commands' do
    def test_complains_with_a_unknown_target(self):
        { self.api.get_all_commands("BLAH") }.to raise_error(/does not exist/)

    def test_returns_an_array_of_commands_as_hashes(self):
        result = self.api.get_all_commands("inst")
        self.assertEqual(result).to be_a Array
        for command in result:
          self.assertEqual(command).to be_a Hash
          self.assertEqual(command['target_name'], ("INST"))
          self.assertIn([*%w(target_name packet_name description endianness items)], command.keys)

    describe 'get_all_command_names' do
    def test_returns_empty_array_with_a_unknown_target(self):
        self.assertEqual(self.api.get_all_command_names("BLAH"),  [])

    def test_returns_an_array_of_command_names(self):
        result = self.api.get_all_command_names("inst")
        self.assertEqual(result).to be_a Array
        self.assertEqual(result[0]).to be_a String

class GetParameter(unittest.TestCase):
    def test_returns_parameter_hash_for_state_parameter(self):
        result = self.api.get_parameter("inst", "Collect", "Type")
        self.assertEqual(result['name'],  "TYPE")
        self.assertEqual(result['states'].keys.sort,  %w[NORMAL SPECIAL])
        self.assertIn(["value" : 0], result['states']['NORMAL'])
        self.assertIn(["value" : 1, "hazardous" : ""], result['states']['SPECIAL'])

    def test_returns_parameter_hash_for_array_parameter(self):
        result = self.api.get_parameter("INST", "ARYCMD", "ARRAY")
        self.assertEqual(result['name'],  "ARRAY")
        self.assertEqual(result['bit_size'],  64)
        self.assertEqual(result['array_size'],  640)
        self.assertEqual(result['data_type'],  "FLOAT")

    describe 'get_command' do
    def test_returns_hash_for_the_command_and_parameters(self):
        result = self.api.get_command("inst", "Collect")
        self.assertEqual(result).to be_a Hash
        self.assertEqual(result['target_name'],  "INST")
        self.assertEqual(result['packet_name'],  "COLLECT")
        for parameter in result['items']:
          self.assertEqual(parameter).to be_a Hash
          if Packet='RESERVED_ITEM_NAMES'.include?(parameter['name']):
            # Reserved items don't have default, min, max
            self.assertIn([*%w(name bit_offset bit_size data_type description endianness overflow)], parameter.keys)
          else:
            self.assertIn([*%w(name bit_offset bit_size data_type description default minimum maximum endianness overflow)], parameter.keys)

          # Check a few of the parameters
          if parameter['name'] == 'TYPE':
            self.assertEqual(parameter['default'],  0)
            self.assertEqual(parameter['data_type'],  "UINT")
            self.assertEqual(parameter['states'], ({ "NORMAL" : { "value" : 0 }, "SPECIAL" : { "value" : 1, "hazardous" : "" } }))
            self.assertEqual(parameter['description'],  "Collect type")
            self.assertTrue(parameter['required'])
            self.assertIsNone(parameter['units'])
          if parameter['name'] == 'TEMP':
            self.assertEqual(parameter['default'],  0.0)
            self.assertEqual(parameter['data_type'],  "FLOAT")
            self.assertIsNone(parameter['states'])
            self.assertEqual(parameter['description'],  "Collect temperature")
            self.assertEqual(parameter['units_full'],  "Celsius")
            self.assertEqual(parameter['units'],  "C")
            self.assertFalse(parameter['required'])

class GetCmdHazardous(unittest.TestCase):
    def test_returns_whether_the_command_with_parameters_is_hazardous(self):
        self.assertFalse(self.api.get_cmd_hazardous("inst collect with type NORMAL"))
        self.assertTrue(self.api.get_cmd_hazardous("INST COLLECT with TYPE SPECIAL"))

        self.assertFalse(self.api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" : "NORMAL" }))
        self.assertTrue(self.api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" : "SPECIAL" }))
        self.assertFalse(self.api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" : 0 }))
        self.assertTrue(self.api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" : 1 }))

    def test_returns_whether_the_command_is_hazardous(self):
        self.assertTrue(self.api.get_cmd_hazardous("INST CLEAR"))
        self.assertTrue(self.api.get_cmd_hazardous("INST", "CLEAR"))

    def test_raises_with_the_wrong_number_of_arguments(self):
        { self.api.get_cmd_hazardous("INST", "COLLECT", "TYPE", "SPECIAL") }.to raise_error(/Invalid number of arguments/)

class GetCmdValue(unittest.TestCase):
    def test_returns_command_values(self):
        time = Time.now
        self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.1
        self.assertEqual(self.api.get_cmd_value("inst", "collect", "type"),  'NORMAL')
        self.assertEqual(self.api.get_cmd_value("INST", "COLLECT", "DURATION"),  5.0)
        self.assertEqual(self.api.get_cmd_value("INST", "COLLECT", "RECEIVED_TIMESECONDS")).to be_within(0.1).of( float(time))
        self.assertEqual(self.api.get_cmd_value("INST", "COLLECT", "PACKET_TIMESECONDS")).to be_within(0.1).of( float(time))
        self.assertEqual(self.api.get_cmd_value("INST", "COLLECT", "RECEIVED_COUNT"),  1)

        self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 7")
        sleep 0.1
        self.assertEqual(self.api.get_cmd_value("INST", "COLLECT", "RECEIVED_COUNT"),  2)
        self.assertEqual(self.api.get_cmd_value("INST", "COLLECT", "DURATION"),  7.0)

class GetCmdTime(unittest.TestCase):
    def test_returns_command_times(self):
        time = Time.now
        self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.1
        result = self.api.get_cmd_time("inst", "collect")
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("COLLECT"))
        self.assertEqual(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        self.assertEqual(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        result = self.api.get_cmd_time("INST")
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("COLLECT"))
        self.assertEqual(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        self.assertEqual(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        result = self.api.get_cmd_time()
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("COLLECT"))
        self.assertEqual(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        self.assertEqual(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        time = Time.now
        self.api.cmd("INST ABORT")
        sleep 0.1
        result = self.api.get_cmd_time("INST")
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("ABORT") # New latest is ABORT)
        self.assertEqual(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        self.assertEqual(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        result = self.api.get_cmd_time()
        self.assertEqual(result[0], ("INST"))
        self.assertEqual(result[1], ("ABORT"))
        self.assertEqual(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        self.assertEqual(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

    def test_returns_0_if_no_times_are_set(self):
        self.assertEqual(self.api.get_cmd_time("INST", "ABORT"),  ["INST", "ABORT", 0, 0])
        self.assertEqual(self.api.get_cmd_time("INST"),  [None, None, 0, 0])
        self.assertEqual(self.api.get_cmd_time(),  [None, None, 0, 0])

class GetCmdCnt(unittest.TestCase):
    def test_complains_about_non_existant_targets(self):
        { self.api.get_cmd_cnt("BLAH", "ABORT") }.to raise_error("Packet 'BLAH ABORT' does not exist")

    def test_complains_about_non_existant_packets(self):
        { self.api.get_cmd_cnt("INST", "BLAH") }.to raise_error("Packet 'INST BLAH' does not exist")

    def test_returns_the_transmit_count(self):
        start = self.api.get_cmd_cnt("inst", "collect")
        self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        # Send unrelated commands to ensure specific command count
        self.api.cmd("INST ABORT")
        self.api.cmd_no_hazardous_check("INST CLEAR")
        sleep 0.1

        count = self.api.get_cmd_cnt("INST", "COLLECT")
        self.assertEqual(count,  start + 1)

class GetCmdCnts(unittest.TestCase):
    def test_returns_transmit_count_for_commands(self):
        self.api.cmd("INST ABORT")
        self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.1
        cnts = self.api.get_cmd_cnts([['inst','abort'],['INST','COLLECT']])
        self.assertEqual(cnts, ([1, 1]))
        self.api.cmd("INST ABORT")
        self.api.cmd("INST ABORT")
        self.api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.1
        cnts = self.api.get_cmd_cnts([['INST','ABORT'],['INST','COLLECT']])
        self.assertEqual(cnts, ([3, 2]))
