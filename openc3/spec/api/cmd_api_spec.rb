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
require 'openc3/api/cmd_api'
require 'openc3/microservices/interface_microservice'
require 'openc3/script/extract'
require 'openc3/utilities/authorization'
require 'openc3/microservices/decom_microservice'
require 'openc3/models/target_model'
require 'openc3/models/interface_model'
require 'openc3/topics/telemetry_decom_topic'


module OpenC3
  describe Api do
    class ApiTest
      include Extract
      include Api
      include Authorization
    end

    before(:each) do
      redis = mock_redis()
      setup_system()
      local_s3()

      require 'openc3/models/target_model'
      model = TargetModel.new(folder_name: 'INST', name: 'INST', scope: "DEFAULT")
      model.create
      model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      model = InterfaceModel.new(name: "INST_INT", scope: "DEFAULT", target_names: ["INST"], cmd_target_names: ["INST"], tlm_target_names: ["INST"], config_params: ["interface.rb"])
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

      allow(redis).to receive(:xread).and_wrap_original do |m, *args|
        # Only use the first two arguments as the last argument is keyword block:
        result = nil
        result = m.call(*args[0..1]) if @process
        # Create a slight delay to simulate the blocking call
        sleep 0.001 if result and result.length == 0
        result
      end

      @int_thread = Thread.new { @thread.run }
      sleep 0.001 # Allow thread to spin up
      @api = ApiTest.new
    end

    after(:each) do
      local_s3_unset()
      InterfaceTopic.shutdown(@interface, scope: 'DEFAULT')
      count = 0
      while @int_thread.alive? or count < 100 do
        sleep 0.001
        count += 1
      end
    end

    def test_cmd_unknown(method)
      expect { @api.send(method, "BLAH COLLECT with TYPE NORMAL") }.to raise_error(/does not exist/)
      expect { @api.send(method, "INST UNKNOWN with TYPE NORMAL") }.to raise_error(/does not exist/)
      expect { @api.send(method, "BLAH", "COLLECT", "TYPE" => "NORMAL") }.to raise_error(/does not exist/)
      expect { @api.send(method, "INST", "UNKNOWN", "TYPE" => "NORMAL") }.to raise_error(/does not exist/)
    end

    %w(cmd cmd_no_checks cmd_no_range_check cmd_no_hazardous_check cmd_raw cmd_raw_no_checks cmd_raw_no_range_check cmd_raw_no_hazardous_check).each do |method|
      describe method do
        it "complains about unknown targets, commands, and parameters" do
          test_cmd_unknown(method.intern)
        end

        it "processes a string" do
          type = method.include?('raw') ? 0 : 'NORMAL'
          command = @api.send(method, "inst Collect with type #{type}, Duration 5")
          expect(command['target_name']).to eql 'INST'
          expect(command['cmd_name']).to eql 'COLLECT'
          expect(command['cmd_params']).to include('TYPE' => type, 'DURATION' => 5)
        end

        it "complains if parameters are not separated by commas" do
          expect { @api.send(method, "INST COLLECT with TYPE NORMAL DURATION 5") }.to raise_error(/Missing comma/)
        end

        it "complains if parameters don't have values" do
          expect { @api.send(method, "INST COLLECT with TYPE") }.to raise_error(/Missing value/)
        end

        it "processes parameters" do
          type = method.include?('raw') ? 0 : 'NORMAL'
          command = @api.send(method, "inst", "Collect", "TYPE" => type, "Duration" => 5)
          expect(command['target_name']).to eql 'INST'
          expect(command['cmd_name']).to eql 'COLLECT'
          expect(command['cmd_params']).to include('TYPE' => type, 'DURATION' => 5)
        end

        it "processes commands without parameters" do
          command = @api.send(method, "INST", "ABORT")
          expect(command['target_name']).to eql 'INST'
          expect(command['cmd_name']).to eql 'ABORT'
          expect(command['cmd_params']).to be {}
        end

        it "complains about too many parameters" do
          expect { @api.send(method, "INST", "COLLECT", "TYPE", "DURATION") }.to raise_error(/Invalid number of arguments/)
        end

        it "warns about required parameters" do
          expect { @api.send(method, "INST COLLECT with DURATION 5") }.to raise_error(/Required/)
        end

        it "warns about out of range parameters" do
          type = method.include?('raw') ? 0 : 'NORMAL'
          if method.include?('no_checks') or method.include?('no_range')
            expect { @api.send(method, "INST COLLECT with TYPE #{type}, DURATION 1000") }.not_to raise_error
          else
            expect { @api.send(method, "INST COLLECT with TYPE #{type}, DURATION 1000") }.to raise_error(/not in valid range/)
          end
        end

        it "warns about bad state parameters" do
          if method.include?('raw')
            type = 2
            check = '0, 1'
          else
            type = 'OTHER'
            check = 'NORMAL, SPECIAL'
          end
          if method.include?('no_checks') or method.include?('no_range')
            if method.include?('raw')
              # If we're using raw commands, we can set any state parameter because it's numeric
              expect { @api.send(method, "INST COLLECT with TYPE #{type}, DURATION 10") }.not_to raise_error
            else
              # Non-raw commands still raise because the state parameter is checked during the write
              expect { @api.send(method, "INST COLLECT with TYPE #{type}, DURATION 10") }.to raise_error("Unknown state 'OTHER' for TYPE, must be one of NORMAL, SPECIAL")
            end
          else
            # cmd(), cmd_raw() and (no_hazardous_check variants) check the state parameter and raise
            expect { @api.send(method, "INST COLLECT with TYPE #{type}, DURATION 10") }.to raise_error("Command parameter 'INST COLLECT TYPE' = #{type} not one of #{check}")
          end
        end

        it "warns about hazardous parameters" do
          type = method.include?('raw') ? 1 : 'SPECIAL'
          if method.include?('no_checks') or method.include?('no_hazard')
            expect { @api.send(method, "INST COLLECT with TYPE #{type}") }.not_to raise_error
          else
            expect { @api.send(method, "INST COLLECT with TYPE #{type}") }.to raise_error(/Hazardous/)
          end
        end

        it "warns about hazardous commands" do
          if method.include?('no_checks') or method.include?('no_hazard')
            expect { @api.send(method, "INST CLEAR") }.not_to raise_error
          else
            expect { @api.send(method, "INST CLEAR") }.to raise_error(/Hazardous/)
          end
        end

        it "does not send disabled commands" do
          expect { @api.send(method, "INST DISABLED") }.to raise_error(DisabledError, "INST DISABLED is Disabled")
        end

        it "times out if the interface does not process the command" do
          expect { @api.send(method, "INST", "ABORT", timeout: true) }.to raise_error("Invalid timeout parameter: true. Must be numeric.")
          expect { @api.send(method, "INST", "ABORT", timeout: false) }.to raise_error("Invalid timeout parameter: false. Must be numeric.")
          expect { @api.send(method, "INST", "ABORT", timeout: "YES") }.to raise_error("Invalid timeout parameter: YES. Must be numeric.")
          begin
            @process = false
            expect { @api.send(method, "INST", "ABORT", timeout: 0.003) }.to raise_error("Timeout of 0.003s waiting for cmd ack")
          ensure
            @process = true
          end
        end

        it "does not log a message if the packet has DISABLE_MESSAGES" do
          message = nil
          allow(Logger).to receive(:info) do |args|
            message = args
          end
          # Check that binary commands work and are logged with correct formatting
          @api.send(method, "INST", "MEMLOAD", "DATA" => "\xAA\xBB\xCC\xDD\xEE\xFF", log_message: true)
          expect(message).to eql "#{method}(\"INST MEMLOAD with DATA 0xAABBCCDDEEFF\")"
          @api.send(method, "INST ABORT")
          expect(message).to eql "#{method}(\"INST ABORT\")"
          message = nil
          @api.send(method, "INST ABORT", log_message: false) # Don't log
          expect(message).to be nil
          @api.send(method, "INST SETPARAMS") # This has DISABLE_MESSAGES applied
          expect(message).to be nil
          @api.send(method, "INST SETPARAMS", log_message: true) # Force log
          expect(message).to eql "#{method}(\"INST SETPARAMS\")"
          # Check that array parameters are logged correctly
          @api.send(method, "INST ARYCMD with ARRAY [1, 2, 3, 4]")
          expect(message).to eql "#{method}(\"INST ARYCMD with ARRAY [1, 2, 3, 4]\")"
          message = nil
          @api.send(method, "INST ASCIICMD with STRING 'NOOP'") # NOOP has DISABLE_MESSAGES applied to the parameter
          expect(message).to be nil
          @api.send(method, "INST ASCIICMD with STRING 'NOOP'", log_message: true) # Force log
          expect(message).to eql "#{method}(\"INST ASCIICMD with STRING 'NOOP'\")"
          message = nil
          # Send bad log_message parameters
          expect { @api.send(method, "INST SETPARAMS", log_message: 0) }.to raise_error("Invalid log_message parameter: 0. Must be true or false.")
          expect { @api.send(method, "INST SETPARAMS", log_message: "YES") }.to raise_error("Invalid log_message parameter: YES. Must be true or false.")
          @api.send(method, "INST SETPARAMS", log_message: nil) # This actually works because nil is the default
          expect(message).to be nil
        end
      end
    end

    describe "build_cmd" do
      before(:each) do
        model = MicroserviceModel.new(name: "DEFAULT__DECOM__INST_INT", scope: "DEFAULT",
          topics: ["DEFAULT__TELEMETRY__{INST}__HEALTH_STATUS"], target_names: ['INST'])
        model.create
        @dm = DecomMicroservice.new("DEFAULT__DECOM__INST_INT")
        @dm_thread = Thread.new { @dm.run }
        sleep 0.001
      end

      after(:each) do
        @dm.shutdown
        sleep 0.001
      end

      it "complains about unknown targets" do
        expect { @api.build_cmd("BLAH COLLECT", timeout: 0.001) }.to raise_error(/Timeout of 0.001s waiting for cmd ack. Does target 'BLAH' exist?/)
      end

      it "complains about unknown commands" do
        expect { @api.build_cmd("INST", "BLAH") }.to raise_error(/does not exist/)
      end

      it "processes a string" do
        cmd = @api.build_cmd("inst Collect with type NORMAL, Duration 5")
        expect(cmd['target_name']).to eql 'INST'
        expect(cmd['packet_name']).to eql 'COLLECT'
        expect(cmd['buffer']).to eql "\x13\xE7\xC0\x00\x00\x00\x00\x01\x00\x00@\xA0\x00\x00\xAB\x00\x00\x00\x00"
      end

      it "complains if parameters are not separated by commas" do
        expect { @api.build_cmd("INST COLLECT with TYPE NORMAL DURATION 5") }.to raise_error(/Missing comma/)
      end

      it "complains if parameters don't have values" do
        expect { @api.build_cmd("INST COLLECT with TYPE") }.to raise_error(/Missing value/)
      end

      it "processes parameters" do
        cmd = @api.build_cmd("inst", "Collect", "TYPE" => "NORMAL", "Duration" => 5)
        expect(cmd['target_name']).to eql 'INST'
        expect(cmd['packet_name']).to eql 'COLLECT'
        expect(cmd['buffer']).to eql "\x13\xE7\xC0\x00\x00\x00\x00\x01\x00\x00@\xA0\x00\x00\xAB\x00\x00\x00\x00"
      end

      it "processes commands without parameters" do
        cmd = @api.build_cmd("INST", "ABORT")
        expect(cmd['target_name']).to eql 'INST'
        expect(cmd['packet_name']).to eql 'ABORT'
        expect(cmd['buffer']).to eql "\x13\xE7\xC0\x00\x00\x00\x00\x02" # Pkt ID 2

        cmd = @api.build_cmd("INST CLEAR")
        expect(cmd['target_name']).to eql 'INST'
        expect(cmd['packet_name']).to eql 'CLEAR'
        expect(cmd['buffer']).to eql "\x13\xE7\xC0\x00\x00\x00\x00\x03" # Pkt ID 3
      end

      it "complains about too many parameters" do
        expect { @api.build_cmd("INST", "COLLECT", "TYPE", "DURATION") }.to raise_error(/Invalid number of arguments/)
      end

      it "warns about required parameters" do
        expect { @api.build_cmd("INST COLLECT with DURATION 5") }.to raise_error(/Required/)
      end

      it "warns about out of range parameters" do
        expect { @api.build_cmd("INST COLLECT with TYPE NORMAL, DURATION 1000") }.to raise_error(/not in valid range/)
        cmd = @api.build_cmd("INST COLLECT with TYPE NORMAL, DURATION 1000", range_check: false)
        expect(cmd['target_name']).to eql 'INST'
        expect(cmd['packet_name']).to eql 'COLLECT'
      end
    end

    describe "enable_cmd / disable_cmd" do
      it "complains about unknown commands" do
        expect { @api.enable_cmd("INST", "BLAH") }.to raise_error(/does not exist/)
        expect { @api.disable_cmd("INST BLAH") }.to raise_error(/does not exist/)
      end

      it "complains if no packet given" do
        expect { @api.enable_cmd("INST") }.to raise_error(/Target name and command name required/)
        expect { @api.disable_cmd("INST") }.to raise_error(/Target name and command name required/)
      end

      it "disables and enables a command" do
        @api.cmd("INST ABORT")
        @api.disable_cmd("INST", "ABORT")
        expect { @api.cmd("INST ABORT") }.to raise_error('INST ABORT is Disabled')
        @api.enable_cmd("INST ABORT")
        @api.cmd("INST ABORT")
      end
    end

    describe "get_cmd_buffer" do
      it "complains about unknown commands" do
        expect { @api.get_cmd_buffer("INST", "BLAH") }.to raise_error(/does not exist/)
        expect { @api.get_cmd_buffer("INST BLAH") }.to raise_error(/does not exist/)
      end

      it "complains if no packet given" do
        expect { @api.get_cmd_buffer("INST") }.to raise_error(/Target name and command name required/)
      end

      it "returns nil if the command has not yet been sent" do
        expect(@api.get_cmd_buffer("INST", "ABORT")).to be_nil
        expect(@api.get_cmd_buffer("INST ABORT")).to be_nil
      end

      it "returns a command packet buffer" do
        @api.cmd("INST ABORT")
        output = @api.get_cmd_buffer("inst", "Abort")
        expect(output["buffer"][6..7].unpack("n")[0]).to eq 2
        output = @api.get_cmd_buffer("inst   Abort")
        expect(output["buffer"][6..7].unpack("n")[0]).to eq 2
        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        output = @api.get_cmd_buffer("INST", "COLLECT")
        expect(output["buffer"][6..7].unpack("n")[0]).to eq 1
        output = @api.get_cmd_buffer("INST COLLECT")
        expect(output["buffer"][6..7].unpack("n")[0]).to eq 1
      end
    end

    describe "send_raw" do
      it "raises on unknown interfaces" do
        expect { @api.send_raw("BLAH_INT", "\x00\x01\x02\x03") }.to raise_error("Interface 'BLAH_INT' does not exist")
      end

      it "sends raw data to an interface" do
        @api.send_raw("inst_int", "\x00\x01\x02\x03")
        sleep 0.001
        expect(@interface_data).to eql "\x00\x01\x02\x03"
      end

      it "sends raw data to an interface" do
        @api.send_raw("inst_int", "\x00\x01\x02\x03")
        sleep 0.001
        expect(@interface_data).to eql "\x00\x01\x02\x03"
      end
    end

    describe 'get_all_cmds' do
      it "complains with a unknown target" do
        expect { @api.get_all_cmds("BLAH") }.to raise_error(/does not exist/)
      end

      it "returns an array of commands as hashes" do
        result = @api.get_all_cmds("inst")
        expect(result).to be_a Array
        result.each do |command|
          expect(command).to be_a Hash
          expect(command['target_name']).to eql("INST")
          expect(command.keys).to include(*%w(target_name packet_name description endianness items))
        end
      end
    end

    describe 'get_all_cmd_names' do
      it "returns empty array with a unknown target" do
        expect(@api.get_all_cmd_names("BLAH")).to eql []
      end

      it "returns an array of command names" do
        result = @api.get_all_cmd_names("inst")
        expect(result).to be_a Array
        expect(result[0]).to be_a String
      end
    end

    describe "get_param" do
      it "returns parameter hash for state parameter" do
        result = @api.get_param("inst", "Collect", "Type")
        expect(result['name']).to eql "TYPE"
        expect(result['states'].keys.sort).to eql %w[NORMAL SPECIAL]
        expect(result['states']['NORMAL']).to include("value" => 0)
        expect(result['states']['SPECIAL']).to include("value" => 1, "hazardous" => "")
      end

      it "returns parameter hash for array parameter" do
        result = @api.get_param("INST", "ARYCMD", "ARRAY")
        expect(result['name']).to eql "ARRAY"
        expect(result['bit_size']).to eql 64
        expect(result['array_size']).to eql 640
        expect(result['data_type']).to eql "FLOAT"
      end
    end

    describe 'get_cmd' do
      it "returns hash for the command and parameters" do
        result = @api.get_cmd("inst", "Collect")
        expect(result).to be_a Hash
        expect(result['target_name']).to eql "INST"
        expect(result['packet_name']).to eql "COLLECT"
        result['items'].each do |parameter|
          expect(parameter).to be_a Hash
          if Packet::RESERVED_ITEM_NAMES.include?(parameter['name'])
            # Reserved items don't have default, min, max
            expect(parameter.keys).to include(*%w(name bit_offset bit_size data_type description endianness overflow))
          else
            expect(parameter.keys).to include(*%w(name bit_offset bit_size data_type description default minimum maximum endianness overflow))
          end

          # Check a few of the parameters
          if parameter['name'] == 'TYPE'
            expect(parameter['default']).to eql 0
            expect(parameter['data_type']).to eql "UINT"
            expect(parameter['states']).to eql({ "NORMAL" => { "value" => 0 }, "SPECIAL" => { "value" => 1, "hazardous" => "" } })
            expect(parameter['description']).to eql "Collect type"
            expect(parameter['required']).to be true
            expect(parameter['units']).to be_nil
          end
          if parameter['name'] == 'TEMP'
            expect(parameter['default']).to eql 0.0
            expect(parameter['data_type']).to eql "FLOAT"
            expect(parameter['states']).to be_nil
            expect(parameter['description']).to eql "Collect temperature"
            expect(parameter['units_full']).to eql "Celsius"
            expect(parameter['units']).to eql "C"
            expect(parameter['required']).to be false
          end
        end

        result = @api.get_cmd("inst  Collect")
        expect(result).to be_a Hash
        expect(result['target_name']).to eql "INST"
        expect(result['packet_name']).to eql "COLLECT"
      end
    end

    describe "get_cmd_hazardous" do
      it "returns whether the command with parameters is hazardous" do
        expect(@api.get_cmd_hazardous("inst collect with type NORMAL")).to be false
        expect(@api.get_cmd_hazardous("INST COLLECT with TYPE SPECIAL")).to be true

        expect(@api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" => "NORMAL" })).to be false
        expect(@api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" => "SPECIAL" })).to be true
        expect(@api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" => 0 })).to be false
        expect(@api.get_cmd_hazardous("INST", "COLLECT", { "TYPE" => 1 })).to be true
      end

      it "returns whether the command is hazardous" do
        expect(@api.get_cmd_hazardous("INST CLEAR")).to be true
        expect(@api.get_cmd_hazardous("INST", "CLEAR")).to be true
      end

      it "raises with the wrong number of arguments" do
        expect { @api.get_cmd_hazardous("INST", "COLLECT", "TYPE", "SPECIAL") }.to raise_error(/Invalid number of arguments/)
      end

      it "ignores the manual keyword" do
        @api.get_cmd_hazardous("INST CLEAR", manual: true)
      end
    end

    describe "get_cmd_value" do
      it "returns command values" do
        time = Time.now
        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.001
        expect(@api.get_cmd_value("inst collect type")).to eql 'NORMAL'
        expect(@api.get_cmd_value("inst collect type", type: :RAW)).to eql 0
        expect(@api.get_cmd_value("INST COLLECT DURATION")).to eql 5.0
        expect(@api.get_cmd_value("INST COLLECT RECEIVED_TIMESECONDS")).to be_within(0.1).of(time.to_f)
        expect(@api.get_cmd_value("INST COLLECT PACKET_TIMESECONDS")).to be_within(0.1).of(time.to_f)
        expect(@api.get_cmd_value("INST COLLECT RECEIVED_COUNT")).to eql 1

        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 7")
        sleep 0.001
        expect(@api.get_cmd_value("INST COLLECT RECEIVED_COUNT")).to eql 2
        expect(@api.get_cmd_value("INST COLLECT DURATION")).to eql 7.0
      end

      it "returns command values (DEPRECATED)" do
        time = Time.now
        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.001
        expect(@api.get_cmd_value("inst", "collect", "type")).to eql 'NORMAL'
        expect(@api.get_cmd_value("inst", "collect", "type", :RAW)).to eql 0
        expect(@api.get_cmd_value("INST", "COLLECT", "DURATION")).to eql 5.0
        expect(@api.get_cmd_value("INST", "COLLECT", "RECEIVED_TIMESECONDS")).to be_within(0.1).of(time.to_f)
        expect(@api.get_cmd_value("INST", "COLLECT", "PACKET_TIMESECONDS")).to be_within(0.1).of(time.to_f)
        expect(@api.get_cmd_value("INST", "COLLECT", "RECEIVED_COUNT")).to eql 1

        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 7")
        sleep 0.001
        expect(@api.get_cmd_value("INST", "COLLECT", "RECEIVED_COUNT")).to eql 2
        expect(@api.get_cmd_value("INST", "COLLECT", "DURATION")).to eql 7.0
      end
    end

    describe "get_cmd_time" do
      it "returns command times" do
        time = Time.now
        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.001
        result = @api.get_cmd_time("inst", "collect")
        expect(result[0]).to eq("INST")
        expect(result[1]).to eq("COLLECT")
        expect(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        expect(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        result = @api.get_cmd_time("INST")
        expect(result[0]).to eq("INST")
        expect(result[1]).to eq("COLLECT")
        expect(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        expect(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        result = @api.get_cmd_time()
        expect(result[0]).to eq("INST")
        expect(result[1]).to eq("COLLECT")
        expect(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        expect(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        time = Time.now
        @api.cmd("INST ABORT")
        sleep 0.001
        result = @api.get_cmd_time("INST")
        expect(result[0]).to eq("INST")
        expect(result[1]).to eq("ABORT") # New latest is ABORT
        expect(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        expect(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms

        result = @api.get_cmd_time()
        expect(result[0]).to eq("INST")
        expect(result[1]).to eq("ABORT")
        expect(result[2]).to be_within(1).of(time.tv_sec) # Allow 1s for rounding
        expect(result[3]).to be_within(50_000).of(time.tv_usec) # Allow 50ms
      end

      it "returns 0 if no times are set" do
        expect(@api.get_cmd_time("INST", "ABORT")).to eql ["INST", "ABORT", 0, 0]
        expect(@api.get_cmd_time("INST")).to eql [nil, nil, 0, 0]
        expect(@api.get_cmd_time()).to eql [nil, nil, 0, 0]
      end
    end

    describe "get_cmd_cnt" do
      it "complains about non-existent targets" do
        expect { @api.get_cmd_cnt("BLAH", "ABORT") }.to raise_error("Packet 'BLAH ABORT' does not exist")
        expect { @api.get_cmd_cnt("BLAH ABORT") }.to raise_error("Packet 'BLAH ABORT' does not exist")
      end

      it "complains about non-existent packets" do
        expect { @api.get_cmd_cnt("INST", "BLAH") }.to raise_error("Packet 'INST BLAH' does not exist")
      end

      it "returns the transmit count" do
        start = @api.get_cmd_cnt("inst", "collect")
        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        # Send unrelated commands to ensure specific command count
        @api.cmd("INST ABORT")
        @api.cmd_no_hazardous_check("INST CLEAR")
        sleep 0.001

        count = @api.get_cmd_cnt("INST", "COLLECT")
        expect(count).to eql start + 1
        count = @api.get_cmd_cnt("INST   COLLECT")
        expect(count).to eql start + 1
      end
    end

    describe "get_cmd_cnts" do
      it "returns transmit count for commands" do
        @api.cmd("INST ABORT")
        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.001
        cnts = @api.get_cmd_cnts([['inst','abort'],['INST','COLLECT']])
        expect(cnts).to eql([1, 1])
        @api.cmd("INST ABORT")
        @api.cmd("INST ABORT")
        @api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")
        sleep 0.001
        cnts = @api.get_cmd_cnts([['INST','ABORT'],['INST','COLLECT']])
        expect(cnts).to eql([3, 2])
      end
    end

    describe "obfuscate cmd" do
      it "obfuscates parameters in command" do
        message = nil
        allow(Logger).to receive(:info) do |args|
          message = args
        end
        expect { @api.cmd("INST SET_PASSWORD with USERNAME username, PASSWORD password, KEY key") }.not_to raise_error
        sleep 0.001
        expect(message).to eql "cmd(\"INST SET_PASSWORD with USERNAME 'username', PASSWORD *****, KEY *****\")"
      end
    end
  end
end
