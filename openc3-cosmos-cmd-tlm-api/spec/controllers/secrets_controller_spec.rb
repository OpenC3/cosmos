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
require "openc3/utilities/secrets"

RSpec.describe SecretsController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:info)
    allow(OpenC3::Logger).to receive(:error)
    allow(controller).to receive(:log_error)

    @secrets_client = double("SecretsClient")
    allow(OpenC3::Secrets).to receive(:getClient).and_return(@secrets_client)
  end

  describe "GET index" do
    it "returns a list of secret keys" do
      secret_keys = ["SECRET1", "SECRET2", "SECRET3"]
      expect(@secrets_client).to receive(:keys).with(scope: "DEFAULT").and_return(secret_keys)

      get :index, params: {scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq(secret_keys)
    end

    it "returns nothing without authorization" do
      get :index

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST create" do
    it "creates a new secret" do
      expect(@secrets_client).to receive(:set).with("TEST_SECRET", "secret_value", scope: "DEFAULT")

      post :create, params: {key: "TEST_SECRET", value: "secret_value", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end

    it "returns nothing without authorization" do
      post :create, params: {key: "TEST_SECRET", value: "secret_value"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "handles errors" do
      allow(@secrets_client).to receive(:set).and_raise(StandardError.new("Failed to set secret"))
      post :create, params: {key: "TEST_SECRET", value: "secret_value", scope: "DEFAULT"}

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("Failed to set secret")
    end
  end

  describe "DELETE destroy" do
    it "deletes a secret" do
      expect(@secrets_client).to receive(:delete).with("TEST_SECRET", scope: "DEFAULT")

      delete :destroy, params: {key: "TEST_SECRET", scope: "DEFAULT"}

      expect(response).to have_http_status(:ok)
    end

    it "returns nothing without authorization" do
      delete :destroy, params: {key: "TEST_SECRET"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "handles errors" do
      allow(@secrets_client).to receive(:delete).and_raise(StandardError.new("Failed to delete secret"))

      delete :destroy, params: {key: "TEST_SECRET", scope: "DEFAULT"}

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["message"]).to eq("Failed to delete secret")
    end
  end
end
