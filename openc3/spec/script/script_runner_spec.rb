require 'rspec'
require 'json'

=begin
This RSpec test suite covers all the methods in the ScriptRunner class, including various success and failure scenarios. It uses a mock API server to simulate responses and tests different edge cases. The tests cover:

1. Successful API calls
2. Error handling for failed API calls
3. Different parameter combinations
4. Edge cases like empty environments or invalid inputs

To run these tests, make sure you have RSpec installed (`gem install rspec`) and save this file with a `.rb` extension (e.g., `script_runner_spec.rb`). Then run the tests using the `rspec` command in the terminal.
=end

# Mock the $script_runner_api_server
class MockApiServer
  def request(method, endpoint, options = {})
    OpenStruct.new(
      status: 200,
      body: '{"success": true}'
    )
  end
end

# Include the module to test
module OpenC3
  module Script
    include OpenC3::Script
  end
end

RSpec.describe OpenC3::Script do
  let(:script_runner) { Class.new { extend OpenC3::Script } }

  before do
    $script_runner_api_server = MockApiServer.new
    $openc3_scope = 'DEFAULT'
  end

  describe '#script_list' do
    it 'returns a list of scripts' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '[{"name": "test_script.rb"}]'))
      expect(script_runner.script_list).to eq([{"name" => "test_script.rb"}])
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.script_list }.to raise_error(RuntimeError, /Script list request failed/)
    end
  end

  describe '#script_syntax_check' do
    it 'returns true when syntax check is successful' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '{"title": "Syntax Check Successful"}'))
      expect(script_runner.script_syntax_check('puts "Hello"')).to be true
    end

    it 'raises an error when syntax check fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '{"title": "Syntax Error", "description": "Invalid syntax"}'))
      expect { script_runner.script_syntax_check('puts "Hello') }.to raise_error(RuntimeError, /{"title"=>"Syntax Error"/)
    end
  end

  describe '#script_body' do
    it 'returns the script body' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: 'puts "Hello"'))
      expect(script_runner.script_body('test_script.rb')).to eq('puts "Hello"')
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 404, body: 'Not Found'))
      expect { script_runner.script_body('nonexistent.rb') }.to raise_error(RuntimeError, /Failed to get nonexistent.rb/)
    end
  end

  describe '#script_run' do
    it 'returns a script ID when run successfully' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '42'))
      expect(script_runner.script_run('test_script.rb')).to eq(42)
    end

    it 'handles environment variables' do
      allow($script_runner_api_server).to receive(:request) do |method, endpoint, options|
        expect(options[:data][:environment]).to eq([{"key" => "VAR1", "value" => "value1"}])
        OpenStruct.new(status: 200, body: '42')
      end
      script_runner.script_run('test_script.rb', environment: {"VAR1" => "value1"})
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.script_run('test_script.rb') }.to raise_error(RuntimeError, /Failed to run test_script.rb/)
    end
  end

  describe '#script_delete' do
    it 'returns true when script is deleted successfully' do
      expect(script_runner.script_delete('test_script.rb')).to be true
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 404, body: 'Not Found'))
      expect { script_runner.script_delete('nonexistent.rb') }.to raise_error(RuntimeError, /Failed to delete nonexistent.rb/)
    end
  end

  describe '#script_lock' do
    it 'returns true when script is locked successfully' do
      expect(script_runner.script_lock('test_script.rb')).to be true
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.script_lock('test_script.rb') }.to raise_error(RuntimeError, /Failed to lock test_script.rb/)
    end
  end

  describe '#script_unlock' do
    it 'returns true when script is unlocked successfully' do
      expect(script_runner.script_unlock('test_script.rb')).to be true
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.script_unlock('test_script.rb') }.to raise_error(RuntimeError, /Failed to unlock test_script.rb/)
    end
  end

  describe '#script_instrumented' do
    it 'returns instrumented script when successful' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '{"title": "Instrumented Script", "description": "[\"line1\",\"line2\"]"}'))
      expect(script_runner.script_instrumented('test_script.rb', 'puts "Hello"')).to eq("line1\nline2")
    end

    it 'raises an error when instrumentation fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '{"title": "Instrumentation Error", "description": "Failed to instrument"}'))
      expect { script_runner.script_instrumented('test_script.rb', 'invalid code') }.to raise_error(RuntimeError, /{"title"=>"Instrumentation Error"/)
    end
  end

  describe '#script_create' do
    it 'creates a script successfully' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '{"success": true}'))
      expect(script_runner.script_create('new_script.rb', 'puts "Hello"')).to eq({"success" => true})
    end

    it 'raises an error when creation fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.script_create('new_script.rb', 'puts "Hello"') }.to raise_error(RuntimeError, /Script create request failed/)
    end
  end

  describe '#script_delete_all_breakpoints' do
    it 'deletes all breakpoints successfully' do
      expect(script_runner.script_delete_all_breakpoints).to be true
    end

    it 'raises an error when deletion fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.script_delete_all_breakpoints }.to raise_error(RuntimeError, /Script delete all breakpoints failed/)
    end
  end

  describe '#running_script_list' do
    it 'returns a list of running scripts' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '[{"id": 1, "name": "running_script.rb"}]'))
      expect(script_runner.running_script_list).to eq([{"id" => 1, "name" => "running_script.rb"}])
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.running_script_list }.to raise_error(RuntimeError, /Running script list request failed/)
    end
  end

  describe '#running_script_get' do
    it 'returns details of a running script' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '{"id": 1, "name": "running_script.rb", "status": "running"}'))
      expect(script_runner.running_script_get(1)).to eq({"id" => 1, "name" => "running_script.rb", "status" => "running"})
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 404, body: 'Not Found'))
      expect { script_runner.running_script_get(999) }.to raise_error(RuntimeError, /Running script show request failed/)
    end
  end

  describe 'running script actions' do
    %w[stop pause retry go step delete backtrace].each do |action|
      it "performs #{action} action on a running script" do
        expect(script_runner.send("running_script_#{action}", 1)).to be true
      end

      it "raises an error when #{action} action fails" do
        allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
        expect { script_runner.send("running_script_#{action}", 1) }.to raise_error(RuntimeError, /Running script #{action} request failed/)
      end
    end
  end

  describe '#running_script_debug' do
    it 'performs debug action on a running script' do
      expect(script_runner.running_script_debug(1, 'puts "Debug"')).to be true
    end

    it 'raises an error when debug action fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.running_script_debug(1, 'puts "Debug"') }.to raise_error(RuntimeError, /Running script debug request failed/)
    end
  end

  describe '#running_script_prompt' do
    it 'responds to a prompt in a running script' do
      expect(script_runner.running_script_prompt(1, 'ask', 'Yes', 'prompt1')).to be true
    end

    it 'handles password prompts' do
      expect(script_runner.running_script_prompt(1, 'ask_password', 'secret', 'prompt2', password: true)).to be true
    end

    it 'raises an error when prompt action fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.running_script_prompt(1, 'ask', 'Yes', 'prompt1') }.to raise_error(RuntimeError, /Running script prompt request failed/)
    end
  end

  describe '#completed_script_list' do
    it 'returns a list of completed scripts' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 200, body: '[{"id": 1, "name": "completed_script.rb"}]'))
      expect(script_runner.completed_script_list).to eq([{"id" => 1, "name" => "completed_script.rb"}])
    end

    it 'raises an error when the request fails' do
      allow($script_runner_api_server).to receive(:request).and_return(OpenStruct.new(status: 500, body: 'Error'))
      expect { script_runner.completed_script_list }.to raise_error(RuntimeError, /Completed script list request failed/)
    end
  end
end
