# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
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

require "rails_helper"
require "tempfile"

RSpec.describe RunningScript, type: :model do
  before(:each) do
    mock_redis
    RunningScript.clear_breakpoints
    RunningScript.file_cache = {}
    RunningScript.instrumented_cache = {}

    # Allow puts to prevent output during tests
    allow($stdout).to receive(:puts)
    allow($stderr).to receive(:puts)
    allow_any_instance_of(IO).to receive(:puts)
    allow_any_instance_of(StringIO).to receive(:puts)
  end

  describe "self.spawn" do
    before do
      # Only mock the process spawning parts to avoid actual process creation
      process_double = double("process")
      allow(process_double).to receive(:io).and_return(double("io", inherit!: nil))
      allow(process_double).to receive(:cwd=)
      allow(process_double).to receive(:environment).and_return({})
      allow(process_double).to receive(:detach=)
      allow(process_double).to receive(:start)
      allow(ChildProcess).to receive(:build).and_return(process_double)
    end

    it "spawns a ruby script process" do
      expect(ChildProcess).to receive(:build).with("ruby", anything, "1", "DEFAULT")

      result = RunningScript.spawn("DEFAULT", "script.rb")
      expect(result).to eq(1)
    end

    it "spawns a python script process" do
      expect(ChildProcess).to receive(:build).with("python", anything, "1", "DEFAULT")

      result = RunningScript.spawn("DEFAULT", "script.py")
      expect(result).to eq(1)
    end

    it "creates a script status model with appropriate parameters" do
      allow(OpenC3::ScriptStatusModel).to receive(:new).and_call_original

      expect(OpenC3::ScriptStatusModel).to receive(:new).with(
        hash_including(
          name: "1",
          state: "spawning",
          shard: 0,
          filename: "script.rb",
          current_filename: "script.rb",
          line_no: 0,
          start_line_no: 1,
          username: "Anonymous",
          user_full_name: "Anonymous",
          disconnect: false,
          scope: "DEFAULT"
        )
      )

      RunningScript.spawn("DEFAULT", "script.rb")
    end

    it "uses custom username and user_full_name when provided" do
      allow(OpenC3::ScriptStatusModel).to receive(:new).and_call_original

      expect(OpenC3::ScriptStatusModel).to receive(:new).with(
        hash_including(
          username: "testuser",
          user_full_name: "Test User"
        )
      )

      RunningScript.spawn("DEFAULT", "script.rb", nil, false, nil, "Test User", "testuser")
    end

    it "handles offline access token when username is provided" do
      # We need to mock the offline access model and auth parts
      model_double = double("model", offline_access_token: "valid_token", update: nil)
      auth_double = double("auth")
      allow(auth_double).to receive(:get_token_from_refresh_token).and_return(true)
      allow(OpenC3::OpenC3KeycloakAuthentication).to receive(:new).and_return(auth_double)
      allow(OpenC3::OfflineAccessModel).to receive(:get_model).with(name: "testuser", scope: "DEFAULT").and_return(model_double)

      process_env_double = {}
      process_double = double("process")
      allow(process_double).to receive(:io).and_return(double("io", inherit!: nil))
      allow(process_double).to receive(:cwd=)
      allow(process_double).to receive(:environment).and_return(process_env_double)
      allow(process_double).to receive(:detach=)
      allow(process_double).to receive(:start)
      allow(ChildProcess).to receive(:build).and_return(process_double)

      RunningScript.spawn("DEFAULT", "script.rb", nil, false, nil, "Test User", "testuser")

      expect(process_env_double["OPENC3_API_TOKEN"]).to eq("valid_token")
    end

    it "raises an error if offline token is invalid" do
      # Mock just the authentication parts
      model_double = double("model", offline_access_token: "invalid_token", update: nil)
      allow(model_double).to receive(:offline_access_token=)
      auth_double = double("auth")
      allow(auth_double).to receive(:get_token_from_refresh_token).and_return(false)
      allow(OpenC3::OpenC3KeycloakAuthentication).to receive(:new).and_return(auth_double)
      allow(OpenC3::OfflineAccessModel).to receive(:get_model).with(name: "testuser", scope: "DEFAULT").and_return(model_double)

      expect {
        RunningScript.spawn("DEFAULT", "script.rb", nil, false, nil, "Test User", "testuser")
      }.to raise_error("offline_access token invalid for script")
    end
  end

  describe "self.instrument_script" do
    it "adds instrumentation code to Ruby scripts" do
      simple_script = "puts 'Hello'"
      result = RunningScript.instrument_script(simple_script, "test.rb")

      # Verify that the instrumentation adds pre and post line hooks
      expect(result).to include("RunningScript.instance.script_binding = binding()")
      expect(result).to include("RunningScript.instance.pre_line_instrumentation")
      expect(result).to include("RunningScript.instance.post_line_instrumentation")
      expect(result).to include("rescue Exception => eval_error")
    end

    it "caches the script text when cache is true" do
      simple_script = "puts 'Hello'"

      RunningScript.instrument_script(simple_script, "test.rb", true, cache: true)

      expect(RunningScript.file_cache["test.rb"]).to eq(simple_script)
    end

    it "doesn't cache the script text when cache is false" do
      simple_script = "puts 'Hello'"

      RunningScript.instrument_script(simple_script, "test.rb", true, cache: false)

      expect(RunningScript.file_cache["test.rb"]).to be_nil
    end

    it "adds line_offset to instrumentation for partial scripts" do
      simple_script = "puts 'Line 10'"
      result = RunningScript.instrument_script(simple_script, "test.rb", true, line_offset: 9)

      # Check that the line number in the instrumentation is offset
      expect(result).to include("RunningScript.instance.pre_line_instrumentation('test.rb', 10)")
    end

    it "marks the script as private when mark_private is true" do
      simple_script = "puts 'Hello'"
      result = RunningScript.instrument_script(simple_script, "test.rb", true)

      # Check that the private keyword is added
      expect(result).to start_with("private;")
    end

    it "doesn't mark the script as private when mark_private is false" do
      simple_script = "puts 'Hello'"
      result = RunningScript.instrument_script(simple_script, "test.rb", false)

      # Check that the private keyword is not added
      expect(result).not_to start_with("private;")
    end
  end

  describe "initialization and state management" do
    let(:script_status) {
      OpenC3::ScriptStatusModel.new(
        name: "12345",
        state: "running",
        shard: 0,
        filename: "test_script.rb",
        current_filename: "test_script.rb",
        line_no: 0,
        start_line_no: 1,
        username: "test_user",
        user_full_name: "Test User",
        start_time: Time.now.utc.iso8601,
        disconnect: false,
        scope: "DEFAULT"
      )
    }

    before do
      # Allow script status to be created but not actually stored
      allow(script_status).to receive(:create)
      allow(script_status).to receive(:update)

      # Mock script retrieval
      allow(::Script).to receive(:body).and_return("puts 'Test Script'")
      allow(::Script).to receive(:get_breakpoints).and_return([])

      # Prevent actual message logging
      allow(OpenC3::MessageLog).to receive(:new).and_return(double("message_log", write: nil))

      # Prevent actual IO redirection
      allow_any_instance_of(RunningScript).to receive(:redirect_io)

      # Prevent actual script running and anycable publishing
      allow_any_instance_of(RunningScript).to receive(:running_script_anycable_publish)
    end

    it "correctly manages step/go/pause internal flags" do
      # Set up RunningScript instance
      running_script = RunningScript.new(script_status)

      # Test step mode
      running_script.step
      expect(running_script.instance_variable_get(:@step)).to be true
      expect(running_script.instance_variable_get(:@go)).to be true
      expect(running_script.instance_variable_get(:@pause)).to be true

      # Test go mode
      running_script.go
      expect(running_script.instance_variable_get(:@step)).to be false
      expect(running_script.instance_variable_get(:@go)).to be true
      expect(running_script.instance_variable_get(:@pause)).to be false

      # Test pause mode
      running_script.pause
      expect(running_script.instance_variable_get(:@go)).to be false
      expect(running_script.instance_variable_get(:@pause)).to be true

      # Test continue with step mode on
      running_script.instance_variable_set(:@step, true)
      running_script.continue
      expect(running_script.instance_variable_get(:@go)).to be true
      expect(running_script.instance_variable_get(:@pause)).to be true
    end

    it "handles stopping a script" do
      # Set up RunningScript instance
      running_script = RunningScript.new(script_status)

      # Setup the class variable directly
      thread_double = double("thread")
      allow(OpenC3).to receive(:kill_thread)

      RunningScript.class_variable_set(:@@run_thread, thread_double)

      # Test stopping the script
      running_script.stop

      expect(running_script.instance_variable_get(:@stop)).to be true
      expect(script_status.state).to eq("stopped")
      expect(script_status.end_time).not_to be_nil

      # Reset the class variable after the test
      RunningScript.class_variable_set(:@@run_thread, nil)
    end
  end

  describe "breakpoint management" do
    it "sets a breakpoint" do
      RunningScript.set_breakpoint("test.rb", 10)

      breakpoints = RunningScript.breakpoints
      expect(breakpoints["test.rb"][10]).to be true
    end

    it "clears a specific breakpoint" do
      RunningScript.set_breakpoint("test.rb", 10)
      RunningScript.set_breakpoint("test.rb", 20)

      RunningScript.clear_breakpoint("test.rb", 10)

      breakpoints = RunningScript.breakpoints
      expect(breakpoints["test.rb"][10]).to be_nil
      expect(breakpoints["test.rb"][20]).to be true
    end

    it "clears all breakpoints for a file" do
      RunningScript.set_breakpoint("test.rb", 10)
      RunningScript.set_breakpoint("test.rb", 20)
      RunningScript.set_breakpoint("other.rb", 30)

      RunningScript.clear_breakpoints("test.rb")

      breakpoints = RunningScript.breakpoints
      expect(breakpoints["test.rb"]).to be_nil
      expect(breakpoints["other.rb"][30]).to be true
    end

    it "clears all breakpoints when no filename is given" do
      RunningScript.set_breakpoint("test.rb", 10)
      RunningScript.set_breakpoint("other.rb", 20)

      RunningScript.clear_breakpoints

      expect(RunningScript.breakpoints).to eq({})
    end
  end

  describe "parse_options" do
    let(:script_status) {
      OpenC3::ScriptStatusModel.new(
        name: "12345",
        state: "running",
        shard: 0,
        filename: "test_script.rb",
        current_filename: "test_script.rb",
        line_no: 0,
        start_line_no: 1,
        username: "test_user",
        user_full_name: "Test User",
        start_time: Time.now.utc.iso8601,
        disconnect: false,
        scope: "DEFAULT"
      )
    }

    before do
      # Allow script status to be created but not actually stored
      allow(script_status).to receive(:create)
      allow(script_status).to receive(:update)

      # Mock script retrieval
      allow(::Script).to receive(:body).and_return("puts 'Test Script'")
      allow(::Script).to receive(:get_breakpoints).and_return([])

      # Prevent actual message logging and IO redirection
      allow(OpenC3::MessageLog).to receive(:new).and_return(double("message_log", write: nil))
      allow_any_instance_of(RunningScript).to receive(:redirect_io)
      allow_any_instance_of(RunningScript).to receive(:running_script_anycable_publish)
    end

    it "sets manual mode when given 'manual' option" do
      running_script = RunningScript.new(script_status)
      running_script.parse_options(["manual"])

      expect($manual).to be true
      expect(OpenC3::SuiteRunner.settings["Manual"]).to be true
    end

    it "sets pauseOnError when given 'pauseOnError' option" do
      running_script = RunningScript.new(script_status)
      running_script.parse_options(["pauseOnError"])

      expect(RunningScript.pause_on_error).to be true
      expect(OpenC3::SuiteRunner.settings["Pause on Error"]).to be true
    end

    it "sets continueAfterError when given 'continueAfterError' option" do
      running_script = RunningScript.new(script_status)
      running_script.parse_options(["continueAfterError"])

      expect(running_script.continue_after_error).to be true
      expect(OpenC3::SuiteRunner.settings["Continue After Error"]).to be true
    end

    it "sets abortAfterError when given 'abortAfterError' option" do
      running_script = RunningScript.new(script_status)
      running_script.parse_options(["abortAfterError"])

      expect(OpenC3::Test.abort_on_exception).to be true
      expect(OpenC3::SuiteRunner.settings["Abort After Error"]).to be true
    end

    it "configures multiple options correctly" do
      running_script = RunningScript.new(script_status)
      running_script.parse_options(["manual", "pauseOnError", "loop", "breakLoopOnError"])

      expect($manual).to be true
      expect(RunningScript.pause_on_error).to be true
      expect(OpenC3::SuiteRunner.settings["Loop"]).to be true
      expect(OpenC3::SuiteRunner.settings["Break Loop On Error"]).to be true
    end
  end

  describe "instrumentation methods" do
    let(:script_status) {
      OpenC3::ScriptStatusModel.new(
        name: "12345",
        state: "running",
        shard: 0,
        filename: "test_script.rb",
        current_filename: "test_script.rb",
        line_no: 0,
        start_line_no: 1,
        username: "test_user",
        user_full_name: "Test User",
        start_time: Time.now.utc.iso8601,
        disconnect: false,
        scope: "DEFAULT"
      )
    }

    before do
      # Allow script status to be created but not actually stored
      allow(script_status).to receive(:create)
      allow(script_status).to receive(:update)

      # Mock script retrieval
      allow(::Script).to receive(:body).and_return("puts 'Test Script'")
      allow(::Script).to receive(:get_breakpoints).and_return([])

      # Prevent actual message logging
      allow(OpenC3::MessageLog).to receive(:new).and_return(double("message_log", write: nil))

      # Prevent actual IO redirection
      allow_any_instance_of(RunningScript).to receive(:redirect_io)

      # Prevent actual script running
      allow_any_instance_of(RunningScript).to receive(:handle_potential_tab_change)
      allow_any_instance_of(RunningScript).to receive(:handle_pause)
      allow_any_instance_of(RunningScript).to receive(:handle_line_delay)
      allow_any_instance_of(RunningScript).to receive(:handle_output_io)
      allow_any_instance_of(RunningScript).to receive(:running_script_anycable_publish)
      allow_any_instance_of(RunningScript).to receive(:update_running_script_store)
    end

    describe "pre_line_instrumentation" do
      it "updates script status with current filename and line number" do
        running_script = RunningScript.new(script_status)

        running_script.use_instrumentation = true

        expect(OpenC3::Logger).to receive(:detail_string=).with("new_file.rb:42")
        expect(running_script).to receive(:update_running_script_store).with("running")
        expect(running_script).to receive(:running_script_anycable_publish).with(
          "running-script-channel:12345",
          {
            type: :line,
            filename: "new_file.rb",
            line_no: 42,
            state: script_status.state
          }
        )

        running_script.pre_line_instrumentation("new_file.rb", 42)

        expect(script_status.current_filename).to eq("new_file.rb")
        expect(script_status.line_no).to eq(42)
      end

      it "raises StopScript if stop flag is set" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = true

        running_script.instance_variable_set(:@stop, true)

        # Call pre_line_instrumentation and expect it to raise StopScript
        expect {
          running_script.pre_line_instrumentation("new_file.rb", 42)
        }.to raise_error(OpenC3::StopScript)
      end

      it "doesn't update anything when use_instrumentation is false" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = false

        expect(running_script).not_to receive(:update_running_script_store)
        expect(running_script).not_to receive(:running_script_anycable_publish)

        running_script.pre_line_instrumentation("new_file.rb", 42)
      end
    end

    describe "post_line_instrumentation" do
      it "calls handle_output_io when instrumentation is enabled" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = true

        expect(running_script).to receive(:handle_output_io).with("new_file.rb", 42)

        running_script.post_line_instrumentation("new_file.rb", 42)
      end

      it "doesn't call handle_output_io when instrumentation is disabled" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = false

        expect(running_script).not_to receive(:handle_output_io)

        running_script.post_line_instrumentation("new_file.rb", 42)
      end

      it "adjusts line number with line_offset" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = true

        running_script.instance_variable_set(:@line_offset, 10)

        expect(running_script).to receive(:handle_output_io).with("new_file.rb", 52) # 42 + 10

        running_script.post_line_instrumentation("new_file.rb", 42)
      end
    end

    describe "exception_instrumentation" do
      it "re-raises StopScript and SkipScript exceptions" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = true

        stop_script_error = OpenC3::StopScript.new
        skip_script_error = OpenC3::SkipScript.new

        expect {
          running_script.exception_instrumentation(stop_script_error, "test.rb", 10)
        }.to raise_error(OpenC3::StopScript)

        expect {
          running_script.exception_instrumentation(skip_script_error, "test.rb", 10)
        }.to raise_error(OpenC3::SkipScript)
      end

      it "calls handle_exception for non-StopScript/SkipScript exceptions" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = true

        standard_error = StandardError.new("Test error")

        expect(running_script).to receive(:handle_exception).with(standard_error, false, "test.rb", 10)

        running_script.exception_instrumentation(standard_error, "test.rb", 10)
      end

      it "adjusts line number with line_offset" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = true

        running_script.instance_variable_set(:@line_offset, 10)

        standard_error = StandardError.new("Test error")

        # Expect handle_exception to be called with adjusted line number
        expect(running_script).to receive(:handle_exception).with(standard_error, false, "test.rb", 20) # 10 + 10

        running_script.exception_instrumentation(standard_error, "test.rb", 10)
      end

      it "doesn't handle exceptions when use_instrumentation is false" do
        running_script = RunningScript.new(script_status)
        running_script.use_instrumentation = false

        standard_error = StandardError.new("Test error")

        expect(running_script).not_to receive(:handle_exception)

        expect {
          running_script.exception_instrumentation(standard_error, "test.rb", 10)
        }.to raise_error(StandardError)
      end
    end
  end
end
