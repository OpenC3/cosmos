# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license 
# if purchased from OpenC3, Inc.

require 'rails_helper'

RSpec.describe EnvironmentController, :type => :controller do
  before(:each) do
    mock_redis()
  end

  describe "GET index" do
    it "returns an empty array and status code 200" do
      get :index, params: { "scope" => "DEFAULT" }
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json).to eql([])
      expect(response).to have_http_status(:ok)
    end

    it "returns results only in the specified scope" do
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME1', 'value' => 'Jason' }
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME2', 'value' => 'Ryan' }
      post :create, params: { 'scope' => 'ANOTHER', 'key' => 'NAME3', 'value' => 'Mike' }
      get :index, params: { "scope" => "DEFAULT" }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json.length).to eql(2)
      expect(json[0].keys.sort).to eql(%w(key name updated_at value))
      expect(json[0]['value']).to eql('Jason')
      expect(json[1]['value']).to eql('Ryan')

      get :index, params: { "scope" => "ANOTHER" }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json[0].keys.sort).to eql(%w(key name updated_at value))
      expect(json[0]['value']).to eql('Mike')
    end
  end

  describe "POST create" do
    it "returns a json hash of name and status code 201" do
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME', 'value' => 'Jason' }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json["key"]).to eql('NAME')
      expect(json["value"]).to eql('Jason')
    end

    it "requires scope" do
      post :create, params: { 'key' => 'NAME', 'value' => 'Jason' }
      expect(response).to have_http_status(401)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).to eql('Scope is required')
    end

    it "requires key" do
      post :create, params: { 'scope' => 'DEFAULT', 'value' => 'Jason' }
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).to eql("Parameter 'key' is required")
    end

    it "requires value" do
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME' }
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).to eql("Parameter 'value' is required")
    end

    it "rejects an identical key / value pair" do
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME', 'value' => 'Jason' }
      expect(response).to have_http_status(:created)
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME', 'value' => 'Jason' }
      expect(response).to have_http_status(409)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).to eql("Key: 'NAME' value: 'Jason' already exists")
    end

    it "updates an existing value" do
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME', 'value' => 'Jason' }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json["key"]).to eql('NAME')
      expect(json["value"]).to eql('Jason')
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME', 'value' => 'Ryan' }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json["key"]).to eql('NAME')
      expect(json["value"]).to eql('Ryan')
    end
  end

  describe "DELETE" do
    it "returns error if key / value not found" do
      delete :destroy, params: { 'scope' => 'DEFAULT', "name" => "abc123" }
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).not_to be_nil
      expect(response).to have_http_status(:not_found)
    end

    it "deletes an existing item" do
      post :create, params: { 'scope' => 'DEFAULT', 'key' => 'NAME', 'value' => 'Jason' }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      delete :destroy, params: { 'scope' => 'DEFAULT', 'name' => json['name'] }
      expect(response).to have_http_status(:no_content)
      get :index, params: { 'scope' => 'DEFAULT', 'name' => json['name'] }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json).to eql([])
    end
  end
end
