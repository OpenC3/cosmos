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
        MicroserviceModel.new(name: "#{scope}__SCOPEMULTI__#{scope}", cmd: ["ruby", "multi_microservice.rb", "#{scope}__SCOPECLEANUP__#{scope}"], scope: scope).create
      end
      # Groups stored by name alone before they were owned by a target
      TargetModel.new(name: 'SYSTEM', scope: 'DEFAULT', db_shard: 1, limits_groups: %w(TEMPS POWER)).create
      TargetModel.new(name: 'INST', scope: 'DEFAULT').create
      Store.hset("DEFAULT__limits_groups", "TEMPS", JSON.generate([%w(INST HEALTH_STATUS TEMP1)]))
      Store.hset("DEFAULT__limits_groups", "POWER", JSON.generate([%w(INST HEALTH_STATUS VOLTS)]))
    end

    it "stores groups under their target, defines the LIMITS_GROUP packets and adds the microservice to SCOPEMULTI in every scope" do
      LimitsGroupBackfill.run
      %w(DEFAULT OTHER).each do |scope|
        model = MicroserviceModel.get_model(name: "#{scope}__LIMITSGROUP__#{scope}", scope: scope)
        expect(model.cmd).to eql ["ruby", "limits_group_microservice.rb", "#{scope}__LIMITSGROUP__#{scope}"]
        expect(model.parent).to eql "#{scope}__SCOPEMULTI__#{scope}"
        multi = MicroserviceModel.get_model(name: "#{scope}__SCOPEMULTI__#{scope}", scope: scope)
        expect(multi.cmd).to eql ["ruby", "multi_microservice.rb", "#{scope}__SCOPECLEANUP__#{scope}", "#{scope}__LIMITSGROUP__#{scope}"]
      end
      expected = {
        "SYSTEM__TEMPS" => JSON.generate([%w(INST HEALTH_STATUS TEMP1)]),
        "SYSTEM__POWER" => JSON.generate([%w(INST HEALTH_STATUS VOLTS)]),
      }
      expect(Store.hgetall("DEFAULT__limits_groups")).to eql expected
      items = JSON.parse(Store.instance(db_shard: 1).hget("DEFAULT__openc3tlm__SYSTEM", "LIMITS_GROUP"))['items'].map { |item| item['name'] }
      expect(items).to include("TEMPS", "TEMPS_ENABLED", "POWER", "POWER_ENABLED")
      expect(Store.hexists("DEFAULT__openc3tlm__INST", "LIMITS_GROUP")).to be false
    end

    it "seeds the CVT, allitems and item map without overwriting published values" do
      CvtModel.set({ "TEMPS" => 2 }, target_name: "SYSTEM", packet_name: "LIMITS_GROUP", scope: "DEFAULT")
      LimitsGroupBackfill.run
      cvt = CvtModel.get(target_name: "SYSTEM", packet_name: "LIMITS_GROUP", scope: "DEFAULT")
      expect(cvt["TEMPS"]).to eql 2
      expect(Store.instance(db_shard: 1).zrange("DEFAULT__openc3tlm__SYSTEM__allitems", 0, -1)).to include("TEMPS", "TEMPS_ENABLED", "POWER", "POWER_ENABLED")
      expect(TargetModel.get_item_to_packet_map("SYSTEM", scope: "DEFAULT")["TEMPS"]).to eql ["LIMITS_GROUP"]
    end

    it "warns about a target with its own LIMITS_GROUP packet" do
      Store.instance(db_shard: 1).hset("DEFAULT__openc3tlm__SYSTEM", "LIMITS_GROUP", JSON.generate({ 'items' => [] }))
      expect(Logger).to receive(:warn).with(/Target SYSTEM in scope DEFAULT has its own LIMITS_GROUP packet/)
      LimitsGroupBackfill.run
      expect(JSON.parse(Store.instance(db_shard: 1).hget("DEFAULT__openc3tlm__SYSTEM", "LIMITS_GROUP"))).to eql({ 'items' => [] })
      expect(Store.hkeys("DEFAULT__limits_groups").sort).to eql %w(SYSTEM__POWER SYSTEM__TEMPS)
    end

    it "keeps a group whose new key is also a legacy group name" do
      # Before groups were owned by a target a name could contain '__'
      model = TargetModel.get_model(name: 'INST', scope: 'DEFAULT')
      model.limits_groups = %w(SYSTEM__TEMPS)
      model.update
      Store.hset("DEFAULT__limits_groups", "SYSTEM__TEMPS", JSON.generate([%w(INST HEALTH_STATUS TEMP2)]))
      LimitsGroupBackfill.run
      expected = {
        "SYSTEM__TEMPS" => JSON.generate([%w(INST HEALTH_STATUS TEMP1)]),
        "SYSTEM__POWER" => JSON.generate([%w(INST HEALTH_STATUS VOLTS)]),
        "INST__SYSTEM__TEMPS" => JSON.generate([%w(INST HEALTH_STATUS TEMP2)]),
      }
      expect(Store.hgetall("DEFAULT__limits_groups")).to eql expected
    end

    it "adds the microservice to SCOPEMULTI when a previous run stopped after creating it" do
      parent = "DEFAULT__SCOPEMULTI__DEFAULT"
      options = ScopeModel.limits_group_microservice_options('DEFAULT', nil, parent)
      MicroserviceModel.new(**options).create
      LimitsGroupBackfill.run
      multi = MicroserviceModel.get_model(name: parent, scope: "DEFAULT")
      expect(multi.cmd).to include("DEFAULT__LIMITSGROUP__DEFAULT")
    end

    it "does nothing the second time" do
      LimitsGroupBackfill.run
      LimitsGroupBackfill.run
      expect(Store.hkeys("DEFAULT__limits_groups").sort).to eql %w(SYSTEM__POWER SYSTEM__TEMPS)
      multi = MicroserviceModel.get_model(name: "DEFAULT__SCOPEMULTI__DEFAULT", scope: "DEFAULT")
      expect(multi.cmd.count("DEFAULT__LIMITSGROUP__DEFAULT")).to eql 1
    end
  end
end
