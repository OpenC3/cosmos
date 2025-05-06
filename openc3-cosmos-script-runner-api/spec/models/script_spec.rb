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
require "open3"

RSpec.describe Script, type: :model do
  before(:each) do
    mock_redis
  end

  describe "self.all" do
    it "gets all scripts" do
      allow(OpenC3::TargetFile).to receive(:all).and_return(["script1", "script2"])
      expect(Script.all("DEFAULT")).to eq(["script1", "script2"])
    end

    it "gets all scripts for a target" do
      allow(OpenC3::TargetFile).to receive(:all).and_return(["script1", "script2"])
      expect(Script.all("DEFAULT", "TARGET")).to eq(["script1", "script2"])
    end
  end

  describe "self.lock, self.unlock, self.locked?" do
    it "locks and unlocks scripts" do
      name = "script.rb"
      username = "user1"

      # Not locked initially
      expect(Script.locked?("DEFAULT", name)).to be false

      # Lock the script
      Script.lock("DEFAULT", name, username)
      expect(Script.locked?("DEFAULT", name)).to eq username

      # Unlock the script
      Script.unlock("DEFAULT", name)
      expect(Script.locked?("DEFAULT", name)).to be false
    end

    it "handles modified script names with asterisks" do
      name = "script.rb*"
      username = "user1"

      Script.lock("DEFAULT", name, username)
      expect(Script.locked?("DEFAULT", name)).to eq username
      expect(Script.locked?("DEFAULT", "script.rb")).to eq username

      Script.unlock("DEFAULT", name)
      expect(Script.locked?("DEFAULT", name)).to be false
    end
  end

  describe "self.get_breakpoints" do
    it "returns breakpoints for a script" do
      name = "script.rb"
      breakpoints = [10, 20, 30]

      # Store breakpoints
      OpenC3::Store.hset("DEFAULT__script-breakpoints", name, breakpoints.to_json)

      # Retrieve breakpoints
      expect(Script.get_breakpoints("DEFAULT", name)).to eq breakpoints
    end

    it "returns empty array if no breakpoints exist" do
      name = "no_breakpoints.rb"
      expect(Script.get_breakpoints("DEFAULT", name)).to eq []
    end

    it "handles modified script names with asterisks" do
      name = "script.rb*"
      breakpoints = [10, 20, 30]

      # Store breakpoints
      OpenC3::Store.hset("DEFAULT__script-breakpoints", "script.rb", breakpoints.to_json)

      # Retrieve breakpoints
      expect(Script.get_breakpoints("DEFAULT", name)).to eq breakpoints
    end
  end

  describe "self.create" do
    it "creates a new script" do
      params = {
        scope: "DEFAULT",
        name: "new_script.rb",
        text: "puts 'Hello'",
        breakpoints: [5, 10]
      }

      allow(Script).to receive(:body).and_return(nil)
      expect(OpenC3::TargetFile).to receive(:create).with("DEFAULT", "new_script.rb", "puts 'Hello'")

      Script.create(params)

      # Verify breakpoints were stored
      stored_breakpoints = OpenC3::Store.hget("DEFAULT__script-breakpoints", "new_script.rb")
      expect(JSON.parse(stored_breakpoints)).to eq([5, 10])
    end

    it "updates an existing script if text changed" do
      params = {
        scope: "DEFAULT",
        name: "existing_script.rb",
        text: "puts 'Updated'",
        breakpoints: [15]
      }

      allow(Script).to receive(:body).and_return("puts 'Original'")
      expect(OpenC3::TargetFile).to receive(:create).with("DEFAULT", "existing_script.rb", "puts 'Updated'")

      Script.create(params)

      # Verify breakpoints were stored
      stored_breakpoints = OpenC3::Store.hget("DEFAULT__script-breakpoints", "existing_script.rb")
      expect(JSON.parse(stored_breakpoints)).to eq([15])
    end

    it "doesn't update if text hasn't changed" do
      params = {
        scope: "DEFAULT",
        name: "existing_script.rb",
        text: "puts 'Same'",
        breakpoints: [15]
      }

      allow(Script).to receive(:body).and_return("puts 'Same'")
      expect(OpenC3::TargetFile).not_to receive(:create)

      Script.create(params)

      # Verify breakpoints were still stored
      stored_breakpoints = OpenC3::Store.hget("DEFAULT__script-breakpoints", "existing_script.rb")
      expect(JSON.parse(stored_breakpoints)).to eq([15])
    end

    it "removes breakpoints key if breakpoints array is empty" do
      params = {
        scope: "DEFAULT",
        name: "script.rb",
        text: "puts 'Hello'",
        breakpoints: []
      }

      allow(Script).to receive(:body).and_return(nil)
      expect(OpenC3::TargetFile).to receive(:create).with("DEFAULT", "script.rb", "puts 'Hello'")

      # Pre-store breakpoints
      OpenC3::Store.hset("DEFAULT__script-breakpoints", "script.rb", [5, 10].to_json)

      Script.create(params)

      # Verify breakpoints were removed
      stored_breakpoints = OpenC3::Store.hget("DEFAULT__script-breakpoints", "script.rb")
      expect(stored_breakpoints).to be_nil
    end
  end

  describe "self.delete_temp" do
    it "deletes temporary scripts and their breakpoints" do
      allow(OpenC3::TargetFile).to receive(:delete_temp).and_return(["temp1.rb", "temp2.rb"])

      # Pre-store breakpoints
      OpenC3::Store.hset("DEFAULT__script-breakpoints", "temp/temp1.rb", [5, 10].to_json)
      OpenC3::Store.hset("DEFAULT__script-breakpoints", "temp/temp2.rb", [15, 20].to_json)

      Script.delete_temp("DEFAULT")

      # Verify breakpoints were removed
      expect(OpenC3::Store.hget("DEFAULT__script-breakpoints", "temp1.rb")).to be_nil
      expect(OpenC3::Store.hget("DEFAULT__script-breakpoints", "temp2.rb")).to be_nil
    end
  end

  describe "self.destroy" do
    it "deletes a script and its breakpoints" do
      name = "script_to_delete.rb"
      allow(OpenC3::TargetFile).to receive(:destroy)

      # Pre-store breakpoints
      OpenC3::Store.hset("DEFAULT__script-breakpoints", name, [5, 10].to_json)

      Script.destroy("DEFAULT", name)

      # Verify breakpoints were removed
      expect(OpenC3::Store.hget("DEFAULT__script-breakpoints", name)).to be_nil
    end
  end

  describe "self.run" do
    it "spawns a running script" do
      expect(RunningScript).to receive(:spawn).with(
        "DEFAULT", "script.rb", nil, false, nil, "User Name", "username", nil, nil
      )

      Script.run("DEFAULT", "script.rb", nil, false, nil, "User Name", "username")
    end
  end

  describe "self.detect_language" do
    it "detects Ruby based on file extension" do
      expect(Script.detect_language("", "script.rb")).to eq "ruby"
    end

    it "detects Python based on file extension" do
      expect(Script.detect_language("", "script.py")).to eq "python"
    end

    it "detects Ruby based on require keyword" do
      expect(Script.detect_language("require 'openc3'")).to eq "ruby"
    end

    it "detects Ruby based on load keyword" do
      expect(Script.detect_language("load 'file.rb'")).to eq "ruby"
    end

    it "detects Ruby based on puts keyword" do
      expect(Script.detect_language("puts 'Hello'")).to eq "ruby"
    end

    it "detects Python based on import keyword" do
      expect(Script.detect_language("import openc3")).to eq "python"
    end

    it "detects Python based on from keyword" do
      expect(Script.detect_language("from openc3 import Script")).to eq "python"
    end

    it "detects Ruby based on end keyword" do
      expect(Script.detect_language("def method\n  puts 'Hello'\nend")).to eq "ruby"
    end

    it "detects Python based on colon syntax" do
      expect(Script.detect_language("def function():\n  print('Hello')")).to eq "python"
    end

    it "defaults to Ruby if no other indicators" do
      expect(Script.detect_language("# Just a comment")).to eq "ruby"
    end
  end

  describe "self.syntax" do
    it "fails if no text is provided" do
      result = Script.syntax("script.rb", nil)
      expect(result["title"]).to eq "Syntax Check Failed"
      expect(result["description"]).to eq "no text passed"
    end

    context "when checking Ruby syntax" do
      it "returns success for valid Ruby syntax" do
        allow_any_instance_of(IO).to receive(:readlines).and_return(["Syntax OK"])

        result = Script.syntax("script.rb", "puts 'Valid Ruby'")
        expect(result["title"]).to eq "Syntax Check Successful"
        expect(JSON.parse(result["description"])).to include("Syntax OK")
      end

      it "returns failure for invalid Ruby syntax" do
        allow_any_instance_of(IO).to receive(:readlines).and_return([":2: syntax error, unexpected end-of-input"])

        result = Script.syntax("script.rb", "puts 'Invalid Ruby")
        expect(result["title"]).to eq "Syntax Check Failed"
        expect(JSON.parse(result["description"])).to include("2: syntax error, unexpected end-of-input")
      end

      it "handles unexpected nil result" do
        allow_any_instance_of(IO).to receive(:readlines).and_return(nil)

        result = Script.syntax("script.rb", "puts 'Ruby with nil result'")
        expect(result["title"]).to eq "Syntax Check Exception"
        expect(result["description"]).to eq "Ruby syntax check unexpectedly returned nil"
      end
    end

    context "when checking Python syntax" do
      it "returns success for valid Python syntax" do
        allow(Open3).to receive(:capture2e).and_return(["", 0])

        result = Script.syntax("script.py", "print('Valid Python')")
        expect(result["title"]).to eq "Syntax Check Successful"
        expect(JSON.parse(result["description"])).to eq(["Syntax OK"])
      end

      it "returns failure for invalid Python syntax" do
        allow(Open3).to receive(:capture2e).and_return(["SyntaxError: invalid syntax", 1])

        result = Script.syntax("script.py", "print('Invalid Python'")
        expect(result["title"]).to eq "Syntax Check Failed"
        expect(JSON.parse(result["description"])).to include("SyntaxError: invalid syntax")
      end
    end
  end

  describe "self.instrumented" do
    context "for Ruby scripts" do
      it "returns instrumented Ruby code" do
        allow(RunningScript).to receive(:instrument_script).and_return("instrumented Ruby code")

        result = Script.instrumented("script.rb", "puts 'Hello'")
        expect(result["title"]).to eq "Instrumented Script"
        expect(JSON.parse(result["description"])).to eq(["instrumented Ruby code"])
      end
    end
  end

  describe "self.process_suite" do
    # Helper method to set up common mocks for process_suite tests
    def setup_process_suite_mocks(language:, stdout_content: '{"suite":"data"}', stderr_content: "", exit_code: 0)
      extension = (language == "ruby") ? ".rb" : ".py"

      # Create mock suite tempfile
      temp_path = File.join(Dir.tmpdir, "temp#{extension}")
      suite_tempfile = double("tempfile", write: nil, close: nil, path: temp_path, delete: nil)
      allow(Tempfile).to receive(:new).with(["suite", extension]).and_return(suite_tempfile)

      # Setup ChildProcess to avoid trying to spawn real processes
      process_env = {}
      io_double = double("io")
      allow(io_double).to receive(:stdout=)
      allow(io_double).to receive(:stderr=)

      process_double = double("process")
      allow(process_double).to receive(:cwd=)
      allow(process_double).to receive(:environment).and_return(process_env)
      allow(process_double).to receive(:io).and_return(io_double)
      allow(process_double).to receive(:start)
      allow(process_double).to receive(:wait)
      allow(process_double).to receive(:exit_code).and_return(exit_code)

      allow(ChildProcess).to receive(:build).and_return(process_double)

      # Mock stdout/stderr tempfiles
      stdout_double = double("stdout")
      allow(stdout_double).to receive(:sync=)
      allow(stdout_double).to receive(:rewind)
      allow(stdout_double).to receive(:read).and_return(stdout_content)
      allow(stdout_double).to receive(:close)
      allow(stdout_double).to receive(:unlink)

      stderr_double = double("stderr")
      allow(stderr_double).to receive(:sync=)
      allow(stderr_double).to receive(:rewind)
      allow(stderr_double).to receive(:read).and_return(stderr_content)
      allow(stderr_double).to receive(:close)
      allow(stderr_double).to receive(:unlink)

      allow(Tempfile).to receive(:new).with("child-stdout").and_return(stdout_double)
      allow(Tempfile).to receive(:new).with("child-stderr").and_return(stderr_double)

      {process_env: process_env}
    end

    context "with successful execution" do
      it "processes Ruby suite files" do
        setup_process_suite_mocks(language: "ruby")

        stdout_result, stderr_result, success = Script.process_suite("suite.rb", "suite content", scope: "DEFAULT")

        expect(stdout_result).to eq '{"suite":"data"}'
        expect(stderr_result).to eq ""
        expect(success).to be true
      end

      it "processes Python suite files" do
        setup_process_suite_mocks(language: "python")

        stdout_result, stderr_result, success = Script.process_suite("suite.py", "suite content", scope: "DEFAULT")

        expect(stdout_result).to eq '{"suite":"data"}'
        expect(stderr_result).to eq ""
        expect(success).to be true
      end
    end

    context "with offline access token" do
      it "uses the token when provided" do
        # Mock offline access model
        model_double = double("model", offline_access_token: "valid_token", update: nil)
        allow(OpenC3::OfflineAccessModel).to receive(:get_model).and_return(model_double)

        # Mock authentication
        auth_double = double("auth")
        allow(auth_double).to receive(:get_token_from_refresh_token).and_return(true)
        allow(OpenC3::OpenC3KeycloakAuthentication).to receive(:new).and_return(auth_double)

        # Setup process suite mocks
        mocks = setup_process_suite_mocks(language: "ruby")

        stdout_result, stderr_result, success = Script.process_suite("suite.rb", "suite content", username: "user1", scope: "DEFAULT")

        expect(mocks[:process_env]["OPENC3_API_TOKEN"]).to eq "valid_token"
        expect(stdout_result).to eq '{"suite":"data"}'
        expect(stderr_result).to eq ""
        expect(success).to be true
      end

      it "raises an error if offline token is invalid" do
        # Mock offline access model with invalid token
        model_double = double("model", offline_access_token: "invalid_token", update: nil)
        allow(model_double).to receive(:offline_access_token=)
        allow(OpenC3::OfflineAccessModel).to receive(:get_model).and_return(model_double)

        # Mock authentication failure
        auth_double = double("auth")
        allow(auth_double).to receive(:get_token_from_refresh_token).and_return(false)
        allow(OpenC3::OpenC3KeycloakAuthentication).to receive(:new).and_return(auth_double)

        expect do
          Script.process_suite("suite.rb", "suite content", username: "user1", scope: "DEFAULT")
        end.to raise_error("offline_access token invalid for script")
      end

      it "returns empty strings if service password isn't set for viewer users" do
        # No offline access model
        allow(OpenC3::OfflineAccessModel).to receive(:get_model).and_return(nil)

        # Remove service password
        original_env = ENV.to_hash
        ENV.delete("OPENC3_SERVICE_PASSWORD")

        stdout_result, stderr_result, success = Script.process_suite("suite.rb", "suite content", username: "viewer", scope: "DEFAULT")

        # Restore environment
        ENV.clear
        original_env.each { |k, v| ENV[k] = v }

        expect(stdout_result).to eq ""
        expect(stderr_result).to eq ""
        expect(success).to be false
      end
    end
  end
end
