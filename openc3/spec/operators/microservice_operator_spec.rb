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
require 'openc3/operators/microservice_operator'
require 'openc3/utilities/aws_bucket'

# Override at_exit to do nothing for testing
saved_verbose = $VERBOSE; $VERBOSE = nil
def at_exit(*args, &block)
end
$VERBOSE = saved_verbose

module OpenC3
  describe MicroserviceOperator do
    before(:each) do
      dbl = double("AwsS3Client").as_null_object
      allow(Aws::S3::Client).to receive(:new).and_return(dbl)
    end

    describe "initialize" do
      it "should call OperatorProcess.setup" do
        expect(OperatorProcess).to receive(:setup)
        MicroserviceOperator.new
      end

      it "should cycle every ENV['OPERATOR_CYCLE_TIME'] seconds" do
        ENV['OPERATOR_CYCLE_TIME'] = '60'
        op = MicroserviceOperator.new
        expect(op.cycle_time).to eq 60.0
      end
    end

    describe "update" do
      # SPEC_DIR: C:/.../openc3/openc3/spec
      before(:all) do
        File.open(File.join(SPEC_DIR, 'while.rb'), 'w') do |file|
          file.puts "while true\n  sleep 1\nend"
        end
      end

      after(:all) do
        # SPEC_DIR: C:/.../openc3/openc3/spec
        FileUtils.rm_f File.join(SPEC_DIR, 'while.rb')
      end

      before(:each) do
        @redis = mock_redis()
        allow(Process).to receive(:kill) do |type, pid|
          # Override SIGINT to just kill the process
          Process.kill("KILL", pid) if type == "SIGINT"
        end
        ENV['OPERATOR_CYCLE_TIME'] = '0.1'
        # Capture and ignore the output from the Operator starting
        capture_io do |stdout|
          @thread = Thread.new { MicroserviceOperator.run }
          sleep 0.1 # Allow the operator to spin up
        end
      end

      after(:each) do
        MicroserviceOperator.instance.stop
        @thread.join
      end

      # DISABLED due to LanuchError due to linux vs windows
      #    ChildProcess::LaunchError:
      #    The directory name is invalid. (267)
      xit "should query redis for new microservices and create processes" do
        capture_io do |stdout|
          expect(MicroserviceOperator.processes).to be_empty()
          config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [] }
          @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__START_INT', JSON.generate(config, allow_nan: true))
          sleep 1
          expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__START_INT')
          expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__START_INT']).to be_a OperatorProcess
          expect(stdout.string).to match(/Starting.*ruby.*while.rb/)
        end
      end

      # DISABLED due to LanuchError due to linux vs windows
      #    ChildProcess::LaunchError:
      #    The directory name is invalid. (267)
      xit "should restart changed microservices" do
        capture_io do |stdout|
          config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [] }
          @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__RESTART_INT', JSON.generate(config, allow_nan: true))
          sleep 1
          expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__RESTART_INT')
          expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__RESTART_INT']).to be_a OperatorProcess

          # Slightly change the configuration by adding something
          config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [], 'target_list' => 'TEST' }
          @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__RESTART_INT', JSON.generate(config, allow_nan: true))
          sleep 3 # Due to 2s wait in shutdown
          expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__RESTART_INT')
          expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__RESTART_INT']).to be_a OperatorProcess
          # We should see starting more than once
          expect(stdout.string.scan(/Starting.*ruby.*while.rb/).size).to be > 1
          # We should see Soft and Hard stopping
          expect(stdout.string.scan(/Soft shutting down.*ruby.*while.rb/).size).to eq 1
          expect(stdout.string.scan(/Hard shutting down.*ruby.*while.rb/).size).to eq 1
        end
      end

      # DISABLED due to LanuchError due to linux vs windows
      #    ChildProcess::LaunchError:
      #    The directory name is invalid. (267)
      xit "should remove deleted microservices" do
        capture_io do |stdout|
          config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [] }
          @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__DELETE_INT', JSON.generate(config, allow_nan: true))
          sleep 1
          expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__DELETE_INT')
          expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__DELETE_INT']).to be_a OperatorProcess

          @redis.hdel('openc3_microservices', 'DEFAULT__INTERFACE__DELETE_INT')
          sleep 1
          expect(MicroserviceOperator.processes).to be_empty()
          expect(stdout.string).to match(/shutting down.*ruby.*while.rb/)
        end
      end
    end
  end
end
