equire 'spec_helper'
require 'openc3/operators/microservice_operator'
require 'openc3/utilities/aws_bucket'
=begin
This test suite covers the main functionality of the MicroserviceOperator class:

1. Initialization and cycle time setting
2. Running the operator
3. Creating new microservice processes
4. Restarting changed microservices
5. Removing deleted microservices
6. Stopping all processes

The tests use a mock Redis instance and override process killing to ensure safe testing. The `run` method is tested by starting it in a separate thread and then stopping it after each test.

Note that some of the original tests were disabled due to platform-specific issues. This test suite aims to provide platform-independent tests that should run on both Windows and Linux systems. However, you may need to adjust the file paths and commands if you want to test with actual file operations.
=end

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
      @redis = mock_redis()
      allow(Process).to receive(:kill) do |type, pid|
        # Override SIGINT to just kill the process
        Process.kill("KILL", pid) if type == "SIGINT"
      end
    end

    describe "initialize" do
      it "should call OperatorProcess.setup" do
        expect(OperatorProcess).to receive(:setup)
        MicroserviceOperator.new
      end

      it "should set cycle_time from ENV['OPERATOR_CYCLE_TIME']" do
        ENV['OPERATOR_CYCLE_TIME'] = '60'
        op = MicroserviceOperator.new
        expect(op.cycle_time).to eq 60.0
      end

      it "should use default cycle_time if ENV['OPERATOR_CYCLE_TIME'] is not set" do
        ENV.delete('OPERATOR_CYCLE_TIME')
        op = MicroserviceOperator.new
        expect(op.cycle_time).to eq 10.0 # Assuming 10.0 is the default
      end
    end

    describe "run" do
      it "should start the operator thread" do
        ENV['OPERATOR_CYCLE_TIME'] = '0.1'
        thread = nil
        expect {
          thread = Thread.new { MicroserviceOperator.run }
          sleep 0.2 # Allow the operator to spin up
        }.to change { MicroserviceOperator.instance }.from(nil)
        MicroserviceOperator.instance.stop
        thread.join
      end
    end

    describe "update" do
      before(:each) do
        ENV['OPERATOR_CYCLE_TIME'] = '0.1'
        @thread = Thread.new { MicroserviceOperator.run }
        sleep 0.2 # Allow the operator to spin up
      end

      after(:each) do
        MicroserviceOperator.instance.stop
        @thread.join
      end

      it "should create new microservice processes" do
        config = { 'filename' => 'test.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby test.rb), 'work_dir' => '.', 'env' => [] }
        @redis.hset('openc3_microservices', 'DEFAULT__TEST', JSON.generate(config))
        sleep 0.3
        expect(MicroserviceOperator.processes.keys).to include('DEFAULT__TEST')
      end

      it "should restart changed microservices" do
        config = { 'filename' => 'test.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby test.rb), 'work_dir' => '.', 'env' => [] }
        @redis.hset('openc3_microservices', 'DEFAULT__TEST', JSON.generate(config))
        sleep 0.3
        
        new_config = config.merge('env' => ['NEW_ENV=1'])
        @redis.hset('openc3_microservices', 'DEFAULT__TEST', JSON.generate(new_config))
        sleep 0.3

        expect(MicroserviceOperator.processes['DEFAULT__TEST'].config).to eq(new_config)
      end

      it "should remove deleted microservices" do
        config = { 'filename' => 'test.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby test.rb), 'work_dir' => '.', 'env' => [] }
        @redis.hset('openc3_microservices', 'DEFAULT__TEST', JSON.generate(config))
        sleep 0.3
        
        @redis.hdel('openc3_microservices', 'DEFAULT__TEST')
        sleep 0.3

        expect(MicroserviceOperator.processes).not_to have_key('DEFAULT__TEST')
      end
    end

    describe "stop" do
      it "should stop all processes and clear the processes hash" do
        ENV['OPERATOR_CYCLE_TIME'] = '0.1'
        thread = Thread.new { MicroserviceOperator.run }
        sleep 0.2

        config = { 'filename' => 'test.rb', 'scope' => 'DEFAULT', 'cmd' => %w(ruby test.rb), 'work_dir' => '.', 'env' => [] }
        @redis.hset('openc3_microservices', 'DEFAULT__TEST', JSON.generate(config))
        sleep 0.3

        expect(MicroserviceOperator.processes).not_to be_empty
        MicroserviceOperator.instance.stop
        sleep 0.3
        expect(MicroserviceOperator.processes).to be_empty

        thread.join
      end
    end
  end
end
