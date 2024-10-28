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
require 'openc3/models/trigger_group_model'

RSpec.describe TriggerController, :type => :controller do
  GROUP = 'ALPHA'.freeze

  before(:each) do
    mock_redis()
    model = OpenC3::TriggerGroupModel.new(name: GROUP, scope: 'DEFAULT')
    model.create()
  end

  def generate_trigger_hash
    return {
      group: GROUP,
      left: {
        "type": 'item',
        "target": "INST",
        "packet": "ADCS",
        "item": "POSX",
        "valueType": "RAW",
      },
      operator: '>',
      right: {
        'type': 'float',
        'float': 10.0,
      }
    }
  end

  describe 'GET index' do
    it 'returns an empty array and status code 200' do
      get :index, params: { group: 'TEST', scope: 'DEFAULT'}
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json).to eql([])
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST then GET index with Triggers' do
    it 'returns an array and status code 200' do
      hash = generate_trigger_hash()
      post :create, params: hash.merge({ scope: 'DEFAULT' })
      expect(response).to have_http_status(:created)
      trigger = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(trigger['name']).not_to be_nil
      get :index, params: { group: GROUP, scope: 'DEFAULT' }
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json.empty?).to eql(false)
      expect(json.length).to eql(1)
      expect(json[0]['name']).to eql(trigger['name'])
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST create' do
    it 'returns a json hash of name and status code 201' do
      hash = generate_trigger_hash()
      post :create, params: hash.merge({ scope: 'DEFAULT' })
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      # Default name is TRIG plus index
      expect(json['name']).to eql('TRIG1')

      post :create, params: hash.merge({ scope: 'DEFAULT' })
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['name']).to eql('TRIG2')
    end
  end

  # describe 'PUT update' do
  #   it 'returns a json hash of name and status code 200' do
  #     hash = generate_trigger_hash()
  #     post :create, params: hash.merge({'scope'=>'DEFAULT'})
  #     expect(response).to have_http_status(:created)
  #     json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
  #     expect(json['name']).not_to be_nil
  #     expect(json['dependents']).not_to be_nil
  #     json['right']['value'] = 23
  #     put :update, params: json.merge({'scope'=>'DEFAULT'})
  #     expect(response).to have_http_status(:ok)
  #     json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
  #     expect(json['name']).not_to be_nil
  #     expect(json['right']['value']).to eql(23)
  #   end
  # end

  describe 'POST' do
    it 'returns a hash and status code 400 with bad operand' do
      hash = generate_trigger_hash()
      hash[:left].delete(:target)
      post :create, params: hash.merge({ scope: 'DEFAULT' })
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).to match(/invalid operand, must contain target, packet, item and valueType/)
      expect(response).to have_http_status(400)
    end
  end

  describe 'DELETE' do
    it 'returns a json hash of name and status code 404 if not found' do
      delete :destroy, params: { scope: 'DEFAULT', name: 'NOPE', group: GROUP }
      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).not_to be_nil
    end

    it 'returns a json hash of name and status code 204' do
      hash = generate_trigger_hash()
      post :create, params: hash.merge({ scope: 'DEFAULT' })
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      delete :destroy, params: { scope: 'DEFAULT', name: 'TRIG1', group: GROUP }
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['name']).to eql('TRIG1')
    end
  end
end
