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

require 'spec_helper'
require 'openc3/models/service_account_script_auth_model'

module OpenC3
  describe ServiceAccountScriptAuthModel, type: :model do
    before(:each) do
      mock_redis()
    end

    it 'creates a new model' do
      model = ServiceAccountScriptAuthModel.new(
        name: 'service-account-cosmos-m2m',
        auth_kind: 'client_credentials',
        client_id: 'cosmos-m2m',
        client_secret_name: 'cosmos-m2m',
        scope: 'DEFAULT',
      )
      expect(model).to be_a(ServiceAccountScriptAuthModel)
    end

    it 'returns nil from get when the record is missing' do
      expect(ServiceAccountScriptAuthModel.get(name: 'service-account-cosmos-m2m', scope: 'DEFAULT')).to be_nil
    end

    it 'keeps records isolated by scope' do
      model = ServiceAccountScriptAuthModel.new(
        name: 'service-account-cosmos-m2m',
        auth_kind: 'client_credentials',
        client_id: 'cosmos-m2m',
        client_secret_name: 'cosmos-m2m',
        scope: 'OTHER',
      )
      model.create

      expect(ServiceAccountScriptAuthModel.get(name: 'service-account-cosmos-m2m', scope: 'DEFAULT')).to be_nil
      expect(ServiceAccountScriptAuthModel.get(name: 'service-account-cosmos-m2m', scope: 'OTHER')['client_id']).to eq('cosmos-m2m')
    end

    it 'serializes the stored fields' do
      model = ServiceAccountScriptAuthModel.new(
        name: 'service-account-cosmos-m2m',
        auth_kind: 'client_credentials',
        client_id: 'cosmos-m2m',
        client_secret_name: 'cosmos-m2m',
        scope: 'DEFAULT',
      )
      expect(model.as_json).to include(
        'name' => 'service-account-cosmos-m2m',
        'auth_kind' => 'client_credentials',
        'client_id' => 'cosmos-m2m',
        'client_secret_name' => 'cosmos-m2m',
        'scope' => 'DEFAULT',
      )
    end
  end
end
