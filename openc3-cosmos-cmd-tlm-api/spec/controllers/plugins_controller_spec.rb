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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "rails_helper"
require "tempfile"

RSpec.describe PluginsController, type: :controller do
  before(:each) do
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
  end

  describe "GET index" do
    it "returns list of installed plugins" do
      allow(OpenC3::PluginModel).to receive(:names).and_return(["PLUGIN1", "PLUGIN2"])

      get :index, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq(["PLUGIN1", "PLUGIN2"])
    end

    it "returns nothing without authorization" do
      get :index
      expect(response).to have_http_status(:unauthorized)
    end

    it "handles errors during index" do
      allow(OpenC3::PluginModel).to receive(:names).and_raise(StandardError.new("Database error"))

      get :index, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Database error")
    end
  end

  describe "GET show" do
    it "returns a specific plugin" do
      plugin_data = {"name" => "TEST_PLUGIN", "version" => "1.0.0"}
      allow(OpenC3::PluginModel).to receive(:get).and_return(plugin_data)

      get :show, params: {id: "TEST_PLUGIN", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq(plugin_data)
    end

    it "returns all plugins when id is 'all'" do
      plugins_data = {
        "PLUGIN1" => {"name" => "PLUGIN1"},
        "PLUGIN2" => {"name" => "PLUGIN2"}
      }
      allow(OpenC3::PluginModel).to receive(:all).and_return(plugins_data)
      allow(OpenC3::PluginStoreModel).to receive(:all).and_return([].to_json)

      get :show, params: {id: "all", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq(plugins_data)
    end

    it "returns nothing without authorization" do
      get :show, params: {id: "TEST_PLUGIN"}
      expect(response).to have_http_status(:unauthorized)
    end

    it "handles errors during show" do
      allow(OpenC3::PluginModel).to receive(:get).and_raise(StandardError.new("Plugin not found"))

      get :show, params: {id: "TEST_PLUGIN", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Plugin not found")
    end
  end

  describe "POST create" do
    before(:each) do
      @file = Tempfile.new(["test-plugin", ".gem"])
      @file.write("gem content")
      @file.rewind

      @upload_file = fixture_file_upload(@file.path, "application/octet-stream")
      allow(@upload_file).to receive(:original_filename).and_return("test-plugin.gem")

      allow(Dir).to receive(:mktmpdir).and_return("/tmp/test")
      allow(FileUtils).to receive(:cp)
      allow(FileUtils).to receive(:remove_entry_secure)
    end

    it "creates a new plugin successfully" do
      install_result = {
        "name" => "TEST_PLUGIN",
        "variables" => {},
        "plugin_txt_lines" => []
      }
      allow(OpenC3::PluginModel).to receive(:install_phase1).and_return(install_result)

      post :create, params: {plugin: @upload_file, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq(install_result)
    end

    it "handles plugin creation with existing variables" do
      existing_model = {
        "variables" => {"VAR1" => "value1"},
        "plugin_txt_lines" => ["line1", "line2"]
      }
      allow(OpenC3::PluginModel).to receive(:get).and_return(existing_model)

      install_result = {
        "name" => "TEST_PLUGIN",
        "variables" => {"VAR1" => "value1"},
        "plugin_txt_lines" => ["line1", "line2"]
      }

      expect(OpenC3::PluginModel).to receive(:install_phase1).with(
        "/tmp/test/test-plugin.gem",
        existing_variables: {"VAR1" => "value1"},
        existing_plugin_txt_lines: ["line1", "line2"],
        store_id: nil,
        scope: "DEFAULT"
      ).and_return(install_result)

      put :update, params: {id: "TEST_PLUGIN", plugin: @upload_file, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq(install_result)
    end

    it "returns error when no file is provided" do
      post :create, params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("No file received")
    end

    it "handles errors during plugin installation" do
      allow(OpenC3::PluginModel).to receive(:install_phase1).and_raise(StandardError.new("Installation failed"))

      post :create, params: {plugin: @upload_file, scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Installation failed")
    end

    it "cleans up temporary directory on success" do
      allow(OpenC3::PluginModel).to receive(:install_phase1).and_return({})
      expect(FileUtils).to receive(:remove_entry_secure).with("/tmp/test", true)

      post :create, params: {plugin: @upload_file, scope: "DEFAULT"}
    end

    it "cleans up temporary directory on error" do
      allow(OpenC3::PluginModel).to receive(:install_phase1).and_raise(StandardError.new("Installation failed"))
      expect(FileUtils).to receive(:remove_entry_secure).with("/tmp/test", true)

      post :create, params: {plugin: @upload_file, scope: "DEFAULT"}
    end

    it "returns nothing without authorization" do
      post :create, params: {plugin: @upload_file}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT update" do
    before(:each) do
      @file = Tempfile.new(["test-plugin", ".gem"])
      @file.write("gem content")
      @file.rewind

      @upload_file = fixture_file_upload(@file.path, "application/octet-stream")
      allow(@upload_file).to receive(:original_filename).and_return("test-plugin.gem")

      allow(Dir).to receive(:mktmpdir).and_return("/tmp/test")
      allow(FileUtils).to receive(:cp)
      allow(FileUtils).to receive(:remove_entry_secure)
    end

    it "updates an existing plugin" do
      existing_plugin = {
        "name" => "TEST_PLUGIN",
        "variables" => {"VAR1" => "existing_value"},
        "plugin_txt_lines" => ["existing_line"]
      }
      allow(OpenC3::PluginModel).to receive(:get).and_return(existing_plugin)

      install_result = {
        "name" => "TEST_PLUGIN",
        "variables" => {"VAR1" => "existing_value"},
        "plugin_txt_lines" => ["existing_line"]
      }

      expect(OpenC3::PluginModel).to receive(:install_phase1).with(
        "/tmp/test/test-plugin.gem",
        existing_variables: {"VAR1" => "existing_value"},
        existing_plugin_txt_lines: ["existing_line"],
        store_id: nil,
        scope: "DEFAULT"
      ).and_return(install_result)

      put :update, params: {id: "TEST_PLUGIN", plugin: @upload_file, scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to eq(install_result)
    end

    it "returns nothing without authorization" do
      put :update, params: {id: "TEST_PLUGIN", plugin: @upload_file}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST install" do
    before(:each) do
      allow(Dir).to receive(:mktmpdir).and_return("/tmp/test")
      allow(Dir::Tmpname).to receive(:create).and_return("plugin-instance-123.json")
      allow(File).to receive(:open).and_yield(double("file", write: true))
    end

    it "installs a plugin with hash parameters" do
      plugin_hash = '{"variables": {"VAR1": "value1"}}'
      process_result = double("ProcessInfo", name: "process_123")

      allow(OpenC3::ProcessManager.instance).to receive(:spawn).and_return(process_result)

      post :install, params: {
        id: "TEST_PLUGIN__1.0.0__plugin",
        plugin_hash: plugin_hash,
        scope: "DEFAULT"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("process_123")
    end

    it "extracts gem name from plugin id correctly" do
      plugin_hash = '{"variables": {}}'
      process_result = double("ProcessInfo", name: "process_123")

      expect(OpenC3::ProcessManager.instance).to receive(:spawn).with(
        ["ruby", "/openc3/bin/openc3cli", "load", "TEST_PLUGIN", "DEFAULT", anything, "force"],
        "plugin_install",
        "TEST_PLUGIN__1.0.0__plugin",
        anything,
        hash_including(temp_dir: "/tmp/test", scope: "DEFAULT")
      ).and_return(process_result)

      post :install, params: {
        id: "TEST_PLUGIN__1.0.0__plugin",
        plugin_hash: plugin_hash,
        scope: "DEFAULT"
      }
    end

    it "handles errors during installation" do
      plugin_hash = '{"variables": {}}'
      allow(OpenC3::ProcessManager.instance).to receive(:spawn).and_raise(StandardError.new("Spawn failed"))

      post :install, params: {
        id: "TEST_PLUGIN__1.0.0__plugin",
        plugin_hash: plugin_hash,
        scope: "DEFAULT"
      }

      expect(response).to have_http_status(:internal_server_error)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Spawn failed")
    end

    it "returns nothing without authorization" do
      post :install, params: {id: "TEST_PLUGIN", plugin_hash: "{}"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE destroy" do
    it "uninstalls a plugin successfully" do
      process_result = double("ProcessInfo", name: "process_123")

      expect(OpenC3::ProcessManager.instance).to receive(:spawn).with(
        ["ruby", "/openc3/bin/openc3cli", "unload", "TEST_PLUGIN", "DEFAULT"],
        "plugin_uninstall",
        "TEST_PLUGIN",
        anything,
        hash_including(scope: "DEFAULT")
      ).and_return(process_result)

      delete :destroy, params: {id: "TEST_PLUGIN", scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("process_123")
    end

    it "handles errors during uninstallation" do
      allow(OpenC3::ProcessManager.instance).to receive(:spawn).and_raise(StandardError.new("Uninstall failed"))

      delete :destroy, params: {id: "TEST_PLUGIN", scope: "DEFAULT"}
      expect(response).to have_http_status(:internal_server_error)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("Uninstall failed")
    end

    it "returns nothing without authorization" do
      delete :destroy, params: {id: "TEST_PLUGIN"}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
