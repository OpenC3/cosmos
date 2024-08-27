require 'rspec'
require_relative 'path/to/your/operator_process_file'

RSpec.describe OpenC3::OperatorProcess do
  let(:process_definition) { ['ruby', 'test_script.rb'] }
  let(:work_dir) { '/tmp' }
  let(:scope) { 'test_scope' }
  let(:operator_process) { OpenC3::OperatorProcess.new(process_definition, work_dir: work_dir, scope: scope) }

  before do
    allow(ChildProcess).to receive(:build).and_return(double('process', 
      start: nil, 
      alive?: true, 
      exit_code: nil, 
      stop: nil, 
      pid: 12345,
      environment: {},
      io: double('io', stdout: double('stdout', extract: ''), stderr: double('stderr', extract: ''))
    ))
    allow(Logger).to receive(:info)
    allow(Process).to receive(:kill)
  end

  describe '#alive?' do
    it 'returns true if process is alive' do
      operator_process.start
      expect(operator_process.alive?).to be true
    end

    it 'returns false if process is not started' do
      expect(operator_process.alive?).to be false
    end
  end

  describe '#exit_code' do
    it 'returns nil if process is not started' do
      expect(operator_process.exit_code).to be_nil
    end

    it 'returns exit code if process is started' do
      operator_process.start
      allow(operator_process.instance_variable_get(:@process)).to receive(:exit_code).and_return(0)
      expect(operator_process.exit_code).to eq(0)
    end
  end

  describe '#soft_stop' do
    it 'sends SIGINT to the process' do
      operator_process.start
      expect(Process).to receive(:kill).with('SIGINT', 12345)
      operator_process.soft_stop
    end
  end

  describe '#hard_stop' do
    it 'stops the process' do
      operator_process.start
      expect(operator_process.instance_variable_get(:@process)).to receive(:stop)
      operator_process.hard_stop
    end
  end

  describe '#stdout' do
    it 'returns stdout of the process' do
      operator_process.start
      expect(operator_process.stdout).to be_a(OpenC3::OperatorProcessIO)
    end
  end

  describe '#stderr' do
    it 'returns stderr of the process' do
      operator_process.start
      expect(operator_process.stderr).to be_a(OpenC3::OperatorProcessIO)
    end
  end

  describe '#output_increment' do
    it 'extracts and prints stdout and stderr' do
      operator_process.start
      expect(STDOUT).to receive(:puts).twice
      expect(STDERR).to receive(:puts).twice
      operator_process.output_increment
    end
  end

  describe '#extract_output' do
    it 'returns formatted output from stdout and stderr' do
      operator_process.start
      expect(operator_process.extract_output).to include('Stdout:', 'Stderr:')
    end
  end

  describe '#start' do
    it 'starts the process' do
      expect(ChildProcess).to receive(:build).with(*process_definition)
      operator_process.start
    end
  end
end

RSpec.describe OpenC3::Operator do
  let(:operator) { OpenC3::Operator.new }

  describe '#start_new' do
    it 'starts new processes' do
      new_process = double('new_process')
      expect(new_process).to receive(:start)
      operator.instance_variable_set(:@new_processes, {'test' => new_process})
      operator.start_new
    end
  end

  describe '#respawn_changed' do
    it 'restarts changed processes' do
      changed_process = double('changed_process')
      expect(changed_process).to receive(:start)
      operator.instance_variable_set(:@changed_processes, {'test' => changed_process})
      allow(operator).to receive(:shutdown_processes)
      operator.respawn_changed
    end
  end

  describe '#remove_old' do
    it 'shuts down removed processes' do
      removed_process = double('removed_process')
      operator.instance_variable_set(:@removed_processes, {'test' => removed_process})
      expect(operator).to receive(:shutdown_processes)
      operator.remove_old
    end
  end

  describe '#respawn_dead' do
    it 'respawns dead processes' do
      dead_process = double('dead_process', alive?: false, cmd_line: 'test', scope: 'test')
      expect(dead_process).to receive(:output_increment)
      expect(dead_process).to receive(:extract_output).and_return('')
      expect(dead_process).to receive(:start)
      operator.instance_variable_set(:@processes, {'test' => dead_process})
      operator.respawn_dead
    end
  end

  describe '#shutdown_processes' do
    it 'shuts down processes' do
      process = double('process', alive?: true, cmd_line: 'test', scope: 'test')
      expect(process).to receive(:soft_stop)
      expect(process).to receive(:hard_stop)
      operator.shutdown_processes({'test' => process})
    end
  end

  describe '#shutdown' do
    it 'shuts down all processes' do
      expect(operator).to receive(:shutdown_processes)
      operator.shutdown
    end
  end

  describe '#run' do
    it 'runs the operator cycle' do
      allow(operator).to receive(:update)
      allow(operator).to receive(:remove_old)
      allow(operator).to receive(:respawn_changed)
      allow(operator).to receive(:start_new)
      allow(operator).to receive(:respawn_dead)
      allow(operator).to receive(:sleep)
      expect(operator).to receive(:shutdown)
      operator.run
    end
  end

  describe '#stop' do
    it 'sets the shutdown flag' do
      operator.stop
      expect(operator.instance_variable_get(:@shutdown)).to be true
    end
  end

  describe '.run' do
    it 'creates an instance and runs it' do
      instance = double('operator_instance')
      expect(described_class).to receive(:new).and_return(instance)
      expect(instance).to receive(:run)
      described_class.run
    end
  end

  describe '.processes' do
    it 'returns processes from the instance' do
      instance = double('operator_instance', processes: {})
      described_class.class_variable_set(:@@instance, instance)
      expect(described_class.processes).to eq({})
    end
  end

  describe '.instance' do
    it 'returns the singleton instance' do
      instance = double('operator_instance')
      described_class.class_variable_set(:@@instance, instance)
      expect(described_class.instance).to eq(instance)
    end
  end
end
```

This RSpec test suite covers all the specified methods of the OperatorProcess class and the Operator class. It includes tests for various scenarios and edge cases. Note that some methods might require additional setup or mocking depending on their implementation details. You may need to adjust the file path in the `require_relative` statement at the beginning of the file to match your project structure.

