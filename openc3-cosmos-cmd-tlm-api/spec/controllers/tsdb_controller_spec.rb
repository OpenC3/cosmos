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

RSpec.describe TsdbController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
  end

  describe "#execute_raw" do
    it "executes the query" do
      result = double("result", fields: ["a"], values: [[1]])
      conn = double("conn")
      expect(conn).to receive(:exec).with("SELECT 1").and_return(result)
      expect(OpenC3::QuestDBClient).to receive(:connection).with(db_shard: 0).and_return(conn)
      request.content_type = "text/plain"
      post :execute_raw, body: "SELECT 1", params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eql({"columns" => ["a"], "rows" => [[1]]})
    end

    it "requires superadmin rather than admin of the requested scope" do
      expect(controller).to receive(:authorize).with(hash_including(permission: "superadmin", scope: "DEFAULT")).and_raise(OpenC3::ForbiddenError.new("no superadmin"))
      expect(OpenC3::QuestDBClient).not_to receive(:connection)
      request.content_type = "text/plain"
      post :execute_raw, body: "SELECT 1", params: {scope: "DEFAULT"}
      expect(response).to have_http_status(:forbidden)
    end
  end
end
