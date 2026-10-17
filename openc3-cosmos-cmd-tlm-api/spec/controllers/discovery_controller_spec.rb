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
require "openc3/models/bridge_model"
require "openc3/topics/discovery_topic"

RSpec.describe DiscoveryController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:error)
    OpenC3::BridgeModel.new(name: "DEFAULT", scope: "DEFAULT", ticket: "ticket", app_public_key: "app-key").create
    OpenC3::BridgeModel.new(name: "UNPAIRED", scope: "DEFAULT", ticket: "ticket").create
  end

  describe "POST create" do
    it "requires admin and returns the discovered values" do
      expect(controller).to receive(:authorization).with("admin").and_return(true)
      expect(OpenC3::DiscoveryTopic).to receive(:discover)
        .with("DEFAULT", ["openc3/discovery/hid_discovery.py", "0x054C"], timeout: DiscoveryController::DISCOVERY_TIMEOUT_S, scope: "DEFAULT")
        .and_return([{ "value" => "abc", "text" => "DualSense (abc)" }])

      post :create, params: { scope: "DEFAULT", discovery: ["openc3/discovery/hid_discovery.py", "0x054C"] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([{ "value" => "abc", "text" => "DualSense (abc)" }])
    end

    it "rejects a missing discovery" do
      post :create, params: { scope: "DEFAULT" }, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "fails fast when the bridge is not paired" do
      expect(OpenC3::DiscoveryTopic).not_to receive(:discover)
      post :create, params: { scope: "DEFAULT", bridge: "unpaired", discovery: ["x.py"] }, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["message"]).to eq "Bridge 'UNPAIRED' is not paired with openc3-app"
      post :create, params: { scope: "DEFAULT", bridge: "missing", discovery: ["x.py"] }, as: :json
      expect(response).to have_http_status(:service_unavailable)
    end

    it "returns discovery errors" do
      allow(OpenC3::DiscoveryTopic).to receive(:discover).and_raise("Timeout of 15s waiting for discovery")
      post :create, params: { scope: "DEFAULT", discovery: ["x.py"] }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq "Timeout of 15s waiting for discovery"
    end
  end
end
