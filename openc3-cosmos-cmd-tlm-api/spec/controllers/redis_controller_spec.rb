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

RSpec.describe RedisController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
  end

  describe "#execute_raw" do
    it "rejects disallowed commands" do
      request.content_type = "text/plain"
      post :execute_raw, body: "AUTH password", params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("error")
      expect(json["message"]).to eq("The AUTH command is not allowed.")
    end

    it "executes command on main store" do
      expect(OpenC3::Store).to receive(:method_missing).with("GET", ["key"]).and_return("value")
      request.content_type = "text/plain"
      post :execute_raw, body: "GET key", params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["result"]).to eq("value")
    end

    it "executes command on ephemeral store" do
      expect(OpenC3::EphemeralStore).to receive(:method_missing).with("SET", ["key", "value"]).and_return("OK")
      request.content_type = "text/plain"
      post :execute_raw, body: "SET key value", params: {ephemeral: true, scope: "DEFAULT"}
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["result"]).to eq("OK")
    end

    it "requires admin access" do
      request.content_type = "text/plain"
      post :execute_raw, body: "GET key"
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
