# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.

require "rails_helper"
require "openc3/models/bridge_model"
require "openc3/models/microservice_model"

RSpec.describe BridgesController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
    allow(OpenC3::Bucket).to receive(:getClient).and_return(double("bucket", list_objects: []))

    OpenC3::BridgeModel.build_microservice(bridge_name: "READY", scope: "DEFAULT").create
    OpenC3::BridgeModel.build_microservice(bridge_name: "PENDING", scope: "DEFAULT").create
    OpenC3::MicroserviceModel.new(name: "DEFAULT__USER__OTHER", scope: "DEFAULT").create
    OpenC3::BridgeModel.new(
      name: "READY",
      scope: "DEFAULT",
      public_key: "hub-public-key",
      ticket: "secret-ticket",
      app_public_key: "app-public-key",
      enroll_code: "secret-code",
      enroll_code_generated_at: Time.now.to_i,
    ).create
    OpenC3::BridgeModel.new(name: "ORPHAN", scope: "DEFAULT", ticket: "orphan-ticket").create
  end

  describe "GET show" do
    it "requires admin authorization and returns only safe bridge summaries" do
      expect(controller).to receive(:authorization).with("admin").and_return(true)

      get :show, params: { id: "all", scope: "DEFAULT" }

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result).to eq(
        "READY" => {
          "name" => "READY",
          "app_public_key" => "app-public-key",
          "reachable" => true,
        },
        "PENDING" => {
          "name" => "PENDING",
          "app_public_key" => nil,
          "reachable" => false,
        },
      )
      expect(response.body).not_to include("secret-ticket", "secret-code", "hub-public-key")
    end

    it "returns a safe summary for one bridge" do
      get :show, params: { id: "ready", scope: "DEFAULT" }

      expect(JSON.parse(response.body)).to eq(
        "name" => "READY",
        "app_public_key" => "app-public-key",
        "reachable" => true,
      )
    end
  end

  describe "GET index" do
    it "requires admin authorization and includes bridges whose hubs have not started" do
      expect(controller).to receive(:authorization).with("admin").and_return(true)

      get :index, params: { scope: "DEFAULT" }

      expect(JSON.parse(response.body)).to contain_exactly("READY", "PENDING")
    end
  end

  describe "DELETE destroy" do
    it "deletes a pending bridge that has no BridgeModel record" do
      secret_client = double("secrets", delete: nil)
      allow(OpenC3::Secrets).to receive(:getClient).and_return(secret_client)

      delete :destroy, params: { id: "PENDING", scope: "DEFAULT" }

      expect(response).to have_http_status(:ok)
      expect(
        OpenC3::MicroserviceModel.get_model(name: "DEFAULT__BRIDGE__PENDING", scope: "DEFAULT")
      ).to be_nil
    end
  end
end
