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
require 'openc3/migrations/20260731000000_system_health_json'

module OpenC3
  describe SystemHealthJson do
    before(:each) do
      mock_redis()
    end

    describe "repair" do
      it "returns the defaults if there is no setting" do
        expect(SystemHealthJson.repair(nil)).to eq(ScopeModel::SYSTEM_HEALTH_DEFAULTS)
      end

      it "returns a Hash stored by older versions" do
        hash = {"cpu" => {"redThreshold" => 95.0}}
        expect(SystemHealthJson.repair(hash)).to eq(hash)
      end

      it "parses a JSON String" do
        hash = {"cpu" => {"redThreshold" => 95.0}}
        expect(SystemHealthJson.repair(JSON.generate(hash))).to eq(hash)
      end

      it "recovers values from a Ruby inspect String" do
        hash = {"cpu" => {"redThreshold" => 95.0, "lastTriggerTimeRed" => nil}}
        expect(SystemHealthJson.repair(hash.to_s)).to eq(hash)
      end

      it "returns the defaults if the data can't be understood" do
        expect(SystemHealthJson.repair("not a setting")).to eq(ScopeModel::SYSTEM_HEALTH_DEFAULTS)
      end
    end

    describe "run" do
      it "stores the setting as a JSON String" do
        SettingModel.set({name: 'system_health', data: ScopeModel::SYSTEM_HEALTH_DEFAULTS}, scope: 'DEFAULT')
        SystemHealthJson.run()
        data = SettingModel.get(name: 'system_health')['data']
        expect(data).to be_a String
        expect(JSON.parse(data)).to eq(JSON.parse(JSON.generate(ScopeModel::SYSTEM_HEALTH_DEFAULTS)))
      end
    end
  end
end
