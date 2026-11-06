# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'faraday'
require 'openc3/models/plugin_store_model'
require 'openc3/models/setting_model'

module OpenC3
  describe PluginStoreModel do
    before(:each) do
      mock_redis()
      @requested = []
      @statuses = {}
      requested = @requested
      statuses = @statuses
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        ['/api/v1.3/cosmos_plugins', '/api/v1.2/cosmos_plugins'].each do |path|
          stub.get(path) do
            requested << path
            [statuses.fetch(path, 200), { 'Content-Type' => 'application/json' }, "[{\"id\":1,\"api\":\"#{path}\"}]"]
          end
        end
      end
      allow(Faraday).to receive(:new).and_wrap_original do |original, **kwargs, &block|
        original.call(**kwargs) do |faraday|
          block&.call(faraday)
          faraday.adapter(:test, stubs)
        end
      end
    end

    it "reads the store catalog with discovery data" do
      PluginStoreModel.update
      expect(@requested).to eql ['/api/v1.3/cosmos_plugins']
      expect(JSON.parse(PluginStoreModel.all)).to eql [{ 'id' => 1, 'api' => '/api/v1.3/cosmos_plugins' }]
    end

    it "falls back to v1.2 for stores without v1.3" do
      [400, 404].each do |status|
        @requested.clear
        @statuses['/api/v1.3/cosmos_plugins'] = status
        PluginStoreModel.update
        expect(@requested).to eql ['/api/v1.3/cosmos_plugins', '/api/v1.2/cosmos_plugins']
        expect(PluginStoreModel.get_by_id(1)['api']).to eql '/api/v1.2/cosmos_plugins'
      end
    end

    it "reports other errors" do
      @statuses['/api/v1.3/cosmos_plugins'] = 500
      PluginStoreModel.update
      expect(@requested).to eql ['/api/v1.3/cosmos_plugins']
      expect(JSON.parse(PluginStoreModel.all)['body']).to include('status: 500')
    end
  end
end
