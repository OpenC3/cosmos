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
require "openc3/models/process_status_model"

RSpec.describe ProcessStatusController, type: :controller do
  before(:each) do
    mock_redis
    controller.instance_variable_set(:@model_class, OpenC3::ProcessStatusModel)

    tcp_server = OpenC3::ProcessStatusModel.new(
      name: "INST__INTERFACE__TCP_SERVER",
      state: "RUNNING",
      process_type: "INTERFACE",
      scope: "DEFAULT"
    )
    tcp_server.create

    decom = OpenC3::ProcessStatusModel.new(
      name: "DEFAULT__DECOM__DECOM1",
      state: "STOPPED",
      process_type: "DECOM",
      scope: "DEFAULT"
    )
    decom.create

    tcp_client = OpenC3::ProcessStatusModel.new(
      name: "INST__INTERFACE__TCP_CLIENT",
      state: "RUNNING",
      process_type: "INTERFACE",
      scope: "DEFAULT"
    )
    tcp_client.create
  end

  describe "GET show" do
    it "returns all process statuses when id is 'all'" do
      get :show, params: {id: "all", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(3)
    end

    it "returns a specific process status when id contains '__'" do
      get :show, params: {id: "INST__INTERFACE__TCP_SERVER", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["name"]).to eq("INST__INTERFACE__TCP_SERVER")
      expect(json["state"]).to eq("RUNNING")
    end

    it "filters processes by process_type" do
      get :show, params: {id: "INTERFACE", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
      expect(json).to have_key("INST__INTERFACE__TCP_CLIENT")
      expect(json).to have_key("INST__INTERFACE__TCP_SERVER")
    end

    it "returns unauthorized if not authorized" do
      get :show, params: {id: "all"}
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
