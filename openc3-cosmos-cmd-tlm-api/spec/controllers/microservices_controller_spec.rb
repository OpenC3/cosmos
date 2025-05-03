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
      "ports" => [8080]
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
    end
  end
end
