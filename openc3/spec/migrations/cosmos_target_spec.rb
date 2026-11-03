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
ENV['OPENC3_NO_MIGRATE'] = 'true'
require 'openc3/migrations/20261103000000_cosmos_target'

module OpenC3
  describe CosmosTarget do
    before(:each) do
      mock_redis()
      ScopeModel.new(name: 'DEFAULT').create
      ScopeModel.new(name: 'OTHER').create
    end

    it "creates the COSMOS target in every scope" do
      CosmosTarget.run
      expect(TargetModel.get(name: 'COSMOS', scope: 'DEFAULT')).to_not be_nil
      expect(TargetModel.get(name: 'COSMOS', scope: 'OTHER')).to_not be_nil
    end

    it "leaves an existing COSMOS target alone" do
      TargetModel.new(name: 'COSMOS', plugin: 'old-plugin-1.0.0.gem', scope: 'DEFAULT').create
      expect(Logger).to receive(:warn).with(/COSMOS target from plugin old-plugin-1.0.0.gem/)
      CosmosTarget.run
      expect(TargetModel.get(name: 'COSMOS', scope: 'DEFAULT')['plugin']).to eql 'old-plugin-1.0.0.gem'
      expect(TargetModel.get(name: 'COSMOS', scope: 'OTHER')).to_not be_nil
    end

    it "does nothing the second time" do
      CosmosTarget.run
      expect { CosmosTarget.run }.to_not raise_error
    end
  end
end
