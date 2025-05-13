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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "rails_helper"
require "openc3/models/trigger_model"
require "openc3/models/trigger_group_model"

RSpec.describe ReactionController, type: :controller do
  GROUP = "DEFAULT".freeze

  before(:each) do
    mock_redis
    model = OpenC3::TriggerGroupModel.new(name: GROUP, scope: "DEFAULT")
    model.create
    model = OpenC3::TriggerGroupModel.new(name: "TEST", scope: "TEST")
    model.create
  end

  def generate_trigger(
    scope: "DEFAULT",
    name: "TRIG1",
    group: GROUP,
    left: {
      "type" => "item",
      "target" => "INST",
      "packet" => "ADCS",
      "item" => "POSX",
      "valueType" => "RAW"
    },
    operator: ">",
    right: {
      "type" => "float",
      "float" => 10.0
    }
  )
    OpenC3::TriggerModel.new(
      name: name,
      scope: scope,
      group: group,
      left: left,
      operator: operator,
      right: right
    ).create
  end

  def generate_reaction_hash(
    description: "another test",
    triggers: [{name: "TRIG1", group: GROUP}],
    actions: [{"type" => "command", "value" => "INST ABORT"}]
  )
    {
      "snooze" => 300,
      "triggers" => triggers,
      "trigger_level" => "EDGE",
      "actions" => actions
    }
  end

  describe "GET index" do
    it "returns an empty array and status code 200" do
      get :index, params: {"scope" => "DEFAULT"}
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json).to eql([])
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST then GET index with Triggers" do
    it "returns an array and status code 200" do
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      expect(response).to have_http_status(:created)
      trigger = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(trigger["name"]).not_to be_nil
      get :show, params: {scope: "DEFAULT", name: trigger["name"]}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      get :index, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json.empty?).to eql(false)
      expect(json.length).to eql(1)
      expect(json[0]["name"]).to eql(trigger["name"])
    end
  end

  describe "Error handling for GET index" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 500 status code for StandardError" do
      allow(OpenC3::ReactionModel).to receive(:all).and_raise(StandardError.new("Database error"))

      get :index, params: {scope: "DEFAULT"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Database error")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end
  end

  describe "Error handling for GET show" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 404 status code for ReactionInputError" do
      allow(OpenC3::ReactionModel).to receive(:get).and_raise(OpenC3::ReactionInputError.new("Reaction not found"))

      get :show, params: {scope: "DEFAULT", name: "nonexistent_reaction"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Reaction not found")
      expect(json["type"]).to include("ReactionInputError")
      expect(response).to have_http_status(404)
    end

    it "returns a 400 status code for ReactionError" do
      allow(OpenC3::ReactionModel).to receive(:get).and_raise(OpenC3::ReactionError.new("Bad reaction format"))

      get :show, params: {scope: "DEFAULT", name: "bad_format_reaction"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Bad reaction format")
      expect(json["type"]).to include("ReactionError")
      expect(response).to have_http_status(400)
    end

    it "returns a 500 status code for StandardError" do
      allow(OpenC3::ReactionModel).to receive(:get).and_raise(StandardError.new("Unexpected error"))

      get :show, params: {scope: "DEFAULT", name: "error_reaction"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Unexpected error")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end
  end

  describe "POST two reactions on different scopes then GET index" do
    it "returns an array of one and status code 200" do
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      expect(response).to have_http_status(:created)
      default_json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      generate_trigger(scope: "TEST", group: "TEST")
      hash["triggers"][0][:group] = "TEST"
      post :create, params: hash.merge({scope: "TEST"})
      expect(response).to have_http_status(:created)
      test_json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(default_json["name"]).to eql(test_json["name"])
      # check the value on the index
      get :index, params: {"scope" => "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json.empty?).to eql(false)
      expect(json.length).to eql(1)
      expect(json[0]["name"]).to eql(default_json["name"])
    end
  end

  describe "Error handling for POST create" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 400 status code for ReactionInputError" do
      hash = generate_reaction_hash
      hash["triggers"][0]["name"] = "BAD"
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).not_to be_nil
      expect(json["type"]).to include("ReactionInputError")
      expect(response).to have_http_status(400)
    end

    it "returns a 418 status code for ReactionError" do
      allow_any_instance_of(OpenC3::ReactionModel).to receive(:create).and_raise(OpenC3::ReactionError.new("Test reaction error"))
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Test reaction error")
      expect(json["type"]).to include("ReactionError")
      expect(response).to have_http_status(418)
    end

    it "returns a 500 status code for StandardError" do
      allow_any_instance_of(OpenC3::ReactionModel).to receive(:create).and_raise(StandardError.new("Test standard error"))
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Test standard error")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end
  end

  describe "Error handling for PUT update" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 404 status code if reaction not found" do
      put :update, params: {
        scope: "DEFAULT",
        name: "nonexistent",
        snooze: 300,
        triggers: [],
        trigger_level: "EDGE",
        actions: []
      }

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
      expect(response).to have_http_status(404)
    end

    it "returns a 400 status code for ReactionInputError" do
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      reaction_name = json["name"]

      model = instance_double(OpenC3::ReactionModel)
      allow(model).to receive(:as_json).and_return({})
      allow(model).to receive(:snooze=)
      allow(model).to receive(:triggers=).and_raise(OpenC3::ReactionInputError.new("Invalid trigger format"))
      allow(model).to receive(:trigger_level=)
      allow(model).to receive(:actions=)
      allow(OpenC3::ReactionModel).to receive(:get).and_return(model)

      put :update, params: {
        scope: "DEFAULT",
        name: reaction_name,
        snooze: 300,
        triggers: [{"name" => "INVALID"}],
        trigger_level: "EDGE",
        actions: []
      }

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Invalid trigger format")
      expect(json["type"]).to include("ReactionInputError")
      expect(response).to have_http_status(400)
    end

    it "returns a 418 status code for ReactionError" do
      # Create a reaction first
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      reaction_name = json["name"]

      # Mock error on update
      model = instance_double(OpenC3::ReactionModel)
      allow(model).to receive(:as_json).and_return({})
      allow(model).to receive(:snooze=)
      allow(model).to receive(:triggers=)
      allow(model).to receive(:trigger_level=)
      allow(model).to receive(:actions=)
      allow(model).to receive(:notify).and_raise(OpenC3::ReactionError.new("Failed to notify"))
      allow(OpenC3::ReactionModel).to receive(:get).and_return(model)

      put :update, params: {
        scope: "DEFAULT",
        name: reaction_name,
        snooze: 300,
        triggers: [{"name" => "TRIG1", "group" => "DEFAULT"}],
        trigger_level: "EDGE",
        actions: []
      }

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Failed to notify")
      expect(json["type"]).to include("ReactionError")
      expect(response).to have_http_status(418)
    end

    it "returns a 500 status code for StandardError" do
      # Create a reaction first
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      reaction_name = json["name"]

      # Mock error on update
      allow(OpenC3::ReactionModel).to receive(:get).and_raise(StandardError.new("Database failure"))

      put :update, params: {
        scope: "DEFAULT",
        name: reaction_name,
        snooze: 300,
        triggers: [{"name" => "TRIG1", "group" => "DEFAULT"}],
        trigger_level: "EDGE",
        actions: []
      }

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Database failure")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end
  end

  describe "Error handling for POST enable" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 404 status code if reaction not found" do
      post :enable, params: {scope: "DEFAULT", name: "nonexistent"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
      expect(response).to have_http_status(404)
    end

    it "returns a 500 status code for StandardError" do
      # Create a reaction first
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      reaction_name = json["name"]

      # Mock error on enable
      model = instance_double(OpenC3::ReactionModel)
      allow(model).to receive(:as_json).and_return({})
      allow(model).to receive(:notify_enable).and_raise(StandardError.new("Notification failed"))
      allow(OpenC3::ReactionModel).to receive(:get).and_return(model)

      post :enable, params: {scope: "DEFAULT", name: reaction_name}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Notification failed")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end
  end

  describe "Error handling for POST disable" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 404 status code if reaction not found" do
      post :disable, params: {scope: "DEFAULT", name: "nonexistent"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
      expect(response).to have_http_status(404)
    end

    it "returns a 500 status code for StandardError" do
      # Create a reaction first
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      reaction_name = json["name"]

      # Mock error on disable
      model = instance_double(OpenC3::ReactionModel)
      allow(model).to receive(:as_json).and_return({})
      allow(model).to receive(:notify_disable).and_raise(StandardError.new("Notification failed"))
      allow(OpenC3::ReactionModel).to receive(:get).and_return(model)

      post :disable, params: {scope: "DEFAULT", name: reaction_name}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Notification failed")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end
  end

  describe "Error handling for POST execute" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 404 status code if reaction not found" do
      post :execute, params: {scope: "DEFAULT", name: "nonexistent"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("not found")
      expect(response).to have_http_status(404)
    end

    it "returns a 500 status code for StandardError" do
      # Create a reaction first
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      reaction_name = json["name"]

      # Mock error on execute
      model = instance_double(OpenC3::ReactionModel)
      allow(model).to receive(:as_json).and_return({})
      allow(model).to receive(:notify_execute).and_raise(StandardError.new("Execution failed"))
      allow(OpenC3::ReactionModel).to receive(:get).and_return(model)

      post :execute, params: {scope: "DEFAULT", name: reaction_name}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Execution failed")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end
  end

  describe "Error handling for DELETE destroy" do
    before(:each) do
      allow(controller).to receive(:log_error)
    end

    it "returns a 404 status code if reaction not found" do
      delete :destroy, params: {"scope" => "DEFAULT", "name" => "test"}

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).not_to be_nil
    end

    it "returns a 404 status code for ReactionInputError" do
      allow(OpenC3::ReactionModel).to receive(:get).and_raise(OpenC3::ReactionInputError.new("Invalid reaction name"))

      delete :destroy, params: {scope: "DEFAULT", name: "invalid$reaction"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Invalid reaction name")
      expect(json["type"]).to include("ReactionInputError")
      expect(response).to have_http_status(404)
    end

    it "returns a 400 status code for ReactionError" do
      allow(OpenC3::ReactionModel).to receive(:get).and_raise(OpenC3::ReactionError.new("Cannot delete active reaction"))

      delete :destroy, params: {scope: "DEFAULT", name: "active_reaction"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Cannot delete active reaction")
      expect(json["type"]).to include("ReactionError")
      expect(response).to have_http_status(400)
    end

    it "returns a 500 status code for StandardError" do
      allow(OpenC3::ReactionModel).to receive(:get).and_raise(StandardError.new("Database failure"))

      delete :destroy, params: {scope: "DEFAULT", name: "problem_reaction"}

      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["status"]).to eql("error")
      expect(json["message"]).to eql("Database failure")
      expect(json["type"]).to include("StandardError")
      expect(json).to have_key("backtrace")
      expect(response).to have_http_status(500)
    end

    it "returns a json hash of name and status code 200 if found" do
      generate_trigger
      hash = generate_reaction_hash
      post :create, params: hash.merge({"scope" => "DEFAULT"})
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      delete :destroy, params: {"scope" => "DEFAULT", "name" => json["name"]}
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json["name"]).to eql("REACT1")
    end
  end
end
