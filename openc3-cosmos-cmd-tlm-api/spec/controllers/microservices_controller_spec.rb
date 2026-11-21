# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

require "rails_helper"
require "openc3/models/microservice_model"

RSpec.describe MicroservicesController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
    controller.instance_variable_set(:@model_class, OpenC3::MicroserviceModel)

    @micro1 = {
      "name" => "DEFAULT__MICROSERVICE__MICRO1",
      "prefix" => "PREFIX",
      "ports" => [[8080, "TCP"]]
    }

    microservice_model = OpenC3::MicroserviceModel.from_json(@micro1.to_json, scope: "DEFAULT")
    microservice_model.create
  end

  describe "POST start" do
    it "starts a microservice" do
      microservice_instance = instance_double(OpenC3::MicroserviceModel)
      allow(OpenC3::MicroserviceModel).to receive(:get_model)
        .with(name: "MICRO1", scope: "DEFAULT")
        .and_return(microservice_instance)

      expect(microservice_instance).to receive(:enabled=).with(true)
      expect(microservice_instance).to receive(:update)

      post :start, params: {id: "MICRO1", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end

    it "handles nonexistent microservice" do
      post :start, params: {id: "NONEXISTENT", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end

    it "returns nothing without authorization" do
      post :start, params: {id: "MICRO1"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST stop" do
    it "stops a microservice" do
      microservice_instance = instance_double(OpenC3::MicroserviceModel)
      allow(OpenC3::MicroserviceModel).to receive(:get_model)
        .with(name: "MICRO1", scope: "DEFAULT")
        .and_return(microservice_instance)

      expect(microservice_instance).to receive(:enabled=).with(false)
      expect(microservice_instance).to receive(:update)

      post :stop, params: {id: "MICRO1", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end

    it "handles nonexistent microservice" do
      post :stop, params: {id: "NONEXISTENT", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end

    it "returns nothing without authorization" do
      post :stop, params: {id: "MICRO1"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET traefik" do
    it "generates traefik configuration" do
      get :traefik

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)

      expect(result).to have_key("http")
      expect(result["http"]).to have_key("routers")
      expect(result["http"]).to have_key("services")
      expect(result["http"]["routers"]).to have_key("DEFAULT__MICROSERVICE__MICRO1")
      router = result["http"]["routers"]["DEFAULT__MICROSERVICE__MICRO1"]
      # Anchored so /PREFIX doesn't also capture /PREFIXother
      expect(router["rule"]).to eq("Path(`/PREFIX`) || PathPrefix(`/PREFIX/`)")
      expect(router["service"]).to eq("DEFAULT__MICROSERVICE__MICRO1")
      # Below the api (8), tools (4-6) and other built in routers
      expect(router["priority"]).to eq(3)
    end

    it "returns an empty object when there are no routes" do
      OpenC3::MicroserviceModel.new(name: "DEFAULT__MICROSERVICE__MICRO1", scope: "DEFAULT").destroy

      get :traefik

      expect(response).to have_http_status(:ok)
      # Traefik rejects {"http":{"routers":{},"services":{}}} and keeps the old
      # routes live, so the last route being deleted must produce {}
      expect(JSON.parse(response.body)).to eq({})
    end

    it "is not served through traefik" do
      request.headers["X-Forwarded-For"] = "127.0.0.1"
      get :traefik
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end

    it "skips stored routes with invalid prefixes or names" do
      # Write directly to the store to simulate microservices saved before
      # prefixes were validated
      store = OpenC3::MicroserviceModel.store
      {
        "DEFAULT__USER__FILES" => "files/myapi",
        "DEFAULT__USER__API" => "/openc3-api",
        "DEFAULT__USER__ROOT" => "/",
        "DEFAULT__USER__BACKTICK" => "/my`api",
        "DEFAULT__USER__BAD@NAME" => "/badname",
      }.each do |name, prefix|
        store.hset(OpenC3::MicroserviceModel::PRIMARY_KEY, name, JSON.generate({ "name" => name, "prefix" => prefix, "ports" => [[7791, "TCP"]] }))
      end
      allow(controller.logger).to receive(:warn)

      get :traefik

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      expect(result["http"]["routers"].keys).to eq(["DEFAULT__MICROSERVICE__MICRO1"])
      expect(result["http"]["services"].keys).to eq(["DEFAULT__MICROSERVICE__MICRO1"])
      expect(controller.logger).to have_received(:warn).exactly(5).times
    end

    it "rejects creating a microservice with a reserved prefix" do
      json = { "name" => "DEFAULT__USER__FILES_API", "prefix" => "files/myapi", "ports" => [[7791, "http"]] }.to_json
      post :create, params: { scope: "DEFAULT", json: json }
      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to match(/is reserved by COSMOS/)
      expect(OpenC3::MicroserviceModel.get(name: "DEFAULT__USER__FILES_API")).to be_nil
    end

    it "uses base operator hostname for shard 0" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENC3_OPERATOR_HOSTNAME").and_return("openc3-operator")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENC3_OPERATOR_HOSTNAME").and_return("openc3-operator")

      get :traefik

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      url = result["http"]["services"]["DEFAULT__MICROSERVICE__MICRO1"]["loadBalancer"]["servers"][0]["url"]
      expect(url).to eq("http://openc3-operator:8080")
    end

    it "appends shard number to operator hostname for non-zero shards" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENC3_OPERATOR_HOSTNAME").and_return("openc3-operator")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("OPENC3_OPERATOR_HOSTNAME").and_return("openc3-operator")

      # Create a microservice with shard 1
      micro2 = {
        "name" => "DEFAULT__MICROSERVICE__MICRO2",
        "prefix" => "PREFIX2",
        "ports" => [[8081, "TCP"]],
        "shard" => 1
      }
      microservice_model = OpenC3::MicroserviceModel.from_json(micro2.to_json, scope: "DEFAULT")
      microservice_model.create

      get :traefik

      expect(response).to have_http_status(:ok)
      result = JSON.parse(response.body)
      url = result["http"]["services"]["DEFAULT__MICROSERVICE__MICRO2"]["loadBalancer"]["servers"][0]["url"]
      expect(url).to eq("http://openc3-operator-1:8081")
    end
  end
end
