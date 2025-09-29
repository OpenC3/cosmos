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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'rails_helper'

RSpec.describe NotesController, :type => :controller do
  before(:each) do
    mock_redis()
  end

  def create_note(start: Time.now - 20, stop: Time.now - 10, description: 'note')
    post :create, params: { scope: 'DEFAULT', start: start.iso8601, stop: stop.iso8601, description: description }
    return [start, stop]
  end

  describe "POST create" do
    it "successfully creates note object with status code 201" do
      start, stop = create_note()
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['updated_at'].to_i / Time::NSEC_PER_SECOND).to be_within(1).of(Time.now.to_i)
      expect(json['start']).to be_within(1).of(start.to_i)
      expect(json['stop']).to be_within(1).of(stop.to_i)
    end

    it "requires scope" do
      start = Time.now - 20
      stop = Time.now - 10
      post :create, params: { start: start.iso8601, stop: stop.iso8601, description: 'test' }
      expect(response).to have_http_status(401)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['status']).to eql('error')
      expect(json['message']).to eql('Scope is required')
    end

    it "requires start" do
      start = Time.now - 20
      stop = Time.now - 10
      post :create, params: { scope: 'DEFAULT', stop: stop.iso8601, description: 'test' }
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['status']).to eql('error')
      expect(json['message']).to include("Param 'start' is required")
    end

    it "requires stop" do
      start = Time.now - 20
      stop = Time.now - 10
      post :create, params: { scope: 'DEFAULT', start: start.iso8601, description: 'test' }
      expect(response).to have_http_status(400)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['status']).to eql('error')
      expect(json['message']).to include("Param 'stop' is required")
    end
  end

  describe "GET index" do
    it "successfully returns an empty array and status code 200" do
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json).to eql([])
    end

    it "successfully returns all the metadata" do
      create_note(start: Time.now - 20, stop: Time.now - 10, description: 'note1')
      create_note(start: Time.now - 40, stop: Time.now - 20, description: 'note2')
      create_note(start: Time.now - 60, stop: Time.now - 50, description: 'note3')
      start = Time.now - 20
      stop = Time.now - 10
      post :create, params: { scope: 'OTHER', start: start.iso8601, stop: stop.iso8601, description: "note4" }
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret.length).to eql(3)
      description = ret.map { |item| item['description'] }
      expect(description).to eql(['note1', 'note2', 'note3'])
      get :index, params: { scope: 'OTHER' }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      description = ret.map { |item| item['description'] }
      expect(description).to eql(['note4'])
    end

    it "requests a range of notes based on date" do
      now = Time.now
      create_note(start: now - 20, stop: now - 10, description: 'note1')
      create_note(start: now - 40, stop: now - 20, description: 'note2')
      create_note(start: now - 60, stop: now - 50, description: 'note3')

      get :index, params: { scope: 'DEFAULT', start: now - 70, stop: now - 45 }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret.length).to eql(1)
      description = ret.map { |item| item['description'] }
      expect(description).to eql(['note3'])

      get :index, params: { scope: 'DEFAULT', start: now - 45, stop: now }
      expect(response).to have_http_status(:ok)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret.length).to eql(2)
      description = ret.map { |item| item['description'] }
      expect(description).to eql(['note2', 'note1'])
    end

    it "returns an error and status code 401 with bad authorization" do
      get :index # Simply don't pass in the scope
      expect(response).to have_http_status(:unauthorized)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match("Scope is required")
    end
  end

  describe "GET show" do
    it "returns an error object with status code 404" do
      get :show, params: { scope: 'DEFAULT', id: '42' }
      expect(response).to have_http_status(:not_found)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).to match("not found")
    end

    it "returns an instance and status code 200" do
      start, stop = create_note()
      get :show, params: { scope: 'DEFAULT', id: start.to_i }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['start']).to eql(start.to_i)
    end
  end

  describe "PUT update" do
    it "returns error if id not found" do
      put :update, params: { scope: 'DEFAULT', id: '12345' }
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql("error")
      expect(ret['message']).not_to be_nil
      expect(response).to have_http_status(:not_found)
    end

    it "successfully updates a note and status code 200" do
      start, stop = create_note()
      put :update, params: { scope: 'DEFAULT', id: start.to_i, start: start.iso8601, stop: stop.iso8601, description: 'updated' }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['start']).to eql(start.to_i)
      expect(json['description']).to eql('updated')

      get :show, params: { scope: 'DEFAULT', id: start.to_i }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['start']).to eql(start.to_i)
      expect(json['description']).to eql('updated')
    end

    it "successfully updates a note object with a different start time and status code 200" do
      start, stop = create_note()
      put :update, params: { scope: 'DEFAULT', id: start.to_i, start: (start - 100).iso8601, stop: stop.iso8601, description: 'updated' }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['start']).to eql(start.to_i - 100)
      expect(json['description']).to eql('updated')
    end

    it "attempts to update with no stop and status code 400" do
      start, stop = create_note()
      put :update, params: { scope: 'DEFAULT', id: start.to_i, start: start.iso8601, description: 'updated' }
      expect(response).to have_http_status(:bad_request)
      ret = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(ret['status']).to eql('error')
      expect(ret['message']).not_to be_nil
    end
  end

  describe "DELETE" do
    it "returns error if id not found" do
      delete :destroy, params: { 'scope' => 'DEFAULT', 'id' => '12345' }
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json['status']).to eql('error')
      expect(json['message']).not_to be_nil
      expect(response).to have_http_status(:not_found)
    end

    it "deletes an existing item" do
      start = Time.now - 20
      stop = Time.now - 10
      post :create, params: { 'scope' => 'DEFAULT', start: start.iso8601, stop: stop.iso8601, description: 'test' }
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      delete :destroy, params: { 'scope' => 'DEFAULT', 'id' => json['start'] }
      expect(response).to have_http_status(:success)
      get :index, params: { 'scope' => 'DEFAULT', 'name' => json['name'] }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, allow_nan: true, create_additions: true)
      expect(json).to eql([])
    end
  end
end
