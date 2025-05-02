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

RSpec.describe ApiController, type: :controller do
  let(:sample_request) { '{"jsonrpc":"2.0","method":"method_name","params":[],"id":1}' }
  let(:sample_response) { '{"jsonrpc":"2.0","result":"success","id":1}' }
  let(:sample_invalid_request) { "invalid json" }
  let(:sample_request_headers) { {"HTTP_CONTENT_TYPE" => "application/json-rpc"} }

  let(:sample_error_responses) do
    {
      invalid_request: '{"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Request"},"id":null}',
      auth_error: '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Authentication failed"},"id":1}',
      forbidden_error: '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Access forbidden"},"id":1}',
      method_not_found: '{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":1}',
      hazardous_error: '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Hazardous operation"},"id":1}',
      critical_cmd_error: '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Critical command rejected"},"id":1}',
      internal_error: '{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"},"id":1}'
    }
  end

  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:debug)
    allow(OpenC3::Logger).to receive(:warn)

    # Mock OpenTelemetry
    allow(OpenC3).to receive(:in_span).and_yield(nil)
  end

  describe "GET ping" do
    it "returns OK" do
      get :ping
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("OK")
    end
  end

  describe "POST api" do
    before(:each) do
      # Mock Cts and JsonDRb
      @json_drb = double("JsonDRb")
      @cts = double("Cts", json_drb: @json_drb)
      allow(OpenC3::Cts).to receive(:instance).and_return(@cts)
    end

    it "handles successful requests" do
      request.env["RAW_POST_DATA"] = sample_request
      allow(@json_drb).to receive(:process_request).and_return([sample_response, nil])

      post :api
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/json-rpc")
      expect(response.body).to eq(sample_response)
    end

    it "handles authentication errors" do
      request.env["RAW_POST_DATA"] = sample_request

      allow(@json_drb).to receive(:process_request).and_raise(OpenC3::AuthError, "Authentication failed")

      post :api
      expect(response).to have_http_status(:unauthorized)
      expect(response.content_type).to eq("application/json-rpc")
      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq(OpenC3::JsonRpcError::ErrorCode::AUTH_ERROR)
      expect(json["error"]["message"]).to eq("Authentication failed")
    end

    it "handles forbidden errors" do
      request.env["RAW_POST_DATA"] = sample_request

      allow(@json_drb).to receive(:process_request).and_raise(OpenC3::ForbiddenError, "Access forbidden")

      post :api
      expect(response).to have_http_status(:forbidden)
      expect(response.content_type).to eq("application/json-rpc")
      json = JSON.parse(response.body)
      expect(json["error"]["code"]).to eq(OpenC3::JsonRpcError::ErrorCode::FORBIDDEN_ERROR)
      expect(json["error"]["message"]).to eq("Access forbidden")
    end

    it "handles JSON-RPC error responses" do
      request.env["RAW_POST_DATA"] = sample_request

      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:method_not_found], OpenC3::JsonRpcError::ErrorCode::METHOD_NOT_FOUND])

      post :api
      expect(response).to have_http_status(:not_found)
      expect(response.content_type).to eq("application/json-rpc")
      expect(response.body).to eq(sample_error_responses[:method_not_found])
    end

    it "supports ignored errors header" do
      request.env["RAW_POST_DATA"] = sample_request
      request.env["HTTP_IGNORE_ERRORS"] = "500"

      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:internal_error], OpenC3::JsonRpcError::ErrorCode::INTERNAL_ERROR])

      post :api
      expect(response).to have_http_status(:internal_server_error)
      expect(response.content_type).to eq("application/json-rpc")
      expect(response.body).to eq(sample_error_responses[:internal_error])
      expect(response.headers["Ignore-Errors"]).to eq("500")
    end
  end

  describe "#handle_post" do
    before(:each) do
      # Mock Cts and JsonDRb
      @json_drb = double("JsonDRb")
      @cts = double("Cts", json_drb: @json_drb)
      allow(OpenC3::Cts).to receive(:instance).and_return(@cts)
    end

    it "returns success status with response" do
      allow(@json_drb).to receive(:process_request).and_return([sample_response, nil])

      status, content_type, body = controller.handle_post(sample_request, sample_request_headers)

      expect(status).to eq(200)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_response)
    end

    it "handles invalid request errors" do
      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:invalid_request], OpenC3::JsonRpcError::ErrorCode::INVALID_REQUEST])

      status, content_type, body = controller.handle_post(sample_invalid_request, sample_request_headers)

      expect(status).to eq(400)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_error_responses[:invalid_request])
    end

    it "handles authentication errors" do
      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:auth_error], OpenC3::JsonRpcError::ErrorCode::AUTH_ERROR])

      status, content_type, body = controller.handle_post(sample_request, sample_request_headers)

      expect(status).to eq(401)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_error_responses[:auth_error])
    end

    it "handles forbidden errors" do
      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:forbidden_error], OpenC3::JsonRpcError::ErrorCode::FORBIDDEN_ERROR])

      status, content_type, body = controller.handle_post(sample_request, sample_request_headers)

      expect(status).to eq(403)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_error_responses[:forbidden_error])
    end

    it "handles method not found errors" do
      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:method_not_found], OpenC3::JsonRpcError::ErrorCode::METHOD_NOT_FOUND])

      status, content_type, body = controller.handle_post(sample_request, sample_request_headers)

      expect(status).to eq(404)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_error_responses[:method_not_found])
    end

    it "handles hazardous errors" do
      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:hazardous_error], OpenC3::JsonRpcError::ErrorCode::HAZARDOUS_ERROR])

      status, content_type, body = controller.handle_post(sample_request, sample_request_headers)

      expect(status).to eq(409)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_error_responses[:hazardous_error])
    end

    it "handles critical command errors" do
      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:critical_cmd_error], OpenC3::JsonRpcError::ErrorCode::CRITICAL_CMD_ERROR])

      status, content_type, body = controller.handle_post(sample_request, sample_request_headers)

      expect(status).to eq(428)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_error_responses[:critical_cmd_error])
    end

    it "handles other internal errors" do
      allow(@json_drb).to receive(:process_request).and_return([sample_error_responses[:internal_error], OpenC3::JsonRpcError::ErrorCode::INTERNAL_ERROR])

      status, content_type, body = controller.handle_post(sample_request, sample_request_headers)

      expect(status).to eq(500)
      expect(content_type).to eq("application/json-rpc")
      expect(body).to eq(sample_error_responses[:internal_error])
    end
  end
end
