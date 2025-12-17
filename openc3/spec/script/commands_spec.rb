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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3'
require 'openc3/script'
load 'openc3/script/script.rb' # load to prevent prompt_for_hazardous overrides
require 'openc3/api/api'
require 'openc3/models/target_model'
require 'openc3/microservices/interface_microservice'
require 'openc3/microservices/decom_microservice'
require 'openc3/script/extract'
require 'openc3/utilities/authorization'

module OpenC3
  describe Script do
    class CommandsSpecApi
      include Extract
      include Api
      include Authorization
      def shutdown
      end

      def disconnect
      end

      def generate_url
        return "http://localhost:2900"
      end

      def method_missing(name, *params, **kw_params)
        self.send(name, *params, **kw_params)
      end
    end

    before(:each) do
      capture_io do |stdout|
        redis = mock_redis()
        setup_system()
        local_s3()

        @api = CommandsSpecApi.new
        # Mock the server proxy to directly call the api
        allow(ServerProxy).to receive(:new).and_return(@api)

        model = TargetModel.new(folder_name: 'INST', name: 'INST', scope: "DEFAULT")
        model.create
        model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
        model = InterfaceModel.new(name: "INST_INT", scope: "DEFAULT", target_names: ["INST"], cmd_target_names: ["INST"], tlm_target_names: ["INST"],config_params: ["interface.rb"])
        model.create
        model = InterfaceStatusModel.new(name: "INST_INT", scope: "DEFAULT", state: "ACTIVE")
        model.create

        # Create an Interface we can use in the InterfaceCmdHandlerThread
        # It has to have a valid list of target_names as that is what 'receive_commands'
        # in the Store uses to determine which topics to read
        @interface = Interface.new
        @interface.name = "INST_INT"
        @interface.target_names = %w[INST]
        @interface.cmd_target_names = %w[INST]
        @interface.tlm_target_names = %w[INST]
        @interface.cmd_target_enabled = {"INST" => true}
        @interface.tlm_target_enabled = {"INST" => true}

        # Stub to make the InterfaceCmdHandlerThread happy
        @interface_data = ''
        allow(@interface).to receive(:connected?).and_return(true)
        allow(@interface).to receive(:write_interface) { |data| @interface_data = data }
        @thread = InterfaceCmdHandlerThread.new(@interface, nil, scope: 'DEFAULT')
        @process = true # Allow the command to be processed or not
        @int_thread = Thread.new { @thread.run }
        sleep 0.01 # Allow thread to start

        allow(redis).to receive(:xread).and_wrap_original do |m, *args|
          # Only use the first two arguments as the last argument is keyword block:
          result = m.call(*args[0..1]) if @process
          # Create a slight delay to simulate the blocking call
          sleep 0.001 if result and result.length == 0
          result
        end
        initialize_script()
      end
    end

    after(:each) do
      local_s3_unset()
      shutdown_script()
      InterfaceTopic.shutdown(@interface, scope: 'DEFAULT')
      count = 0
      while (@int_thread.alive? or count < 100) do
        sleep 0.01
        count += 1
      end
    end

    %w(connected disconnected).each do |connect|
      context "with server #{connect}" do
        before(:each) do
          @prefix = '' # Empty if we're connected
          if connect == 'disconnected'
            disconnect_script()
            expect($api_server).to_not receive(:cmd)
            expect(CommandTopic).to_not receive(:send_command)
            @prefix = "DISCONNECT: "
          end
        end

        describe "cmd" do
          it "sends a command" do
            capture_io do |stdout|
              cmd("INST ABORT")
              expect(stdout.string).to match(/#{@prefix}cmd\(\"INST ABORT\"\)/) # "
              stdout.rewind
              cmd("INST", "ABORT")
              expect(stdout.string).to match(/#{@prefix}cmd\(\"INST ABORT\"\)/) # "
            end
          end

          it "raises without any parameters" do
            expect { cmd() }.to raise_error(/Invalid number of arguments/)
          end

          it "raises if a command item does not exist" do
            expect { cmd('INST COLLECT with TYPE NORMAL, DURATION 5, NOPE 10') }.to raise_error(/Packet item 'INST COLLECT NOPE' does not exist/)
          end

          if connect == 'connected'
            it "checks parameter ranges" do
              expect { cmd("INST COLLECT with TYPE NORMAL, DURATION 20") }.to raise_error(/Command parameter 'INST COLLECT DURATION' = 20 not in valid range/)
            end
          else
            it "does not check parameter ranges" do
              cmd("INST COLLECT with TYPE NORMAL, DURATION 20")
            end
          end

          it "sends with the hash parameter syntax" do
            expect { cmd("INST", "COLLECT", "TYPE" => "NORMAL", "DURATION" => 5) }.to_not raise_error
          end

          it "encodes binary data as BINARY in the output string" do
            capture_io do |stdout|
              cmd("INST", "MEMLOAD", "DATA" => "\x00\x01\x02\x03")
              expect(stdout.string).to match(/cmd\(\"INST MEMLOAD with DATA BINARY\"\)/)
            end
          end

          it "encodes array data in the output string" do
            capture_io do |stdout|
              cmd("INST", "ARYCMD", "ARRAY" => [1,2,3,4,5])
              expect(stdout.string).to match(/cmd\(\"INST ARYCMD with ARRAY \[1, 2, 3, 4, 5\]\"\)/)
            end
          end

          it "#{'has no' if connect == 'disconnected'} prompts for a hazardous command" do
            capture_io do |stdout|
              allow(self).to receive(:gets) { 'y' } if connect == 'connected' # Send hazardous command
              cmd("INST COLLECT with TYPE SPECIAL")
              expect(stdout.string).to match(/#{@prefix}cmd\(\"INST COLLECT/)
              if connect == 'connected'
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
                expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring range checks")
                expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring hazardous warnings")
                stdout.rewind
                cmd("INST COLLECT with TYPE SPECIAL")
                expect(stdout.string).to match(/#{@prefix}cmd\(\"INST COLLECT/)
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
              else
                expect(stdout.string).to_not match("Warning")
              end
            end
          end

          it "#{'has no' if connect == 'disconnected'} prompts for a hazardous command and handles obfuscation" do
          capture_io do |stdout|
            allow(self).to receive(:gets) { 'y' } if connect == 'connected' # Send hazardous command
            cmd("INST HAZARDOUS_SET_PASSWORD with PASSWORD password")
            expect(stdout.string).to match(/#{@prefix}cmd\(\"INST HAZARDOUS_SET_PASSWORD/)
            if connect == 'connected'
              expect(stdout.string).to match("Warning: Command INST HAZARDOUS_SET_PASSWORD is Hazardous")
              expect(stdout.string).to_not match("Command INST HAZARDOUS_SET_PASSWORD being sent ignoring range checks")
              expect(stdout.string).to_not match("Command INST HAZARDOUS_SET_PASSWORD being sent ignoring hazardous warnings")
              stdout.rewind
              cmd("INST HAZARDOUS_SET_PASSWORD with PASSWORD password")
              expect(stdout.string).to match(/#{@prefix}cmd\(\"INST HAZARDOUS_SET_PASSWORD with PASSWORD \*{5}/)
              expect(stdout.string).to match("Warning: Command INST HAZARDOUS_SET_PASSWORD is Hazardous")
            else
              expect(stdout.string).to_not match("Warning")
            end
          end
        end

          it "handles obfuscation" do
            capture_io do |stdout|
              expect { cmd("INST SET_PASSWORD with USERNAME username, PASSWORD password") }.not_to raise_error
              expect(stdout.string).to match(/cmd\("INST SET_PASSWORD with USERNAME \w+, PASSWORD \*{5}"\)/)
            end
          end
        end

        describe "cmd_no_range_check" do
          it "sends an out of range command" do
            expect { cmd_no_range_check("INST COLLECT with TYPE NORMAL, DURATION 20") }.to_not raise_error
          end

          it "#{'has no' if connect == 'disconnected'} prompts for a hazardous command" do
            capture_io do |stdout|
              allow(self).to receive(:gets) { 'y' } if connect == 'connected' # Send hazardous command
              cmd_no_range_check("INST COLLECT with TYPE SPECIAL")

              expect(stdout.string).to match(/#{@prefix}cmd\(\"INST COLLECT/) # "
              if connect == 'connected'
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
                expect(stdout.string).to match("Command INST COLLECT being sent ignoring range checks")
                expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring hazardous warnings")
                stdout.rewind
                cmd_no_range_check("INST COLLECT with TYPE SPECIAL")
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
              else
                expect(stdout.string).to_not match("Warning")
              end
            end
          end
        end

        describe "cmd_no_hazardous_check" do
          if connect == 'connected'
            it "checks parameter ranges" do
              expect { cmd_no_hazardous_check("INST COLLECT with TYPE SPECIAL, DURATION 20") }.to raise_error(/Command parameter 'INST COLLECT DURATION' = 20 not in valid range/)
            end
          else
            it "does not check parameter ranges" do
              cmd_no_hazardous_check("INST COLLECT with TYPE SPECIAL, DURATION 20")
            end
          end

          it "sends a hazardous command without prompting" do
            capture_io do |stdout|
              cmd_no_hazardous_check("INST COLLECT with TYPE SPECIAL")

              expect(stdout.string).to match(/#{@prefix}cmd\(\"INST COLLECT/) # "
              expect(stdout.string).to_not match("Warning: Command INST COLLECT is Hazardous")
              expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring range checks")
              expect(stdout.string).to match("Command INST COLLECT being sent ignoring hazardous warnings")
            end
          end
        end

        describe "cmd_no_checks" do
          it "sends an out of range hazardous command without prompting" do
            capture_io do |stdout|
              cmd_no_checks("INST COLLECT with TYPE SPECIAL, DURATION 20")

              expect(stdout.string).to match(/#{@prefix}cmd\(\"INST COLLECT/) # "
              expect(stdout.string).to_not match("Warning: Command INST COLLECT is Hazardous")
              expect(stdout.string).to match("Command INST COLLECT being sent ignoring range checks")
              expect(stdout.string).to match("Command INST COLLECT being sent ignoring hazardous warnings")
            end
          end
        end

        describe "cmd_raw" do
          it "sends a command" do
            capture_io do |stdout|
              cmd_raw("INST ABORT")
              expect(stdout.string).to match(/#{@prefix}cmd_raw\(\"INST ABORT\"\)/) # "
            end
          end

          if connect == 'connected'
            it "checks parameter ranges" do
              expect { cmd_raw("INST COLLECT with TYPE 0, DURATION 20") }.to raise_error(/Command parameter 'INST COLLECT DURATION' = 20 not in valid range/)
            end
          else
            it "does not check parameter ranges" do
              cmd_raw("INST COLLECT with TYPE 0, DURATION 20")
            end
          end

          it "#{'has no' if connect == 'disconnected'} prompts for a hazardous command" do
            capture_io do |stdout|
              allow(self).to receive(:gets) { 'y' } if connect == 'connected' # Send hazardous command
              cmd_raw("INST COLLECT with TYPE 1")

              expect(stdout.string).to match(/#{@prefix}cmd_raw\(\"INST COLLECT/) # "
              if connect == 'connected'
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
                expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring range checks")
                expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring hazardous warnings")
                stdout.rewind
                cmd_raw("INST COLLECT with TYPE 1")
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
              else
                expect(stdout.string).to_not match("Warning")
              end
            end
          end
        end

        describe "cmd_raw_no_range_check" do
          it "sends an out of range command" do
            expect { cmd_raw_no_range_check("INST COLLECT with TYPE 0, DURATION 20") }.to_not raise_error
          end

          it "#{'has no' if connect == 'disconnected'} prompts for a hazardous command" do
            capture_io do |stdout|
              allow(self).to receive(:gets) { 'y' } if connect == 'connected' # Send hazardous command
              cmd_raw_no_range_check("INST COLLECT with TYPE 1")

              expect(stdout.string).to match(/#{@prefix}cmd_raw\(\"INST COLLECT/) # "
              if connect == 'connected'
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
                expect(stdout.string).to match("Command INST COLLECT being sent ignoring range checks")
                expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring hazardous warnings")
                stdout.rewind
                cmd_raw_no_range_check("INST COLLECT with TYPE 1")
                expect(stdout.string).to match("Warning: Command INST COLLECT is Hazardous")
              else
                expect(stdout.string).to_not match("Warning")
              end
            end
          end
        end

        describe "cmd_raw_no_hazardous_check" do
          if connect == 'connected'
            it "checks parameter ranges" do
              expect { cmd_raw_no_hazardous_check("INST COLLECT with TYPE 1, DURATION 20") }.to raise_error(/Command parameter 'INST COLLECT DURATION' = 20 not in valid range/)
            end
          else
            it "does not check parameter ranges" do
              cmd_raw_no_hazardous_check("INST COLLECT with TYPE 1, DURATION 20")
            end
          end

          it "sends a hazardous command without prompting" do
            capture_io do |stdout|
              cmd_raw_no_hazardous_check("INST COLLECT with TYPE 1")
              expect(stdout.string).to match(/#{@prefix}cmd_raw\(\"INST COLLECT/) # "
              expect(stdout.string).to_not match("Warning: Command INST COLLECT is Hazardous")
              expect(stdout.string).to_not match("Command INST COLLECT being sent ignoring range checks")
              expect(stdout.string).to match("Command INST COLLECT being sent ignoring hazardous warnings")
            end
          end
        end

        describe "cmd_raw_no_checks" do
          it "sends an out of range hazardous command without prompting" do
            capture_io do |stdout|
              cmd_raw_no_checks("INST COLLECT with TYPE 1, DURATION 20")
              expect(stdout.string).to match(/#{@prefix}cmd_raw\(\"INST COLLECT/) # "
              expect(stdout.string).to_not match("Warning: Command INST COLLECT is Hazardous")
              expect(stdout.string).to match("Command INST COLLECT being sent ignoring range checks")
              expect(stdout.string).to match("Command INST COLLECT being sent ignoring hazardous warnings")
            end
          end
        end

        describe "get_cmd_hazardous" do
          it "returns whether a command is hazardous" do
            expect(get_cmd_hazardous("INST ABORT")).to be false
            expect(get_cmd_hazardous("INST CLEAR")).to be true
            expect(get_cmd_hazardous("inst collect with type NORMAL")).to be false
            expect(get_cmd_hazardous("INST COLLECT with TYPE SPECIAL")).to be true
          end
        end

        describe "build_cmd" do
          before(:each) do
            model = MicroserviceModel.new(name: "DEFAULT__DECOM__INST_INT", scope: "DEFAULT",
              topics: ["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"], target_names: ['INST'])
            model.create
            @dm = DecomMicroservice.new("DEFAULT__DECOM__INST_INT")
            @dm_thread = Thread.new { @dm.run }
            sleep(0.1)
          end

          after(:each) do
            @dm.shutdown
            sleep(0.1)
          end

          it "builds a command" do
            cmd = build_cmd("INST ABORT")
            expect(cmd['target_name']).to eql 'INST'
            expect(cmd['packet_name']).to eql 'ABORT'
            expect(cmd['buffer']).to eql "\x13\xE7\xC0\x00\x00\x00\x00\x02" # Pkt ID 2
          end

          it "builds a command with parameters" do
            cmd = @api.build_cmd("inst", "Collect", "TYPE" => "NORMAL", "Duration" => 5)
            expect(cmd['target_name']).to eql 'INST'
            expect(cmd['packet_name']).to eql 'COLLECT'
            expect(cmd['buffer']).to eql "\x13\xE7\xC0\x00\x00\x00\x00\x01\x00\x00@\xA0\x00\x00\xAB\x00\x00\x00\x00"
          end
        end

        describe "send_raw" do
          it "sends data to the write_raw interface method" do
            send_raw('INST_INT', "\x00\x01\x02\x03")
            sleep 0.1
            expect(@interface_data).to eql "\x00\x01\x02\x03" if connect == 'connected'
          end
        end

        describe "get_cmd_time" do
          it "creates an actual Ruby Time value" do
            _, _, time = get_cmd_time()
            expect(time).to be_a(Time)
          end
        end
      end
    end
  end
end
