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
require "openc3/models/tool_model"

RSpec.describe ToolsController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
    allow(controller).to receive(:authorization).and_return(true)
    controller.instance_variable_set(:@model_class, OpenC3::ToolModel)

    # Create tools using model methods
    @tool1 = {
      "name" => "tool1",
      "folder_name" => "tool1",
      "icon" => "tool1.png",
      "url" => "/tools/tool1",
      "position" => 0,
      "window" => "SAME"
    }

    @tool2 = {
      "name" => "tool2",
      "folder_name" => "tool2",
      "icon" => "tool2.png",
      "url" => "/tools/tool2",
      "position" => 1,
      "window" => "INLINE",
      "inline_url" => "index.js",
      "import_map_items" => {
        "item1" => "path1",
        "item2" => "path2"
      }
    }

    # Create tools using the model methods
    tool1_model = OpenC3::ToolModel.from_json(@tool1.to_json, scope: "DEFAULT")
    tool1_model.create

    tool2_model = OpenC3::ToolModel.from_json(@tool2.to_json, scope: "DEFAULT")
    tool2_model.create
  end

  describe "GET show" do
    it "returns all tools" do
      get :show, params: {id: "all", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      tools = JSON.parse(response.body)
      expect(tools.size).to eq(2)
    end

    it "returns the requested tool" do
      get :show, params: {id: "tool1", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      tool = JSON.parse(response.body)
      expect(tool["name"]).to eq("tool1")
      expect(tool["folder_name"]).to eq("tool1")
      expect(tool["window"]).to eq("SAME")
    end
  end

  describe "PUT position" do
    it "sets the tool position" do
      # Mock the set_position method to avoid issues with string/integer comparison
      expect(OpenC3::ToolModel).to receive(:set_position).with(
        name: "tool1",
        position: "2",
        scope: "DEFAULT"
      )

      put :position, params: {id: "tool1", position: "2", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET importmap" do
    it "returns import map with all tools" do
      # Make sure the controller has access to the tools with import_map_items
      allow(OpenC3::ToolModel).to receive(:all_scopes).and_return({
        "DEFAULT__tool2" => @tool2
      })

      get :importmap

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)

      expect(result["imports"]).to include("item1" => "path1", "item2" => "path2")
      expect(result["imports"]).to include("@openc3/tool-tool2" => "/tools/tool2/index.js")
    end

    it "handles tools with no import_map_items" do
      get :importmap

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result["imports"]).to eq({})
    end
  end

  describe "GET auth" do
    before(:each) do
      ENV["OPENC3_KEYCLOAK_REALM"] = nil
      ENV["OPENC3_KEYCLOAK_URL"] = nil
      ENV["OPENC3_KEYCLOAK_EXTERNAL_URL"] = nil
      ENV["OPENC3_API_CLIENT"] = "client"
    end

    it "returns default auth settings when default Keycloak URL" do
      ENV["OPENC3_KEYCLOAK_URL"] = "http://openc3-keycloak:8080"

      get :auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('var openc3_keycloak_url = "/auth"')
      expect(response.body).to include('var openc3_keycloak_realm = "openc3"')
      expect(response.body).to include('var openc3_keycloak_client_id = "client"')
    end

    it "uses OPENC3_KEYCLOAK_EXTERNAL_URL when set" do
      ENV["OPENC3_KEYCLOAK_EXTERNAL_URL"] = "https://auth.example.com"

      get :auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('var openc3_keycloak_url = "https://auth.example.com"')
    end

    it "uses custom realm when OPENC3_KEYCLOAK_REALM is set" do
      ENV["OPENC3_KEYCLOAK_URL"] = "http://openc3-keycloak:8080"
      ENV["OPENC3_KEYCLOAK_REALM"] = "custom"

      get :auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('var openc3_keycloak_realm = "custom"')
    end

    it "uses OPENC3_KEYCLOAK_URL when set and not default" do
      ENV["OPENC3_KEYCLOAK_URL"] = "https://custom-keycloak:8080"

      get :auth

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('var openc3_keycloak_url = "https://custom-keycloak:8080"')
    end
  end
end
