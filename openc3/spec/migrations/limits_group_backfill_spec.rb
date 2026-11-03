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
require 'openc3/migrations/20261103000001_limits_group_backfill'

module OpenC3
  describe LimitsGroupBackfill do
    before(:each) do
      mock_redis()
      %w(DEFAULT OTHER).each do |scope|
        ScopeModel.new(name: scope).create
        TargetModel.new(name: 'COSMOS', scope: scope).create
        MicroserviceModel.new(name: "#{scope}__SCOPEMULTI__#{scope}", cmd: ["ruby", "multi_microservice.rb", "#{scope}__SCOPECLEANUP__#{scope}"], scope: scope).create
      end
      Store.hset("DEFAULT__limits_groups", "TEMPS", JSON.generate([%w(INST HEALTH_STATUS TEMP1)]))
    end

    it "defines COSMOS LIMITS_GROUP and adds the microservice to SCOPEMULTI in every scope" do
      LimitsGroupBackfill.run
      %w(DEFAULT OTHER).each do |scope|
        model = MicroserviceModel.get_model(name: "#{scope}__LIMITSGROUP__#{scope}", scope: scope)
        expect(model.cmd).to eql ["ruby", "limits_group_microservice.rb", "#{scope}__LIMITSGROUP__#{scope}"]
        expect(model.parent).to eql "#{scope}__SCOPEMULTI__#{scope}"
        multi = MicroserviceModel.get_model(name: "#{scope}__SCOPEMULTI__#{scope}", scope: scope)
        expect(multi.cmd).to eql ["ruby", "multi_microservice.rb", "#{scope}__SCOPECLEANUP__#{scope}", "#{scope}__LIMITSGROUP__#{scope}"]
      end
      items = TargetModel.packet("COSMOS", "LIMITS_GROUP", scope: "DEFAULT")['items'].map { |item| item['name'] }
      expect(items).to include("TEMPS", "TEMPS_ENABLED")
      items = TargetModel.packet("COSMOS", "LIMITS_GROUP", scope: "OTHER")['items'].map { |item| item['name'] }
      expect(items).to_not include("TEMPS")
    end

    it "does nothing the second time" do
      LimitsGroupBackfill.run
      LimitsGroupBackfill.run
      multi = MicroserviceModel.get_model(name: "DEFAULT__SCOPEMULTI__DEFAULT", scope: "DEFAULT")
      expect(multi.cmd.count("DEFAULT__LIMITSGROUP__DEFAULT")).to eql 1
    end
  end
end
