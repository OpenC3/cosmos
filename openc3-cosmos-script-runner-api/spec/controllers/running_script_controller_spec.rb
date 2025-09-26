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

RSpec.describe RunningScriptController, type: :controller do
  before(:each) do
    mock_redis

    # Create a script in Redis
    script_status = OpenC3::ScriptStatusModel.new(
      name: "1",
      state: "running",
      scope: "DEFAULT",
      filename: "INST/procedures/test.rb",
      current_filename: "INST/procedures/test.rb",
      line_no: 10,
      start_time: Time.now.utc.iso8601,
      username: "test_user",
      user_full_name: "Test Tester"
    )
    script_status.create

    allow(OpenC3::Logger).to receive(:info)
  end

  describe "GET index" do
    it "returns a list of running scripts" do
      get :index, params: {"scope" => "DEFAULT"}
      expect(response.status).to eq(200)
      expect(response.content_type).to include("application/json")
      json = JSON.parse(response.body, symbolize_names: true)
      expect(json).to include(:items, :total)
      expect(json[:items]).to be_an(Array)
      expect(json[:total]).to eq(1)
    end

    it "respects limit and offset parameters" do
      get :index, params: {"scope" => "DEFAULT", "limit" => 1, "offset" => 0}
      expect(response.status).to eq(200)
      json = JSON.parse(response.body)
      expect(json["items"].size).to eq(1)

      get :index, params: {"scope" => "DEFAULT", "limit" => 1, "offset" => 1}
      expect(response.status).to eq(200)
      json = JSON.parse(response.body)
      expect(json["items"].size).to eq(0)
    end

    it "handles forbidden errors when authorization is enabled" do
      get :index
      expect(response.status).to eq(401)
    end
  end

  describe "GET show" do
    context "when script exists" do
      it "returns the script by id" do
        get :show, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
        expect(response.content_type).to include("application/json")

        json = JSON.parse(response.body, symbolize_names: true)
        expect(json[:name]).to eq("1")
        expect(json[:state]).to eq("running")
        expect(json[:filename]).to eq("INST/procedures/test.rb")
      end
    end

    context "when script does not exist" do
      it "returns not found" do
        get :show, params: {id: "999", scope: "DEFAULT"}

        expect(response.status).to eq(404)
      end
    end
  end

  describe "script control actions" do
    describe "POST stop" do
      context "when script exists" do
        it "stops the script" do
          expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "stop")

          post :stop, params: {id: "1", scope: "DEFAULT"}

          expect(response.status).to eq(200)
        end
      end

      context "when script does not exist" do
        it "returns not found" do
          post :stop, params: {id: "999", scope: "DEFAULT"}

          expect(response.status).to eq(404)
        end
      end
    end

    describe "POST pause" do
      context "when script exists" do
        it "pauses the script" do
          expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "pause")

          post :pause, params: {id: "1", scope: "DEFAULT"}

          expect(response.status).to eq(200)
        end
      end

      context "when script does not exist" do
        it "returns not found" do
          post :pause, params: {id: "999", scope: "DEFAULT"}

          expect(response.status).to eq(404)
        end
      end
    end

    describe "POST go" do
      context "when script exists" do
        it "resumes the script" do
          expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "go")

          post :go, params: {id: "1", scope: "DEFAULT"}

          expect(response.status).to eq(200)
        end
      end

      context "when script does not exist" do
        it "returns not found" do
          post :go, params: {id: "999", scope: "DEFAULT"}

          expect(response.status).to eq(404)
        end
      end
    end

    describe "POST step" do
      context "when script exists" do
        it "steps the script" do
          expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "step")

          post :step, params: {id: "1", scope: "DEFAULT"}

          expect(response.status).to eq(200)
        end
      end

      context "when script does not exist" do
        it "returns not found" do
          post :step, params: {id: "999", scope: "DEFAULT"}

          expect(response.status).to eq(404)
        end
      end
    end

    describe "POST retry" do
      context "when script exists" do
        it "retries the script" do
          expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "retry")

          post :retry, params: {id: "1", scope: "DEFAULT"}

          expect(response.status).to eq(200)
        end
      end

      context "when script does not exist" do
        it "returns not found" do
          post :retry, params: {id: "999", scope: "DEFAULT"}

          expect(response.status).to eq(404)
        end
      end
    end
  end

  describe "DELETE delete" do
    before(:each) do
      allow(Process).to receive(:kill)
      allow(Process).to receive(:getpgid)
    end

    context "when script exists" do
      before(:each) do
        # Create a script model with a pid for the delete action to work with
        script_model = double("ScriptModel")
        allow(script_model).to receive(:filename).and_return("INST/procedures/test.rb")
        allow(script_model).to receive(:pid).and_return("12345")
        allow(OpenC3::ScriptStatusModel).to receive(:get_model).and_return(script_model)
      end

      it "stops and deletes the script" do
        allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
        expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "stop")

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end

      it "uses SIGINT if stop command doesn't work" do
        # First call to Process.getpgid returns true (process still running)
        # Second call raises ESRCH (process stopped after SIGINT)
        call_count = 0
        allow(Process).to receive(:getpgid) do
          call_count += 1
          if call_count <= 10 # First 10 calls (for the first second)
            12345 # Return pid, meaning process is still running
          else
            raise Errno::ESRCH # Process has stopped
          end
        end

        expect(Process).to receive(:kill).with("SIGINT", 12345)
        expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "stop")

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end

      it "uses SIGKILL if process still doesn't stop" do
        # All calls to Process.getpgid return true (process never stops)
        allow(Process).to receive(:getpgid).and_return(12345)

        script_model = double("ScriptModel")
        allow(script_model).to receive(:filename).and_return("INST/procedures/test.rb")
        allow(script_model).to receive(:pid).and_return("12345")
        allow(script_model).to receive(:end_time=) do |value|
          @end_time = value
        end
        allow(script_model).to receive(:state=) do |value|
          @state = value
        end
        allow(script_model).to receive(:update)
        allow(OpenC3::ScriptStatusModel).to receive(:get_model).and_return(script_model)

        expect(Process).to receive(:kill).with("SIGINT", 12345)
        expect(Process).to receive(:kill).with("SIGKILL", 12345)
        expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).at_least(:once).with("cmd-running-script-channel:1", "stop")

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end
    end

    context "when script does not exist" do
      it "returns not found" do
        delete :delete, params: {id: "999", scope: "DEFAULT"}

        expect(response.status).to eq(404)
      end
    end
  end

  describe "script prompt interactions" do
    context "when script exists" do
      it "handles standard answer prompts" do
        expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).with(
          "cmd-running-script-channel:1",
          {method: "ask", answer: "yes", prompt_id: "abc123"}
        )

        post :prompt, params: {
          id: "1",
          scope: "DEFAULT",
          method: "ask",
          answer: "yes",
          prompt_id: "abc123"
        }

        expect(response.status).to eq(200)
      end

      it "handles password prompts" do
        expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).with(
          "cmd-running-script-channel:1",
          {method: "prompt_for_hazardous", password: "secret", prompt_id: "abc123"}
        )

        post :prompt, params: {
          id: "1",
          scope: "DEFAULT",
          method: "prompt_for_hazardous",
          password: "secret",
          prompt_id: "abc123"
        }

        expect(response.status).to eq(200)
      end

      it "handles multiple choice prompts" do
        multiple_options = ["option1", "option2"]

        expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).with(
          "cmd-running-script-channel:1",
          {method: "combo_box", multiple: JSON.generate(multiple_options, allow_nan: true), prompt_id: "abc123"}
        )

        post :prompt, params: {
          id: "1",
          scope: "DEFAULT",
          method: "combo_box",
          multiple: true,
          answer: multiple_options,
          prompt_id: "abc123"
        }

        expect(response.status).to eq(200)
      end
    end

    context "when script does not exist" do
      it "returns not found" do
        post :prompt, params: {
          id: "999",
          scope: "DEFAULT",
          prompt_id: "abc123"
        }

        expect(response.status).to eq(404)
      end
    end
  end

  describe "script method invocation" do
    context "when script exists" do
      it "invokes a method with arguments" do
        method_args = ["arg1", "arg2"]

        expect_any_instance_of(RunningScriptController).to receive(:running_script_publish).with(
          "cmd-running-script-channel:1",
          {method: "some_method", args: method_args, prompt_id: "abc123"}
        )

        post :method, params: {
          id: "1",
          scope: "DEFAULT",
          method: "some_method",
          args: method_args,
          prompt_id: "abc123"
        }

        expect(response.status).to eq(200)
      end
    end

    context "when script does not exist" do
      it "returns not found" do
        post :method, params: {
          id: "999",
          scope: "DEFAULT",
          method: "some_method",
          args: ["arg1", "arg2"],
          prompt_id: "abc123"
        }

        expect(response.status).to eq(404)
      end
    end
  end
end
