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
      # LATEST never resolves to LIMITS_GROUP so its items stay out of the item map
      expect(TargetModel.get_item_to_packet_map("SYSTEM", scope: "DEFAULT")).not_to have_key("TEMPS")
    end

    it "keeps and marks a target's own LIMITS_GROUP packet" do
      Store.instance(db_shard: 1).hset("DEFAULT__openc3tlm__SYSTEM", "LIMITS_GROUP", JSON.generate({ 'items' => [] }))
      expect(TargetModel.generated_limits_group_packet?("SYSTEM", "LIMITS_GROUP", scope: "DEFAULT")).to be true
      expect(Logger).to receive(:error).with(/Target SYSTEM in scope DEFAULT has a telemetry packet of its own named LIMITS_GROUP.*renamed and the target reinstalled/)
      LimitsGroupBackfill.run
      expect(JSON.parse(Store.instance(db_shard: 1).hget("DEFAULT__openc3tlm__SYSTEM", "LIMITS_GROUP"))).to eql({ 'items' => [] })
      expect(Store.hkeys("DEFAULT__limits_groups").sort).to eql %w(SYSTEM__POWER SYSTEM__TEMPS)
      # So it stays writable, in LATEST and isn't published over
      expect(TargetModel.get_model(name: "SYSTEM", scope: "DEFAULT").own_limits_group_packet).to be true
      expect(TargetModel.generated_limits_group_packet?("SYSTEM", "LIMITS_GROUP", scope: "DEFAULT")).to be false
    end

    it "removes groups whose names can't be LIMITS_GROUP items" do
      # Before groups were owned by a target any name was allowed. INST's
      # SYSTEM__TEMPS is also the new key of SYSTEM's TEMPS.
      model = TargetModel.get_model(name: 'INST', scope: 'DEFAULT')
      model.limits_groups = %w(SYSTEM__TEMPS HEATERS HEATERS_ENABLED)
      model.update
      Store.hset("DEFAULT__limits_groups", "SYSTEM__TEMPS", JSON.generate([%w(INST HEALTH_STATUS TEMP2)]))
      Store.hset("DEFAULT__limits_groups", "HEATERS", JSON.generate([%w(INST HEALTH_STATUS TEMP3)]))
      Store.hset("DEFAULT__limits_groups", "HEATERS_ENABLED", JSON.generate([%w(INST HEALTH_STATUS TEMP4)]))
      warnings = []
      allow(Logger).to receive(:warn) { |message| warnings << message }
      LimitsGroupBackfill.run
      expect(warnings).to eql [
        "Removed LIMITS_GROUP SYSTEM__TEMPS of target INST in scope DEFAULT: the name cannot contain a double underscore ('__'). Rename the group and reinstall the target to use it.",
        "Removed LIMITS_GROUP HEATERS_ENABLED of target INST in scope DEFAULT: the name cannot end with _ENABLED. Rename the group and reinstall the target to use it.",
      ]
      # A rerun (e.g. after add_microservice failed) must not rekey again
      LimitsGroupBackfill.run
      expected = {
        "SYSTEM__TEMPS" => JSON.generate([%w(INST HEALTH_STATUS TEMP1)]),
        "SYSTEM__POWER" => JSON.generate([%w(INST HEALTH_STATUS VOLTS)]),
        "INST__HEATERS" => JSON.generate([%w(INST HEALTH_STATUS TEMP3)]),
      }
      expect(Store.hgetall("DEFAULT__limits_groups")).to eql expected
      expect(TargetModel.get_model(name: 'INST', scope: 'DEFAULT').limits_groups).to eql %w(HEATERS)
      items = JSON.parse(Store.hget("DEFAULT__openc3tlm__INST", "LIMITS_GROUP"))['items'].map { |item| item['name'] }
      expect(items).to include("HEATERS", "HEATERS_ENABLED")
    end

    it "adds the LIMITS_GROUP packet to the target's TSDB microservice" do
      MicroserviceModel.new(name: "DEFAULT__TSDB__SYSTEM", topics: ["DEFAULT__DECOM__{SYSTEM}__HEALTH"], scope: "DEFAULT").create
      allow(Topic).to receive(:write_topic).and_call_original
      # A running microservice is told on the target's db_shard
      expect(Topic).to receive(:write_topic).with("MICROSERVICE__DEFAULT__TSDB__SYSTEM", { 'command' => 'ADD_TOPICS', 'topics' => ["DEFAULT__DECOM__{SYSTEM}__LIMITS_GROUP"].to_json }, db_shard: 1).once.and_call_original
      LimitsGroupBackfill.run
      expect(MicroserviceModel.get_model(name: "DEFAULT__TSDB__SYSTEM", scope: "DEFAULT").topics).to eql ["DEFAULT__DECOM__{SYSTEM}__HEALTH", "DEFAULT__DECOM__{SYSTEM}__LIMITS_GROUP"]
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
      config_name = JSON.parse(Store.instance(db_shard: 1).hget("DEFAULT__openc3tlm__SYSTEM", "LIMITS_GROUP"))['config_name']
      # The packet stored by the first run is recognized as the generated one
      expect(Logger).not_to receive(:warn)
      LimitsGroupBackfill.run
      expect(Store.hkeys("DEFAULT__limits_groups").sort).to eql %w(SYSTEM__POWER SYSTEM__TEMPS)
      expect(JSON.parse(Store.instance(db_shard: 1).hget("DEFAULT__openc3tlm__SYSTEM", "LIMITS_GROUP"))['config_name']).to eql config_name
      expect(TargetModel.get_model(name: "SYSTEM", scope: "DEFAULT").own_limits_group_packet).to be false
      multi = MicroserviceModel.get_model(name: "DEFAULT__SCOPEMULTI__DEFAULT", scope: "DEFAULT")
      expect(multi.cmd.count("DEFAULT__LIMITSGROUP__DEFAULT")).to eql 1
    end
  end
end
