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
require 'openc3/models/trigger_model'
require 'openc3/models/trigger_group_model'

RSpec.describe ReactionController, :type => :controller do
  GROUP = 'DEFAULT'.freeze

  before(:each) do
    mock_redis()
    model = OpenC3::TriggerGroupModel.new(name: GROUP, scope: 'DEFAULT')
    model.create()
    model = OpenC3::TriggerGroupModel.new(name: 'TEST', scope: 'TEST')
    model.create()
  end

  def generate_trigger(
    scope: 'DEFAULT',
    name: 'TRIG1',
    group: GROUP,
    left: {
      "type" => "item",
      "target" => "INST",
      "packet" => "ADCS",
      "item" => "POSX",
      "valueType" => "RAW",
    },
    operator: '>',
    right: {
      'type' => 'float',
      'float' => 10.0,
    })
    OpenC3::TriggerModel.new(
      name: name,
      scope: scope,
      group: group,
      left: left,
      operator: operator,
      right: right,
    ).create()
  end

  def generate_reaction_hash(
    description: 'another test',
    triggers: [{'name': 'TRIG1', 'group': GROUP}],
    actions: [{'type' => 'command', 'value' => 'INST ABORT'}]
  )
    return {
      'snooze' => 300,
      'triggers' => triggers,
      'trigger_level' => 'EDGE',
      'actions' => actions
    }
  end

  describe 'GET index' do
    it 'returns an empty array and status code 200' do
      get :index, params: {'scope'=>'DEFAULT'}
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json).to eql([])
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST then GET index with Triggers' do
    it 'returns an array and status code 200' do
      generate_trigger()
      hash = generate_reaction_hash()
      post :create, params: hash.merge({'scope'=>'DEFAULT'})
      expect(response).to have_http_status(:created)
      trigger = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(trigger['name']).not_to be_nil
      get :show, params: { scope: 'DEFAULT', name: trigger['name'] }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      get :index, params: { scope: 'DEFAULT' }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json.empty?).to eql(false)
      expect(json.length).to eql(1)
      expect(json[0]['name']).to eql(trigger['name'])
    end
  end

  describe 'POST two reactions on different scopes then GET index' do
    it 'returns an array of one and status code 200' do
      generate_trigger()
      hash = generate_reaction_hash()
      post :create, params: hash.merge({'scope'=>'DEFAULT'})
      expect(response).to have_http_status(:created)
      default_json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      generate_trigger(scope: 'TEST', group: 'TEST')
      hash['triggers'][0][:group] = 'TEST'
      post :create, params: hash.merge({scope: 'TEST'})
      expect(response).to have_http_status(:created)
      test_json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(default_json['name']).to eql(test_json['name'])
      # check the value on the index
      get :index, params: {'scope'=>'DEFAULT'}
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json.empty?).to eql(false)
      expect(json.length).to eql(1)
      expect(json[0]['name']).to eql(default_json['name'])
    end
  end

  # describe 'PUT update' do
  #   it 'returns a json hash of name and status code 200' do
  #     hash = generate_reaction_hash()
  #     post :create, params: hash.merge({'scope'=>'DEFAULT'})
  #     expect(response).to have_http_status(:created)
  #     json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
  #     expect(json['name']).not_to be_nil
  #     expect(json['dependents']).not_to be_nil
  #     json['description'] = 'something...'
  #     put :update, params: json.merge({'scope'=>'DEFAULT'})
  #     expect(response).to have_http_status(:ok)
  #     json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
  #     expect(json['name']).not_to be_nil
  #     expect(json['description']).to eql('something...')
  #   end
  # end

  describe 'POST error bad trigger' do
    it 'returns a hash and status code 400' do
      hash = generate_reaction_hash()
      hash['triggers'][0]['name'] = 'BAD'
      post :create, params: hash.merge({'scope'=>'DEFAULT'})
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).not_to be_nil
      expect(response).to have_http_status(400)
    end
  end

  describe 'DELETE' do
    it 'returns a json hash of name and status code 404 if not found' do
      delete :destroy, params: {'scope'=>'DEFAULT', 'name'=>'test'}
      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['status']).to eql('error')
      expect(json['message']).not_to be_nil
    end

    it 'returns a json hash of name and status code 200 if found' do
      generate_trigger()
      hash = generate_reaction_hash()
      post :create, params: hash.merge({'scope'=>'DEFAULT'})
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      delete :destroy, params: {'scope'=>'DEFAULT', 'name'=>json['name']}
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body, :allow_nan => true, :create_additions => true)
      expect(json['name']).to eql('REACT1')
    end
  end
end
