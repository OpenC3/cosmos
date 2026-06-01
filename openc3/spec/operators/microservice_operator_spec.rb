# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
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

    describe "convert_microservice_to_process_definition" do
      before(:each) do
        mock_redis()
        @operator = MicroserviceOperator.new
      end

      it "sets per-plugin venv env vars when plugin venv directory exists" do
        config = {
          "env" => {},
          "needs_dependencies" => true,
          "plugin" => "my-plugin__0"
        }
        sanitized_name = "my-plugin__0"
        venv_dir = "/gems/plugin_venvs/#{sanitized_name}/.venv"
        allow(File).to receive(:directory?).with(venv_dir).and_return(true)

        _cmd, _work_dir, env, _scope, _container = @operator.convert_microservice_to_process_definition("DEFAULT__TYPE__NAME", config)

        expect(env['VIRTUAL_ENV']).to eq(venv_dir)
        expect(env['PATH']).to start_with("#{venv_dir}/bin:")
        expect(env['PYTHONUSERBASE']).to eq(venv_dir)
        expect(env['GEM_HOME']).to eq('/gems')
      end

      it "falls back to shared python_packages when no plugin venv exists" do
        config = {
          "env" => {},
          "needs_dependencies" => true,
          "plugin" => "my-plugin__0"
        }
        venv_dir = "/gems/plugin_venvs/my-plugin__0/.venv"
        allow(File).to receive(:directory?).with(venv_dir).and_return(false)

        _cmd, _work_dir, env, _scope, _container = @operator.convert_microservice_to_process_definition("DEFAULT__TYPE__NAME", config)

        expect(env['VIRTUAL_ENV']).to be_nil
        expect(env['PYTHONUSERBASE']).to eq('/gems/python_packages')
        expect(env['GEM_HOME']).to eq('/gems')
      end

      it "sets GEM_HOME, PYTHONUSERBASE, and PYTHONPATH to nil when needs_dependencies is false" do
        config = {
          "env" => {},
          "needs_dependencies" => false,
          "plugin" => "my-plugin__0"
        }

        _cmd, _work_dir, env, _scope, _container = @operator.convert_microservice_to_process_definition("DEFAULT__TYPE__NAME", config)

        expect(env['GEM_HOME']).to be_nil
        expect(env['PYTHONUSERBASE']).to be_nil
        expect(env['PYTHONPATH']).to be_nil
      end

      it "sanitizes plugin name for venv directory lookup" do
        config = {
          "env" => {},
          "needs_dependencies" => true,
          "plugin" => "my.plugin@1.0"
        }
        # tr('^a-zA-Z0-9_-', '_') converts dots and @ to underscores
        sanitized_name = "my_plugin_1_0"
        venv_dir = "/gems/plugin_venvs/#{sanitized_name}/.venv"
        allow(File).to receive(:directory?).with(venv_dir).and_return(true)

        _cmd, _work_dir, env, _scope, _container = @operator.convert_microservice_to_process_definition("DEFAULT__TYPE__NAME", config)

        expect(env['VIRTUAL_ENV']).to eq(venv_dir)
        expect(env['PYTHONUSERBASE']).to eq(venv_dir)
      end

      it "falls back to shared when plugin name is nil" do
        config = {
          "env" => {},
          "needs_dependencies" => true,
          "plugin" => nil
        }

        _cmd, _work_dir, env, _scope, _container = @operator.convert_microservice_to_process_definition("DEFAULT__TYPE__NAME", config)

        expect(env['VIRTUAL_ENV']).to be_nil
        expect(env['PYTHONUSERBASE']).to eq('/gems/python_packages')
      end

      it "preserves PYTHONPATH from parent environment" do
        config = {
          "env" => {},
          "needs_dependencies" => true,
          "plugin" => "test-plugin"
        }
        allow(File).to receive(:directory?).and_return(false)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('PYTHONPATH').and_return('/some/python/path')

        _cmd, _work_dir, env, _scope, _container = @operator.convert_microservice_to_process_definition("DEFAULT__TYPE__NAME", config)

        expect(env['PYTHONPATH']).to eq('/some/python/path')
      end
    end

    describe "start_new" do
      before(:each) do
        @saved_max = ENV.fetch('OPENC3_OPERATOR_MAX_START_PER_CYCLE', nil)
      end

      after(:each) do
        if @saved_max.nil?
          ENV.delete('OPENC3_OPERATOR_MAX_START_PER_CYCLE')
        else
          ENV['OPENC3_OPERATOR_MAX_START_PER_CYCLE'] = @saved_max
        end
      end

      def build_processes(started)
        processes = {}
        5.times do |i|
          name = "DEFAULT__TYPE__NAME#{i}"
          process = double(name)
          allow(process).to receive(:start) { started << name }
          processes[name] = process
        end
        processes
      end

      it "starts at most OPENC3_OPERATOR_MAX_START_PER_CYCLE processes per cycle" do
        ENV['OPENC3_OPERATOR_MAX_START_PER_CYCLE'] = '2'
        op = MicroserviceOperator.new
        started = []
        op.instance_variable_set(:@new_processes, build_processes(started))

        # First cycle starts only the first 2; the rest stay queued for later cycles
        capture_io { op.start_new }
        expect(started).to eq(%w(DEFAULT__TYPE__NAME0 DEFAULT__TYPE__NAME1))
        expect(op.instance_variable_get(:@new_processes).keys).to eq(%w(DEFAULT__TYPE__NAME2 DEFAULT__TYPE__NAME3 DEFAULT__TYPE__NAME4))

        # Subsequent cycles drain the queue 2 at a time until empty
        capture_io { op.start_new }
        expect(started).to eq(%w(DEFAULT__TYPE__NAME0 DEFAULT__TYPE__NAME1 DEFAULT__TYPE__NAME2 DEFAULT__TYPE__NAME3))
        capture_io { op.start_new }
        expect(started.length).to eq(5)
        expect(op.instance_variable_get(:@new_processes)).to be_empty
      end

      it "starts every process in one cycle when the limit is 0 (unlimited)" do
        ENV['OPENC3_OPERATOR_MAX_START_PER_CYCLE'] = '0'
        op = MicroserviceOperator.new
        started = []
        op.instance_variable_set(:@new_processes, build_processes(started))

        capture_io { op.start_new }
        expect(started.length).to eq(5)
        expect(op.instance_variable_get(:@new_processes)).to be_empty
      end
    end

    describe "respawn_dead" do
      it "skips processes still queued by the per-cycle start limit" do
        op = MicroserviceOperator.new
        queued = double("queued_process")
        # A queued (not yet started) process must not be treated as dead and respawned
        expect(queued).to_not receive(:alive?)
        expect(queued).to_not receive(:start)
        op.instance_variable_set(:@processes, { "DEFAULT__TYPE__QUEUED" => queued })
        op.instance_variable_set(:@new_processes, { "DEFAULT__TYPE__QUEUED" => queued })
        capture_io { op.respawn_dead }
      end
    end

    describe "respawn_changed" do
      before(:each) do
        @saved_max = ENV.fetch('OPENC3_OPERATOR_MAX_START_PER_CYCLE', nil)
      end

      after(:each) do
        if @saved_max.nil?
          ENV.delete('OPENC3_OPERATOR_MAX_START_PER_CYCLE')
        else
          ENV['OPENC3_OPERATOR_MAX_START_PER_CYCLE'] = @saved_max
        end
      end

      def build_changed(started)
        processes = {}
        5.times do |i|
          name = "DEFAULT__TYPE__NAME#{i}"
          # as_null_object so the shutdown_processes calls (soft_stop, hard_stop,
          # output_increment, extract_output) are harmless no-ops
          process = double(name).as_null_object
          allow(process).to receive(:alive?).and_return(false)
          allow(process).to receive(:start) { started << name }
          processes[name] = process
        end
        processes
      end

      it "cycles at most OPENC3_OPERATOR_MAX_START_PER_CYCLE changed processes per cycle" do
        ENV['OPENC3_OPERATOR_MAX_START_PER_CYCLE'] = '2'
        op = MicroserviceOperator.new
        started = []
        op.instance_variable_set(:@changed_processes, build_changed(started))

        # First cycle restarts only the first 2; the rest keep running, queued for later
        capture_io { op.respawn_changed }
        expect(started).to eq(%w(DEFAULT__TYPE__NAME0 DEFAULT__TYPE__NAME1))
        expect(op.instance_variable_get(:@changed_processes).keys).to eq(%w(DEFAULT__TYPE__NAME2 DEFAULT__TYPE__NAME3 DEFAULT__TYPE__NAME4))

        # Subsequent cycles drain the queue 2 at a time until empty
        capture_io { op.respawn_changed }
        expect(started.length).to eq(4)
        capture_io { op.respawn_changed }
        expect(started.length).to eq(5)
        expect(op.instance_variable_get(:@changed_processes)).to be_empty
      end

      it "cycles all changed processes in one cycle when the limit is 0 (unlimited)" do
        ENV['OPENC3_OPERATOR_MAX_START_PER_CYCLE'] = '0'
        op = MicroserviceOperator.new
        started = []
        op.instance_variable_set(:@changed_processes, build_changed(started))

        capture_io { op.respawn_changed }
        expect(started.length).to eq(5)
        expect(op.instance_variable_get(:@changed_processes)).to be_empty
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
      # xit "should query redis for new microservices and create processes" do
      #   capture_io do |stdout|
      #     expect(MicroserviceOperator.processes).to be_empty()
      #     config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [] }
      #     @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__START_INT', JSON.generate(config, allow_nan: true))
      #     sleep 1
      #     expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__START_INT')
      #     expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__START_INT']).to be_a OperatorProcess
      #     expect(stdout.string).to match(/Starting.*ruby.*while.rb/)
      #   end
      # end

      # DISABLED due to LanuchError due to linux vs windows
      #    ChildProcess::LaunchError:
      #    The directory name is invalid. (267)
      # xit "should restart changed microservices" do
      #   capture_io do |stdout|
      #     config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [] }
      #     @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__RESTART_INT', JSON.generate(config, allow_nan: true))
      #     sleep 1
      #     expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__RESTART_INT')
      #     expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__RESTART_INT']).to be_a OperatorProcess

      #     # Slightly change the configuration by adding something
      #     config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [], 'target_list' => 'TEST' }
      #     @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__RESTART_INT', JSON.generate(config, allow_nan: true))
      #     sleep 3 # Due to 2s wait in shutdown
      #     expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__RESTART_INT')
      #     expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__RESTART_INT']).to be_a OperatorProcess
      #     # We should see starting more than once
      #     expect(stdout.string.scan(/Starting.*ruby.*while.rb/).size).to be > 1
      #     # We should see Soft and Hard stopping
      #     expect(stdout.string.scan(/Soft shutting down.*ruby.*while.rb/).size).to eq 1
      #     expect(stdout.string.scan(/Hard shutting down.*ruby.*while.rb/).size).to eq 1
      #   end
      # end

      # DISABLED due to LanuchError due to linux vs windows
      #    ChildProcess::LaunchError:
      #    The directory name is invalid. (267)
      # xit "should remove deleted microservices" do
      #   capture_io do |stdout|
      #     config = { 'filename' => './while.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby while.rb), 'work_dir' => SPEC_DIR, 'env' => [] }
      #     @redis.hset('openc3_microservices', 'DEFAULT__INTERFACE__DELETE_INT', JSON.generate(config, allow_nan: true))
      #     sleep 1
      #     expect(MicroserviceOperator.processes.keys).to include('DEFAULT__INTERFACE__DELETE_INT')
      #     expect(MicroserviceOperator.processes['DEFAULT__INTERFACE__DELETE_INT']).to be_a OperatorProcess

      #     @redis.hdel('openc3_microservices', 'DEFAULT__INTERFACE__DELETE_INT')
      #     sleep 1
      #     expect(MicroserviceOperator.processes).to be_empty()
      #     expect(stdout.string).to match(/shutting down.*ruby.*while.rb/)
      #   end
      # end
    end
  end
end
