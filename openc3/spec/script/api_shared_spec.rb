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
require 'openc3'
require 'openc3/script'
require 'openc3/api/api'
require 'openc3/models/target_model'
require 'openc3/microservices/interface_microservice'
require 'openc3/script/extract'
require 'openc3/utilities/authorization'

module OpenC3
  describe Script do
    class ApiTest
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

    def openc3_script_sleep(sleep_time = nil)
      @sleep_cancel
    end

    before(:each) do
      mock_redis()
      setup_system()

      @sleep_cancel = false
      @api = ApiTest.new
      # Mock the server proxy to directly call the api
      allow(ServerProxy).to receive(:new).and_return(@api)
      @count = true
      received_count = 0
      allow(CvtModel).to receive(:get_item) do |*args, **kwargs|
        case args[2]
        when 'TEMP1'
          case kwargs[:type]
          when :RAW
            1
          when :CONVERTED
            10
          when :FORMATTED
            '10.000'
          when :WITH_UNITS
            '10.000 C'
          end
        when 'TEMP2'
          case kwargs[:type]
          when :RAW
            1.5
          when :CONVERTED
            10.5
          end
        when 'CCSDSSHF'
          'FALSE'
        when 'RECEIVED_COUNT'
          if @count
            received_count += 1
            received_count
          else
            nil
          end
        when 'ARY'
          [2,3,4]
        else
          nil
        end
      end

      model = TargetModel.new(folder_name: 'INST', name: 'INST', scope: "DEFAULT")
      model.create
      model.update_store(System.new(['INST'], File.join(SPEC_DIR, 'install', 'config', 'targets')))
      # model = InterfaceModel.new(name: "INST_INT", scope: "DEFAULT", target_names: ["INST"], config_params: ["interface.rb"])
      # model.create
      # model = InterfaceStatusModel.new(name: "INST_INT", scope: "DEFAULT", state: "ACTIVE")
      # model.create

      # Create an Interface we can use in the InterfaceCmdHandlerThread
      # It has to have a valid list of target_names as that is what 'receive_commands'
      # in the Store uses to determine which topics to read
      # interface = Interface.new
      # interface.name = "INST_INT"
      # interface.target_names = %w[INST]
      # # Stub to make the InterfaceCmdHandlerThread happy
      # @interface_data = ''
      # allow(interface).to receive(:connected?).and_return(true)
      # allow(interface).to receive(:write_interface) { |data| @interface_data = data }
      # @thread = InterfaceCmdHandlerThread.new(interface, nil, scope: 'DEFAULT')
      # @process = true # Allow the command to be processed or not
      # @int_thread = Thread.new { @thread.run }
      # sleep 0.01 # Allow thread to start

      # allow(redis).to receive(:xread).and_wrap_original do |m, *args|
      #   # Only use the first two arguments as the last argument is keyword block:
      #   result = m.call(*args[0..1]) if @process
      #   # Create a slight delay to simulate the blocking call
      #   sleep 0.001 if result and result.length == 0
      #   result
      # end
      initialize_script()
    end

    after(:each) do
      shutdown_script()
    end

    describe "check" do
      it "checks a telemetry item against a value" do
        capture_io do |stdout|
          check("INST", "HEALTH_STATUS", "TEMP1", "> 1")
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 > 1 success with value == 10/)
          check("INST HEALTH_STATUS TEMP1 == 1", type: :RAW)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 == 1 success with value == 1/)
        end
        expect { check("INST HEALTH_STATUS TEMP1 > 100") }.to raise_error(/CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10/)
      end

      it "warns when checking a state against a constant" do
        capture_io do |stdout|
          check("INST HEALTH_STATUS CCSDSSHF == 'FALSE'")
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS CCSDSSHF == 'FALSE' success with value == 'FALSE'/)
        end
        expect { check("INST HEALTH_STATUS CCSDSSHF == FALSE") }.to raise_error(NameError, "Uninitialized constant FALSE. Did you mean 'FALSE' as a string?")
      end
    end

    describe "check_raw, check_formatted, check_with_units" do
      it "checks against the specified type" do
        capture_io do |stdout|
          check_raw("INST HEALTH_STATUS TEMP1 == 1")
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 == 1 success/)
          check_formatted("INST HEALTH_STATUS TEMP1 == '10.000'")
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 == '10.000' success/)
          check_with_units("INST HEALTH_STATUS TEMP1 == '10.000 C'")
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 == '10.000 C' success/)
        end
      end
    end

    describe "check_exception" do
      it "checks that the exception is raised in our apis" do
        capture_io do |stdout|
          check_exception("check", "INST HEALTH_STATUS TEMP1 == 9", type: :RAW, scope: "DEFAULT")
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 == 9 failed/)
          check_exception("check", "INST HEALTH_STATUS TEMP1 == 9", type: :RAW, scope: "OTHER")
          expect(stdout.string).to match(/Packet 'INST HEALTH_STATUS' does not exist/)
        end
      end

      it "raises if the exception is not raised" do
        expect { check_exception("tlm", "INST HEALTH_STATUS TEMP1") }.to raise_error(/tlm\(INST HEALTH_STATUS TEMP1\) should have raised an exception/)
      end

      # it "checks that the exception is raised in other methods" do
      #   def raise1 # no args
      #     raise "error"
      #   end
      #   def raise2(param) # regular args
      #     puts "p:#{param}"
      #     raise "error"
      #   end
      #   def raise3(param, named:) # args plus kwargs
      #     puts "p:#{param} named:#{named}"
      #     raise "error"
      #   end

      #   capture_io do |stdout|
      #     check_exception("raise1")
      #     expect(stdout.string).to match(/CHECK: raise1\(\) raised RuntimeError:error/)
      #     check_exception("raise2", 10)
      #     expect(stdout.string).to match(/CHECK: raise2\(10\) raised RuntimeError:error/)
      #     check_exception("raise3", 10, { named: 20 })
      #     expect(stdout.string).to match(/CHECK: raise3\(10, { named: 20 }\) raised RuntimeError:error/)
      #   end
      # end
    end

    describe "check_tolerance" do
      it "raises with :FORMATTED or :WITH_UNITS" do
        expect { check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type: :FORMATTED) }.to raise_error("Invalid type 'FORMATTED' for check_tolerance")
        expect { check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type: :WITH_UNITS) }.to raise_error("Invalid type 'WITH_UNITS' for check_tolerance")
      end

      it "checks that a value is within a tolerance" do
        capture_io do |stdout|
          check_tolerance("INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, type: :RAW)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65\d+ with value == 1.5/)
          check_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5/)
        end
        expect { check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1) }.to raise_error(CheckError, /CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5/)
      end

      it "checks that an array value is within a single tolerance" do
        capture_io do |stdout|
          check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1)
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4")
        end
        expect { check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2/)
        expect { check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[1\] was within range 2.9 to 3.1 with value == 3/)
        expect { check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[2\] failed to be within range 2.9 to 3.1 with value == 4/)
      end

      it "checks that multiple array values are within tolerance" do
        capture_io do |stdout|
          check_tolerance("INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1)
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4")
        end
      end

      it "checks that an array value is within multiple tolerances" do
        capture_io do |stdout|
          check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2])
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4")
        end
      end
    end

    describe "check_tolerance_raw" do
      it "checks that a value is within a tolerance" do
        capture_io do |stdout|
          check_tolerance_raw("INST HEALTH_STATUS TEMP2", 1.55, 0.1)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65\d+ with value == 1.5/)
        end
      end
    end

    describe "check_expression" do
      it "checks that an expression is true" do
        capture_io do |stdout|
          check_expression("true == true")
          expect(stdout.string).to match(/CHECK: true == true is TRUE/)
        end
        expect { check_expression("true == false") }.to raise_error(/CHECK: true == false is FALSE/)
      end

      it "checks a logical expression" do
        capture_io do |stdout|
          check_expression("'STRING' == 'STRING'")
          expect(stdout.string).to match(/CHECK: 'STRING' == 'STRING' is TRUE/)
        end
        expect { check_expression("1 == 2") }.to raise_error(/CHECK: 1 == 2 is FALSE/)
        expect { check_expression("'STRING' == STRING") }.to raise_error(NameError, "Uninitialized constant STRING. Did you mean 'STRING' as a string?")
      end
    end

    describe "wait" do
      it "waits for an indefinite time" do
        capture_io do |stdout|
          wait()
          expect(stdout.string).to match(/WAIT: Indefinite for actual time of .* seconds/)
        end
      end

      it "waits for a relative time" do
        capture_io do |stdout|
          wait(5)
          expect(stdout.string).to match(/WAIT: 5 seconds with actual time of .* seconds/)
        end
      end

      it "raises on a non-numeric time" do
        expect { wait('5') }.to raise_error("Non-numeric wait time specified")
      end

      it "waits for a TGT PKT ITEM" do
        capture_io do |stdout|
          wait("INST HEALTH_STATUS TEMP1 > 0", 5)
          expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS TEMP1 > 0 success with value == 10 after waiting .* seconds/)

          wait("INST HEALTH_STATUS TEMP1 < 0", 0.1, 0.1) # Last param is polling rate
          expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS TEMP1 < 0 failed with value == 10 after waiting .* seconds/)

          wait("INST", "HEALTH_STATUS", "TEMP1", "> 0", 5)
          expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS TEMP1 > 0 success with value == 10 after waiting .* seconds/)

          wait("INST", "HEALTH_STATUS", "TEMP1", "== 0", 0.1, 0.1) # Last param is polling rate
          expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS TEMP1 == 0 failed with value == 10 after waiting .* seconds/)
        end

        expect { wait("INST", "HEALTH_STATUS", "TEMP1", "== 0", 0.1, 0.1, 0.1) }.to raise_error(/Invalid number of arguments/)
      end
    end


    describe "wait_tolerance" do
      it "raises with :FORMATTED or :WITH_UNITS" do
        expect { wait_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type: :FORMATTED) }.to raise_error("Invalid type 'FORMATTED' for wait_tolerance")
        expect { wait_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, type: :WITH_UNITS) }.to raise_error("Invalid type 'WITH_UNITS' for wait_tolerance")
      end

      it "waits for a value to be within a tolerance" do
        capture_io do |stdout|
          wait_tolerance("INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, 5, type: :RAW)
          expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65\d+ with value == 1.5/)
          wait_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01, 5)
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5")
          wait_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1)
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5")
        end
      end

      it "checks that an array value is within a single tolerance" do
        capture_io do |stdout|
          wait_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1, 5)
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2")
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3")
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4")
          wait_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1)
          expect(stdout.string).to include("INST HEALTH_STATUS ARY[0] failed to be within range 2.9 to 3.1 with value == 2")
          expect(stdout.string).to include("INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3")
          expect(stdout.string).to include("INST HEALTH_STATUS ARY[2] failed to be within range 2.9 to 3.1 with value == 4")
        end
      end

      it "checks that multiple array values are within tolerance" do
        capture_io do |stdout|
          wait_tolerance("INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1, 5)
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2")
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3")
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4")
        end
      end

      it "checks that an array value is within multiple tolerances" do
        capture_io do |stdout|
          wait_tolerance("INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2], 5)
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2")
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3")
          expect(stdout.string).to include("WAIT: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4")
        end
      end
    end

    describe "wait_expression" do
      it "waits for an expression" do
        capture_io do |stdout|
          wait_expression("true == true", 5)
          expect(stdout.string).to match(/WAIT: true == true is TRUE after waiting .* seconds/)
          wait_expression("true == false", 0.1)
          expect(stdout.string).to match(/WAIT: true == false is FALSE after waiting .* seconds/)
        end
      end

      it "checks a logical expression" do
        capture_io do |stdout|
          wait_expression("'STRING' == 'STRING'", 5)
          expect(stdout.string).to match(/WAIT: 'STRING' == 'STRING' is TRUE after waiting .* seconds/)
          wait_expression("1 == 2", 0.1)
          expect(stdout.string).to match(/WAIT: 1 == 2 is FALSE after waiting .* seconds/)
        end
        expect { wait_expression("'STRING' == STRING", 5) }.to raise_error(NameError, "Uninitialized constant STRING. Did you mean 'STRING' as a string?")
      end
    end

    describe "wait_check" do
      it "checks a telemetry item against a value" do
        capture_io do |stdout|
          wait_check("INST", "HEALTH_STATUS", "TEMP1", "> 1", 0.01)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 > 1 success with value == 10/)
          wait_check("INST HEALTH_STATUS TEMP1 == 1", 0.01, type: :RAW)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP1 == 1 success with value == 1/)
        end
        expect { wait_check("INST HEALTH_STATUS TEMP1 > 100", 0.01) }.to raise_error(/CHECK: INST HEALTH_STATUS TEMP1 > 100 failed with value == 10/)
      end

      it "warns when checking a state against a constant" do
        capture_io do |stdout|
          wait_check("INST HEALTH_STATUS CCSDSSHF == 'FALSE'", 0.01)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS CCSDSSHF == 'FALSE' success with value == 'FALSE'/)
        end
        expect { wait_check("INST HEALTH_STATUS CCSDSSHF == FALSE", 0.01) }.to raise_error(NameError, "Uninitialized constant FALSE. Did you mean 'FALSE' as a string?")
      end
    end

    describe "wait_check_tolerance" do
      it "raises with :FORMATTED or :WITH_UNITS" do
        expect { wait_check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, 5, type: :FORMATTED) }.to raise_error("Invalid type 'FORMATTED' for wait_check_tolerance")
        expect { wait_check_tolerance("INST HEALTH_STATUS TEMP2 == 10.5", 0.1, 5, type: :WITH_UNITS) }.to raise_error("Invalid type 'WITH_UNITS' for wait_check_tolerance")
      end

      it "checks that a value is within a tolerance" do
        capture_io do |stdout|
          wait_check_tolerance("INST", "HEALTH_STATUS", "TEMP2", 1.55, 0.1, 5, type: :RAW)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP2 was within range 1.45 to 1.65\d+ with value == 1.5/)
          wait_check_tolerance("INST HEALTH_STATUS TEMP2", 10.5, 0.01, 5)
          expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS TEMP2 was within range 10.49 to 10.51 with value == 10.5/)
        end
        expect { wait_check_tolerance("INST HEALTH_STATUS TEMP2", 11, 0.1, 0.1) }.to raise_error(CheckError, /CHECK: INST HEALTH_STATUS TEMP2 failed to be within range 10.9 to 11.1 with value == 10.5/)
      end

      it "checks that an array value is within a single tolerance" do
        capture_io do |stdout|
          wait_check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, 1, 5)
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[1] was within range 2 to 4 with value == 3")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[2] was within range 2 to 4 with value == 4")
        end
        expect { wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[0\] failed to be within range 2.9 to 3.1 with value == 2/)
        expect { wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[1\] was within range 2.9 to 3.1 with value == 3/)
        expect { wait_check_tolerance("INST HEALTH_STATUS ARY", 3, 0.1, 0.1) }.to raise_error(/INST HEALTH_STATUS ARY\[2\] failed to be within range 2.9 to 3.1 with value == 4/)
      end

      it "checks that multiple array values are within tolerance" do
        capture_io do |stdout|
          wait_check_tolerance("INST", "HEALTH_STATUS", "ARY", [2, 3, 4], 0.1, 5)
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[0] was within range 1.9 to 2.1 with value == 2")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[2] was within range 3.9 to 4.1 with value == 4")
        end
      end

      it "checks that an array value is within multiple tolerances" do
        capture_io do |stdout|
          wait_check_tolerance("INST", "HEALTH_STATUS", "ARY", 3, [1, 0.1, 2], 5)
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[0] was within range 2 to 4 with value == 2")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[1] was within range 2.9 to 3.1 with value == 3")
          expect(stdout.string).to include("CHECK: INST HEALTH_STATUS ARY[2] was within range 1 to 5 with value == 4")
        end
      end
    end

    describe "wait_check_expression" do
      it "waits and checks that an expression is true" do
        capture_io do |stdout|
          wait_check_expression("true == true", 5)
          expect(stdout.string).to match(/CHECK: true == true is TRUE/)
        end
        expect { wait_check_expression("true == false", 0.1) }.to raise_error(/CHECK: true == false is FALSE/)
      end

      it "waits and checks a logical expression" do
        capture_io do |stdout|
          wait_check_expression("'STRING' == 'STRING'", 5)
          expect(stdout.string).to match(/CHECK: 'STRING' == 'STRING' is TRUE/)
        end
        expect { wait_check_expression("1 == 2", 0.1) }.to raise_error(/CHECK: 1 == 2 is FALSE/)
        expect { wait_check_expression("'STRING' == STRING", 0.1) }.to raise_error(NameError, "Uninitialized constant STRING. Did you mean 'STRING' as a string?")
      end
    end

    [true, false].each do |cancel|
      context "with wait cancelled #{cancel}" do

        describe "wait_packet" do
          before(:each) do
            @sleep_cancel = cancel
          end

          it "prints warning if packet not received" do
            @count = false
            capture_io do |stdout|
              wait_packet("INST", "HEALTH_STATUS", 1, 0.5)
              expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS expected to be received 1 times but only received 0 times/)
            end
          end

          it "prints success if the packet is received" do
            @count = true
            capture_io do |stdout|
              wait_packet("INST", "HEALTH_STATUS", 5, 0.5)
              if cancel
                expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS expected to be received 5 times/)
              else
                expect(stdout.string).to match(/WAIT: INST HEALTH_STATUS received 5 times after waiting/)
              end
            end
          end
        end

        describe "wait_check_packet" do
          before(:each) do
            @sleep_cancel = cancel
          end

          it "raises a check error if packet not received" do
            @count = false
            expect { wait_check_packet("INST", "HEALTH_STATUS", 1, 0.5) }.to raise_error(/CHECK: INST HEALTH_STATUS expected to be received 1 times but only received 0 times/)
          end

          it "prints success if the packet is received" do
            @count = true
            capture_io do |stdout|
              if cancel
                expect { wait_check_packet("INST", "HEALTH_STATUS", 5, 0.5) }.to raise_error(/CHECK: INST HEALTH_STATUS expected to be received 5 times/)
              else
                wait_check_packet("INST", "HEALTH_STATUS", 5, 0.5)
                expect(stdout.string).to match(/CHECK: INST HEALTH_STATUS received 5 times after waiting/)
              end
            end
          end
        end
      end
    end
  end
end
