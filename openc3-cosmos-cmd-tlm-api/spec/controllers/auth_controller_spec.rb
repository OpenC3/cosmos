# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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

require 'rails_helper'

RSpec.describe AuthController, :type => :controller do
  before(:each) do
    mock_redis()
  end

  describe "token-exists" do
    it "returns false then true when the token is set" do
      get :token_exists
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json).to eql({"result" => false})

      post :set, params: { token: 'PASSWORD' }
      expect(response).to have_http_status(:ok)

      get :token_exists
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json).to eql({"result" => true})
    end
  end

  describe "set" do
    it "requires old_token after initial set" do
      post :set, params: { token: 'PASSWORD' }
      expect(response).to have_http_status(:ok)

      post :set, params: { token: 'PASSWORD2' }
      expect(response).to have_http_status(:error)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json["status"]).to eql 'error'
      expect(json["message"]).to eql 'old_token must not be nil or empty'

      post :set, params: { token: 'PASSWORD2', old_token: 'BAD' }
      expect(response).to have_http_status(:error)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json["status"]).to eql 'error'
      expect(json["message"]).to eql 'old_token incorrect'

      post :set, params: { token: 'PASSWORD2', old_token: 'PASSWORD' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "verify" do
    it "requires token" do
      post :verify
      expect(response).to have_http_status(:unauthorized)
    end

    it "validates the set token" do
      post :set, params: { token: 'PASSWORD' }
      expect(response).to have_http_status(:ok)

      post :verify, params: { token: 'PASSWORD' }
      expect(response).to have_http_status(:ok)

      post :verify, params: { token: 'BAD' }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
