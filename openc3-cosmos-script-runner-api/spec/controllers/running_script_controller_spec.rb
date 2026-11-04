# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

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

    it "filters the list by the search parameter" do
      OpenC3::ScriptStatusModel.new(
        name: "2",
        state: "running",
        scope: "DEFAULT",
        filename: "INST/procedures/collect.rb",
        start_time: Time.now.utc.iso8601,
        username: "other_user",
        user_full_name: "Other User"
      ).create

      get :index, params: {"scope" => "DEFAULT", "search" => "collect"}
      expect(response.status).to eq(200)
      json = JSON.parse(response.body)
      expect(json["items"].size).to eq(1)
      expect(json["items"][0]["filename"]).to eq("INST/procedures/collect.rb")
      expect(json["total"]).to eq(1)
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
          expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "stop")

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
          expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "pause")

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
          expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "go")

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
          expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "step")

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
          expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "retry")

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
        allow(script_model).to receive(:is_complete?).and_return(false)
        allow(script_model).to receive(:end_time).and_return(nil)
        allow(script_model).to receive(:end_time=)
        allow(script_model).to receive(:state=)
        allow(script_model).to receive(:update)
        allow(OpenC3::ScriptStatusModel).to receive(:get_model).and_return(script_model)
      end

      it "stops and deletes the script" do
        allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "stop")

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end

      it "deletes the per-script signing key" do
        allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
        allow_any_instance_of(RunningScriptController).to receive(:publish_signed_command)
        OpenC3::Store.set("script-signing-key:1", "k" * 64)
        expect(OpenC3::Store.get("script-signing-key:1")).to eq("k" * 64)

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
        expect(OpenC3::Store.get("script-signing-key:1")).to be_nil
      end

      it "moves the script to completed if the process died without cleaning up" do
        allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
        allow_any_instance_of(RunningScriptController).to receive(:publish_signed_command)
        script_model = OpenC3::ScriptStatusModel.get_model(name: "1", scope: "DEFAULT")
        expect(script_model).to receive(:state=).with("killed")
        expect(script_model).to receive(:update)

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end

      it "leaves the script alone if the process already completed it" do
        allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
        allow_any_instance_of(RunningScriptController).to receive(:publish_signed_command)
        script_model = OpenC3::ScriptStatusModel.get_model(name: "1", scope: "DEFAULT")
        allow(script_model).to receive(:is_complete?).and_return(true)
        expect(script_model).not_to receive(:update)

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end

      it "re-fetches the model to see a completion written while stopping" do
        allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
        allow_any_instance_of(RunningScriptController).to receive(:publish_signed_command)
        # The initial fetch sees the script running, then the process
        # moves itself to completed before it exits
        running_model = OpenC3::ScriptStatusModel.get_model(name: "1", scope: "DEFAULT")
        completed_model = double("CompletedScriptModel")
        allow(completed_model).to receive(:filename).and_return("INST/procedures/test.rb")
        allow(completed_model).to receive(:is_complete?).and_return(true)
        allow(OpenC3::ScriptStatusModel).to receive(:get_model).and_return(running_model, completed_model)
        expect(running_model).not_to receive(:update)
        expect(completed_model).not_to receive(:update)

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
        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "stop")

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end

      it "uses SIGKILL if process still doesn't stop" do
        # All calls to Process.getpgid return true (process never stops)
        allow(Process).to receive(:getpgid).and_return(12345)

        script_model = double("ScriptModel")
        allow(script_model).to receive(:filename).and_return("INST/procedures/test.rb")
        allow(script_model).to receive(:pid).and_return("12345")
        allow(script_model).to receive(:is_complete?).and_return(false)
        allow(script_model).to receive(:end_time).and_return(nil)
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
        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "stop")

        delete :delete, params: {id: "1", scope: "DEFAULT"}

        expect(response.status).to eq(200)
      end
    end

    context "when script has no pid (spawn failed)" do
      it "skips process signaling and cleans up the status model" do
        script_model = double("ScriptModel")
        allow(script_model).to receive(:filename).and_return("INST/procedures/test.rb")
        allow(script_model).to receive(:pid).and_return(nil)
        allow(script_model).to receive(:is_complete?).and_return(false)
        allow(script_model).to receive(:end_time).and_return(nil)
        allow(script_model).to receive(:end_time=)
        allow(script_model).to receive(:state=)
        allow(script_model).to receive(:update)
        allow(OpenC3::ScriptStatusModel).to receive(:get_model).and_return(script_model)
        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).at_least(:once).with("1", "DEFAULT", "stop")

        expect(Process).not_to receive(:kill)
        expect(Process).not_to receive(:getpgid)

        expect(script_model).to receive(:state=).with("killed")
        expect(script_model).to receive(:update)

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
        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).with(
          "1", "DEFAULT",
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
        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).with(
          "1", "DEFAULT",
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

        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).with(
          "1", "DEFAULT",
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

        expect_any_instance_of(RunningScriptController).to receive(:publish_signed_command).with(
          "1", "DEFAULT",
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

  describe "signed control messages" do
    let(:signing_key) { "a" * 64 }
    let(:channel) { "script-api:cmd-running-script-channel:1" }

    def published
      messages = []
      without_partial_double_verification do
        allow(OpenC3::Store).to receive(:publish) { |ch, msg| messages << [ch, msg] }
      end
      messages
    end

    it "publishes a verifiable signed envelope for stop" do
      OpenC3::Store.set("script-signing-key:1", signing_key)
      messages = published
      post :stop, params: {id: "1", scope: "DEFAULT"}
      expect(response.status).to eq(200)
      expect(messages.length).to eq(1)
      expect(messages[0][0]).to eq(channel)
      env = JSON.parse(messages[0][1])
      expect(env["payload"]).to eq("stop")
      expect(OpenC3::ScriptMessageSigning.verify(signing_key, env)).to be true
      expect(OpenC3::ScriptMessageSigning.verify("b" * 64, env)).to be false
    end

    it "refreshes the signing key TTL" do
      OpenC3::Store.set("script-signing-key:1", signing_key)
      published
      post :stop, params: {id: "1", scope: "DEFAULT"}
      expect(OpenC3::Store.ttl("script-signing-key:1")).to be > 0
    end

    it "does not publish or raise when the signing key is absent" do
      messages = published
      post :stop, params: {id: "1", scope: "DEFAULT"}
      expect(response.status).to eq(200)
      expect(messages).to be_empty
    end

    it "signs the password prompt payload" do
      OpenC3::Store.set("script-signing-key:1", signing_key)
      messages = published
      post :prompt, params: {id: "1", scope: "DEFAULT", method: "ask", password: "secret", prompt_id: "abc123"}
      env = JSON.parse(messages[0][1])
      expect(env["payload"]).to eq({"method" => "ask", "password" => "secret", "prompt_id" => "abc123"})
      expect(OpenC3::ScriptMessageSigning.verify(signing_key, env)).to be true
    end

    it "signs the multiple prompt payload" do
      OpenC3::Store.set("script-signing-key:1", signing_key)
      messages = published
      post :prompt, params: {id: "1", scope: "DEFAULT", method: "combo_box", multiple: true, answer: ["a", "b"], prompt_id: "abc123"}
      env = JSON.parse(messages[0][1])
      expect(env["payload"]["multiple"]).to eq(JSON.generate(["a", "b"], allow_nan: true))
      expect(OpenC3::ScriptMessageSigning.verify(signing_key, env)).to be true
    end

    it "signs the answer prompt payload" do
      OpenC3::Store.set("script-signing-key:1", signing_key)
      messages = published
      post :prompt, params: {id: "1", scope: "DEFAULT", method: "ask", answer: "yes", prompt_id: "abc123"}
      env = JSON.parse(messages[0][1])
      expect(env["payload"]).to eq({"method" => "ask", "answer" => "yes", "prompt_id" => "abc123"})
      expect(OpenC3::ScriptMessageSigning.verify(signing_key, env)).to be true
    end

    it "stringifies a numeric answer so signing does not reject the Float" do
      # The signer rejects Floats (non-deterministic text form across languages). A
      # numeric ask reply like 1.5 must be stringified so the prompt is not blocked
      # by a 500; the runners convert the string back to a value.
      OpenC3::Store.set("script-signing-key:1", signing_key)
      messages = published
      post :prompt, params: {id: "1", scope: "DEFAULT", method: "ask", answer: 1.5, prompt_id: "abc123"}, as: :json
      expect(response.status).to eq(200)
      env = JSON.parse(messages[0][1])
      expect(env["payload"]).to eq({"method" => "ask", "answer" => "1.5", "prompt_id" => "abc123"})
      expect(OpenC3::ScriptMessageSigning.verify(signing_key, env)).to be true
    end

    it "signs the method payload" do
      OpenC3::Store.set("script-signing-key:1", signing_key)
      messages = published
      post :method, params: {id: "1", scope: "DEFAULT", method: "some_method", args: ["arg1"], prompt_id: "abc123"}
      env = JSON.parse(messages[0][1])
      expect(env["payload"]).to eq({"method" => "some_method", "args" => ["arg1"], "prompt_id" => "abc123"})
      expect(OpenC3::ScriptMessageSigning.verify(signing_key, env)).to be true
    end
  end
end
