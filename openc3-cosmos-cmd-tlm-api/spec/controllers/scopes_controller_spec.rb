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
require "openc3/models/scope_model"
require "openc3/utilities/process_manager"

RSpec.describe ScopesController, type: :controller do
  before(:each) do
    mock_redis

    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
    allow(controller).to receive(:log_error)

    controller.instance_variable_set(:@model_class, OpenC3::ScopeModel)

    @scope1_json = JSON.generate({
      "name" => "SCOPE1"
    })

    @scope2_json = JSON.generate({
      "name" => "SCOPE2",
      "critical_commanding" => "ALL"
    })

    scope1_model = OpenC3::ScopeModel.from_json(@scope1_json, scope: "DEFAULT")
    scope1_model.create

    scope2_model = OpenC3::ScopeModel.from_json(@scope2_json, scope: "DEFAULT")
    scope2_model.create
  end

  describe "GET index" do
    it "returns a list of scope names" do
      get :index

      expect(response).to have_http_status(:ok)
      scope_names = JSON.parse(response.body)
      expect(scope_names).to match_array(["SCOPE1", "SCOPE2"])
    end
  end

  describe "POST create" do
    it "creates a new scope" do
      expect_any_instance_of(OpenC3::ScopeModel).to receive(:deploy)
      new_scope = JSON.generate({
        "name" => "DEFAULT"
      })
      post :create, params: {json: new_scope, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)

      get :index
      expect(response).to have_http_status(:ok)
      scope_names = JSON.parse(response.body)
      expect(scope_names).to match_array(["DEFAULT", "SCOPE1", "SCOPE2"])
    end

    it "validates scope name format" do
      invalid_scope_json = JSON.generate({
        "name" => "INVALID:SCOPE" # : is not allowed in scope names
      })

      post :create, params: {json: invalid_scope_json, scope: "DEFAULT"}

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to include("Invalid scope name")
    end

    it "returns unauthorized without authorization" do
      post :create, params: {json: @scope1_json}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT update" do
    it "updates an existing scope" do
      updated_scope_json = JSON.generate({
        "name" => "SCOPE1",
        "critical_commanding" => "NORMAL"
      })

      put :update, params: {id: "SCOPE1", scope: "DEFAULT", json: updated_scope_json}
      expect(response).to have_http_status(:ok)

      get :show, params: {id: "SCOPE1", scope: "DEFAULT"}
      expect(JSON.parse(response.body)["critical_commanding"]).to eq("NORMAL")
    end

    it "returns unauthorized without authorization" do
      put :update, params: {id: "SCOPE1"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE destroy" do
    it "destroys a scope using ProcessManager" do
      process_manager = instance_double(OpenC3::ProcessManager)
      allow(OpenC3::ProcessManager).to receive(:instance).and_return(process_manager)

      process_result = {"state" => "SPAWNED", "process_id" => 12345}
      expected_cmd = ["ruby", "/openc3/bin/openc3cli", "destroyscope", "SCOPE1"]
      expect(process_manager).to receive(:spawn).with(
        expected_cmd,
        "scope_uninstall",
        "SCOPE1",
        an_instance_of(Time),
        scope: "DEFAULT"
      ).and_return(process_result)

      delete :destroy, params: {id: "SCOPE1", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("state" => "SPAWNED")
    end

    it "returns nothing without superadmin authorization" do
      delete :destroy, params: {id: "SCOPE1"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "handles errors in ProcessManager" do
      process_manager = instance_double(OpenC3::ProcessManager)
      allow(OpenC3::ProcessManager).to receive(:instance).and_return(process_manager)

      allow(process_manager).to receive(:spawn).and_raise(StandardError.new("Failed to destroy scope"))

      delete :destroy, params: {id: "SCOPE1", scope: "DEFAULT"}

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("Failed to destroy scope")
    end
  end
end
