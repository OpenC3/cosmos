# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "rails_helper"
require "openc3/utilities/aws_bucket"
require 'openc3/utilities/script'

RSpec.describe ScriptsController, type: :controller do
  before(:each) do
    ENV.delete("OPENC3_LOCAL_MODE")
    mock_redis
  end

  describe "ping" do
    it "returns OK" do
      get :ping
      expect(response.body).to eq("OK")
      expect(response).to have_http_status(:ok)
    end
  end

  describe "index" do
    it "returns all scripts" do
      scripts = [
        {"name" => "script1.rb", "modified_time" => Time.now.to_s},
        {"name" => "script2.rb", "modified_time" => Time.now.to_s}
      ]
      expect(Script).to receive(:all).with("DEFAULT", nil).and_return(scripts)

      get :index, params: {scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(2)
      expect(json[0]["name"]).to eq("script1.rb")
    end

    it "returns scripts filtered by target" do
      scripts = [
        {"name" => "INST/script1.rb", "modified_time" => Time.now.to_s}
      ]
      expect(Script).to receive(:all).with("DEFAULT", "INST").and_return(scripts)

      get :index, params: {scope: "DEFAULT", target: "INST"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.length).to eq(1)
      expect(json[0]["name"]).to eq("INST/script1.rb")
    end

    it "handles authorization failure" do
      get :index

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "delete_temp" do
    it "deletes temporary scripts" do
      deleted_files = ["temp/script1.rb", "temp/script2.rb"]
      expect(Script).to receive(:delete_temp).with("DEFAULT").and_return(deleted_files)

      post :delete_temp, params: {scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).length).to eq(2)
    end

    it "handles authorization failure" do
      post :delete_temp

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "create" do
    it "creates a script when none exist" do
      s3 = instance_double("Aws::S3::Client")
      # nil means no script exists
      allow(s3).to receive(:get_object).and_return(nil)
      # Expect to call put_object to store the new script
      expect(s3).to receive(:put_object)
      expect(s3).to receive(:wait_until)
      allow(Aws::S3::Client).to receive(:new).and_return(s3)

      post :create, params: {scope: "DEFAULT", name: "script.rb", text: "text"}
      expect(response).to have_http_status(:ok)
    end

    it "saves when text changes" do
      s3 = instance_double("Aws::S3::Client")
      # Simulate returning a file with 'new text'
      file = double("file")
      allow(file).to receive_message_chain(:body, read: "new text")
      expect(s3).to receive(:get_object).and_return(file)
      # Expect to call put_object to store the changed script
      expect(s3).to receive(:put_object)
      expect(s3).to receive(:wait_until)
      allow(Aws::S3::Client).to receive(:new).and_return(s3)

      post :create, params: {scope: "DEFAULT", name: "script.rb", text: "text"}
      expect(response).to have_http_status(:ok)
    end

    it "does not save when text is the same" do
      s3 = instance_double("Aws::S3::Client")
      # Simulate returning a file with identical 'text'
      file = double("file")
      allow(file).to receive_message_chain(:body, read: "text")
      expect(s3).to receive(:get_object).and_return(file)
      expect(s3).to_not receive(:put_object)
      allow(Aws::S3::Client).to receive(:new).and_return(s3)

      post :create, params: {scope: "DEFAULT", name: "script.rb", text: "text"}
      expect(response).to have_http_status(:ok)
    end

    it "does not pass params which aren't permitted" do
      expect(Script).to receive(:create) do |params|
        # Check that we don't pass extra params
        expect(params.keys).to eql(%w[text breakpoints scope name])
      end
      post :create, params: {scope: "DEFAULT", name: "script.rb", text: "text", breakpoints: [1], other: "nope"}
      expect(response).to have_http_status(:ok)
    end

    context "with the script lifecycle feature enabled" do
      before(:each) do
        OpenC3::SettingModel.set({name: 'script_runner_lifecycle', data: true}, scope: 'DEFAULT')
      end

      # Approved scripts cannot be saved (overwritten)
      it "rejects saving an approved script" do
        Script.set_lifecycle("DEFAULT", "script.rb", "review", "anonymous", "")
        Script.set_lifecycle("DEFAULT", "script.rb", "approved", "anonymous", "")
        expect(Script).not_to receive(:create)

        post :create, params: {scope: "DEFAULT", name: "script.rb", text: "text"}

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json["message"]).to match(/approved/)
      end

      it "saves a script that is not approved" do
        s3 = instance_double("Aws::S3::Client")
        allow(s3).to receive(:get_object).and_return(nil)
        expect(s3).to receive(:put_object)
        expect(s3).to receive(:wait_until)
        allow(Aws::S3::Client).to receive(:new).and_return(s3)
        Script.set_lifecycle("DEFAULT", "script.rb", "review", "anonymous", "")

        post :create, params: {scope: "DEFAULT", name: "script.rb", text: "text"}

        expect(response).to have_http_status(:ok)
      end
    end

    it "does not check the lifecycle when the feature is disabled" do
      expect(Script).not_to receive(:lifecycle)
      expect(Script).to receive(:create)

      post :create, params: {scope: "DEFAULT", name: "script.rb", text: "text"}

      expect(response).to have_http_status(:ok)
    end
  end

  describe "run" do
    it "returns an ok response" do
      expect(Script).to receive(:run).with("DEFAULT", "INST/procedures/test.rb", nil, false, nil, "Anonymous", "anonymous", 1, nil).and_return(1)
      post :run, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}
      expect(response).to have_http_status(:ok)
    end

    it "returns an error response" do
      expect(Script).to receive(:run).with("DEFAULT", "INST/procedures/test.rb", nil, false, nil, "Anonymous", "anonymous", 1, nil)
      post :run, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}
      expect(response).to have_http_status(:not_found)
    end

    context "with the script lifecycle feature enabled" do
      before(:each) do
        OpenC3::SettingModel.set({name: 'script_runner_lifecycle', data: true}, scope: 'DEFAULT')
        allow(OpenC3::Logger).to receive(:info)
      end

      it "runs an approved script without checking script_edit" do
        Script.set_lifecycle("DEFAULT", "INST/procedures/test.rb", "review", "anonymous", "")
        Script.set_lifecycle("DEFAULT", "INST/procedures/test.rb", "approved", "anonymous", "")
        expect(Script).to receive(:run).and_return(1)

        post :run, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

        expect(response).to have_http_status(:ok)
      end

      it "runs an unapproved script when the user has script_edit" do
        expect(Script).to receive(:run).and_return(1)

        post :run, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

        expect(response).to have_http_status(:ok)
      end
    end

    it "does not check the lifecycle when the feature is disabled" do
      expect(Script).not_to receive(:lifecycle)
      expect(Script).to receive(:run).and_return(1)

      post :run, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
    end
  end

  describe "body" do
    it "returns script content when the script exists" do
      script_content = "puts 'Hello World'"
      breakpoints = [1, 5]

      expect(Script).to receive(:body).with("DEFAULT", "INST/procedures/test.rb").and_return(script_content)
      expect(Script).to receive(:locked?).with("DEFAULT", "INST/procedures/test.rb").and_return(false)
      expect(Script).to receive(:lock).with("DEFAULT", "INST/procedures/test.rb", "anonymous")
      expect(Script).to receive(:get_breakpoints).with("DEFAULT", "INST/procedures/test.rb").and_return(breakpoints)

      get :body, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["contents"]).to eq(script_content)
      expect(json["breakpoints"]).to eq(breakpoints)
      expect(json["locked"]).to eq(false)
    end

    it "does not lock script if already locked" do
      script_content = "puts 'Hello World'"
      breakpoints = [1, 5]

      expect(Script).to receive(:body).with("DEFAULT", "INST/procedures/test.rb").and_return(script_content)
      expect(Script).to receive(:locked?).with("DEFAULT", "INST/procedures/test.rb").and_return(true)
      expect(Script).not_to receive(:lock)
      expect(Script).to receive(:get_breakpoints).with("DEFAULT", "INST/procedures/test.rb").and_return(breakpoints)

      get :body, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["contents"]).to eq(script_content)
      expect(json["locked"]).to eq(true)
    end

    it "processes suite files correctly" do
      script_content = "class TestSuite < OpenC3::Suite\n  def test_method\n    puts 'test'\n  end\nend"
      breakpoints = []
      suites_data = "{\"suites\":[]}"

      expect(Script).to receive(:body).with("DEFAULT", "INST/procedures/test.rb").and_return(script_content)
      expect(Script).to receive(:locked?).with("DEFAULT", "INST/procedures/test.rb").and_return(false)
      expect(Script).to receive(:lock).with("DEFAULT", "INST/procedures/test.rb", "anonymous")
      expect(Script).to receive(:get_breakpoints).with("DEFAULT", "INST/procedures/test.rb").and_return(breakpoints)
      expect(Script).to receive(:process_suite).with("INST/procedures/test.rb", script_content, username: "anonymous", scope: "DEFAULT").and_return([suites_data, nil, true])

      get :body, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["contents"]).to eq(script_content)
      expect(json["suites"]).to eq(suites_data)
      expect(json["success"]).to eq(true)
    end

    it "processes Python suite files correctly" do
      script_content = "class TestSuite(Suite):\n  def test_method(self):\n    print('test')\n"
      breakpoints = []
      suites_data = "{\"suites\":[]}"

      expect(Script).to receive(:body).with("DEFAULT", "INST/procedures/test.py").and_return(script_content)
      expect(Script).to receive(:locked?).with("DEFAULT", "INST/procedures/test.py").and_return(false)
      expect(Script).to receive(:lock).with("DEFAULT", "INST/procedures/test.py", "anonymous")
      expect(Script).to receive(:get_breakpoints).with("DEFAULT", "INST/procedures/test.py").and_return(breakpoints)
      expect(Script).to receive(:process_suite).with("INST/procedures/test.py", script_content, username: "anonymous", scope: "DEFAULT").and_return([suites_data, nil, true])

      get :body, params: {scope: "DEFAULT", name: "INST/procedures/test.py"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["contents"]).to eq(script_content)
      expect(json["suites"]).to eq(suites_data)
      expect(json["success"]).to eq(true)
    end

    it "returns not found when script does not exist" do
      expect(Script).to receive(:body).with("DEFAULT", "INST/procedures/nonexistent.rb").and_return(nil)
      get :body, params: {scope: "DEFAULT", name: "INST/procedures/nonexistent.rb"}

      expect(response).to have_http_status(:not_found)
    end

    it "handles authorization failure" do
      get :body, params: {name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "lock" do
    it "locks a script" do
      expect(Script).to receive(:lock).with("DEFAULT", "INST/procedures/test.rb", "anonymous")

      post :lock, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
    end

    it "handles authorization failure" do
      post :lock, params: {name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "unlock" do
    it "unlocks a script that is locked by the user" do
      expect(Script).to receive(:locked?).with("DEFAULT", "INST/procedures/test.rb").and_return("anonymous")
      expect(Script).to receive(:unlock).with("DEFAULT", "INST/procedures/test.rb")

      post :unlock, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
    end

    it "does not unlock a script locked by another user" do
      expect(Script).to receive(:locked?).with("DEFAULT", "INST/procedures/test.rb").and_return("another_user")
      expect(Script).not_to receive(:unlock)

      post :unlock, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
    end

    it "handles authorization failure" do
      post :unlock, params: {name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "set_lifecycle" do
    before(:each) do
      allow(OpenC3::Logger).to receive(:info)
    end

    it "moves a script from development to review and records the history" do
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "review", comment: "ready"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("review")
      expect(json["history"].length).to eq(1)
      expect(json["history"][0]["from"]).to eq("development")
      expect(json["history"][0]["to"]).to eq("review")
      expect(json["history"][0]["user"]).to eq("anonymous")
      expect(json["history"][0]["comment"]).to eq("ready")
      expect(json["history"][0]["time"]).to_not be_nil

      # Verify the state was persisted
      get :lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("review")
      expect(json["history"].length).to eq(1)
    end

    it "moves a script through review to approved" do
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "review", comment: "ready"}
      expect(response).to have_http_status(:ok)
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "approved", comment: "looks good"}
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["state"]).to eq("approved")
      expect(json["history"].length).to eq(2)
      expect(json["history"][1]["from"]).to eq("review")
      expect(json["history"][1]["to"]).to eq("approved")
    end

    it "rejects an invalid state" do
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "bogus", comment: ""}

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["message"]).to match(/Invalid lifecycle state: bogus/)

      # Verify nothing was stored
      get :lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}
      expect(JSON.parse(response.body)["state"]).to eq("development")
    end

    it "rejects a comment over the maximum length" do
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "review", comment: "a" * 1001}

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["message"]).to match(/1000 characters or less/)
    end

    it "rejects an invalid transition" do
      # Scripts start in development so moving to development is invalid
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "development", comment: ""}

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["message"]).to match(/Cannot move script from development to development/)
    end

    it "moves an approved script back to development" do
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "review", comment: ""}
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "approved", comment: ""}
      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "development", comment: "needs rework"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["state"]).to eq("development")
      expect(json["history"].length).to eq(3)
      expect(json["history"][2]["from"]).to eq("approved")
      expect(json["history"][2]["to"]).to eq("development")
    end

    it "handles exceptions" do
      expect(Script).to receive(:lifecycle).with("DEFAULT", "INST/procedures/test.rb").and_raise("Lifecycle failed")
      allow_any_instance_of(ScriptsController).to receive(:log_error)

      post :set_lifecycle, params: {scope: "DEFAULT", name: "INST/procedures/test.rb", state: "review", comment: ""}

      expect(response).to have_http_status(500)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Lifecycle failed")
    end

    it "handles authorization failure" do
      post :set_lifecycle, params: {name: "INST/procedures/test.rb", state: "review"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "destroy" do
    it "destroys a script" do
      expect(Script).to receive(:destroy).with("DEFAULT", "INST/procedures/test.rb")
      allow(OpenC3::Logger).to receive(:info)

      delete :destroy, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:ok)
    end

    it "handles exceptions" do
      expect(Script).to receive(:destroy).with("DEFAULT", "INST/procedures/test.rb").and_raise("Destruction failed")
      allow_any_instance_of(ScriptsController).to receive(:log_error)

      delete :destroy, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(500)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Destruction failed")
    end

    it "handles authorization failure" do
      delete :destroy, params: {name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects destroying an approved script when the lifecycle feature is enabled" do
      OpenC3::SettingModel.set({name: 'script_runner_lifecycle', data: true}, scope: 'DEFAULT')
      Script.set_lifecycle("DEFAULT", "INST/procedures/test.rb", "review", "anonymous", "")
      Script.set_lifecycle("DEFAULT", "INST/procedures/test.rb", "approved", "anonymous", "")
      expect(Script).not_to receive(:destroy)

      delete :destroy, params: {scope: "DEFAULT", name: "INST/procedures/test.rb"}

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json["message"]).to match(/approved/)
    end
  end

  describe "delete_all_breakpoints" do
    it "deletes all breakpoints" do
      # Need to mock OpenC3::Store directly
      mock_redis
      expect_any_instance_of(OpenC3::Store).to receive(:method_missing).with(:del, "DEFAULT__script-breakpoints")

      post :delete_all_breakpoints, params: {scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end

    it "handles authorization failure" do
      post :delete_all_breakpoints

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "syntax" do
    it "checks Ruby syntax successfully" do
      valid_script = "puts 'Hello World'"

      expect(Script).to receive(:syntax).with("script.rb", valid_script).and_return({
        "title" => "Syntax Check Successful",
        "description" => ["Syntax OK"]
      })

      post :syntax, params: {name: "script.rb", scope: "DEFAULT"}, body: valid_script

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["title"]).to eq("Syntax Check Successful")
    end

    it "reports Ruby syntax errors" do
      invalid_script = "puts 'Hello World"

      expect(Script).to receive(:syntax).with("script.rb", invalid_script).and_return({
        "title" => "Syntax Check Failed",
        "description" => ["2: syntax error, unexpected end-of-input"]
      })

      post :syntax, params: {name: "script.rb", scope: "DEFAULT"}, body: invalid_script

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["title"]).to eq("Syntax Check Failed")
    end

    it "handles authorization failure" do
      post :syntax, params: {name: "INST/procedures/script.rb"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "instrumented" do
    it "returns instrumented script" do
      script = "puts 'Hello World'"
      instrumented_result = {
        "title" => "Instrumented Script",
        "description" => "[\"instrumented code here\"]"
      }

      expect(Script).to receive(:instrumented).with("script.rb", script).and_return(instrumented_result)

      post :instrumented, params: {name: "script.rb", scope: "DEFAULT"}, body: script

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["title"]).to eq("Instrumented Script")
    end

    it "handles authorization failure" do
      post :instrumented, params: {name: "script.rb"}

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
