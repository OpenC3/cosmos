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
require 'openc3/microservices/limits_group_microservice'
require 'openc3/api/limits_api'

module OpenC3
  describe LimitsGroupMicroservice do
    COSMOS_DB_SHARD = 2

    before(:each) do
      mock_redis()
      setup_system()
      # Members on db_shard 1 and the COSMOS target on db_shard 2
      setup_target_db_shards({ 'INST' => 1 })
      TargetModel.new(name: 'COSMOS', scope: 'DEFAULT', db_shard: COSMOS_DB_SHARD).create
      allow_any_instance_of(OpenC3::Microservice).to receive(:at_exit)
      @microservice = LimitsGroupMicroservice.new("DEFAULT__LIMITSGROUP__DEFAULT")
    end

    after(:each) do
      @microservice.shutdown
    end

    def store_groups(groups)
      Store.del("DEFAULT__limits_groups")
      groups.each { |group, items| Store.hset("DEFAULT__limits_groups", group, JSON.generate(items)) }
    end

    # Write the event like a decom microservice does then hand it to the microservice
    def limits_event(event)
      LimitsEventTopic.write(event, scope: 'DEFAULT')
      @microservice.process_event(JSON.parse(JSON.generate(event)))
    end

    def change(item, state)
      limits_event({ type: :LIMITS_CHANGE, target_name: 'INST', packet_name: 'HEALTH_STATUS', item_name: item,
                     old_limits_state: 'GREEN', new_limits_state: state, time_nsec: 0, message: 'test' })
    end

    def cvt
      json = Store.instance(db_shard: COSMOS_DB_SHARD).hget("DEFAULT__tlm__COSMOS", "LIMITS_GROUP")
      json ? JSON.parse(json) : nil
    end

    def publishes
      EphemeralStore.instance(db_shard: COSMOS_DB_SHARD).xrevrange("DEFAULT__DECOM__{COSMOS}__LIMITS_GROUP", count: 100).length
    end

    def start(groups)
      store_groups(groups)
      %w(TEMP1 TEMP2 TEMP3 TEMP4).each { |item| change(item, 'GREEN') }
      @microservice.reload
      @microservice.publish(force: true)
    end

    it "publishes nothing with no groups" do
      @microservice.reload
      @microservice.publish(force: true)
      expect(publishes).to eql 0
      expect(cvt).to be_nil
    end

    it "rolls up a member going RED" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1), %w(INST HEALTH_STATUS TEMP2)] })
      expect(cvt['TEMPS__C']).to eql 'GREEN'
      expect(cvt['TEMPS__L']).to eql 'GREEN'
      expect(cvt['TEMPS_ENABLED__C']).to eql 'TRUE'
      change('TEMP2', 'YELLOW_HIGH')
      expect(cvt['TEMPS']).to eql 1
      expect(cvt['TEMPS__C']).to eql 'YELLOW'
      change('TEMP1', 'RED_LOW')
      expect(cvt['TEMPS__C']).to eql 'RED'
      expect(cvt['TEMPS__L']).to eql 'RED'
      expect(publishes).to eql 3
    end

    it "doesn't publish for unrelated or unchanged events" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      change('TEMP3', 'RED')
      change('TEMP1', 'GREEN_HIGH')
      @microservice.reload
      @microservice.publish
      expect(publishes).to eql 1
    end

    it "reads limits on db_shard 0 and writes the packet on the COSMOS db_shard" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      expect(Store).to receive(:hget).with("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP1").and_call_original
      expect(Store).to receive(:hget).with("DEFAULT__current_limits_settings", "INST__HEALTH_STATUS__TEMP1").and_call_original
      change('TEMP1', 'RED')
      expect(cvt['TEMPS__C']).to eql 'RED'
      expect(Store.instance(db_shard: COSMOS_DB_SHARD).hexists("DEFAULT__tlm__COSMOS", "LIMITS_GROUP")).to be true
      expect(Store.instance(db_shard: 0).hexists("DEFAULT__tlm__COSMOS", "LIMITS_GROUP")).to be false
      expect(EphemeralStore.instance(db_shard: 0).exists("DEFAULT__DECOM__{COSMOS}__LIMITS_GROUP")).to eql 0
    end

    it "never raises limits events or changes the overall limits state" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      change('TEMP1', 'YELLOW')
      expect(Store.hkeys("DEFAULT__current_limits")).to_not include(a_string_starting_with("COSMOS"))
      api = Object.new.extend(Api)
      allow(api).to receive(:authorize)
      expect(api.get_out_of_limits(scope: 'DEFAULT')).to eql [%w(INST HEALTH_STATUS TEMP1 YELLOW)]
      expect(api.get_overall_limits_state(scope: 'DEFAULT')).to eql 'YELLOW'
    end

    it "ignores disabled members and reports the group not enabled" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1), %w(INST HEALTH_STATUS TEMP2)] })
      change('TEMP1', 'RED')
      limits_event({ type: :LIMITS_ENABLE_STATE, target_name: 'INST', packet_name: 'HEALTH_STATUS', item_name: 'TEMP1',
                     enabled: false, time_nsec: 0, message: 'test' })
      expect(cvt['TEMPS__C']).to eql 'GREEN'
      expect(cvt['TEMPS_ENABLED__C']).to eql 'FALSE'
    end

    it "reports GREEN with no limits state when no member is enabled" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      limits_event({ type: :LIMITS_GROUP_ENABLE_STATE, group_name: 'TEMPS', enabled: false, time_nsec: 0, message: 'test' })
      expect(cvt['TEMPS__C']).to eql 'GREEN'
      expect(cvt).to_not have_key('TEMPS__L')
      expect(cvt['TEMPS_ENABLED__C']).to eql 'FALSE'
    end

    it "ignores unknown members and warns once" do
      warnings = []
      allow_any_instance_of(Logger).to receive(:warn) { |_logger, message| warnings << message }
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1), %w(INST HEALTH_STATUS NOPE), %w(NOPE PKT ITEM)] })
      change('TEMP1', 'RED')
      @microservice.reload
      expect(cvt['TEMPS__C']).to eql 'RED'
      expect(cvt['TEMPS_ENABLED__C']).to eql 'TRUE'
      expect(warnings).to eql [
        "LIMITS_GROUP TEMPS member INST HEALTH_STATUS NOPE does not exist or has no limits. Ignoring it.",
        "LIMITS_GROUP TEMPS member NOPE PKT ITEM does not exist or has no limits. Ignoring it.",
      ]
    end

    it "rolls nested groups up to the top in one publish" do
      start({ 'SPACECRAFT' => [%w(COSMOS LIMITS_GROUP THERMAL), %w(INST HEALTH_STATUS TEMP3)],
              'THERMAL' => [%w(INST HEALTH_STATUS TEMP1), %w(INST HEALTH_STATUS TEMP2)] })
      change('TEMP1', 'RED')
      expect(cvt['THERMAL__C']).to eql 'RED'
      expect(cvt['SPACECRAFT__C']).to eql 'RED'
      expect(publishes).to eql 2

      # A disabled item below a child shows up at the top
      limits_event({ type: :LIMITS_ENABLE_STATE, target_name: 'INST', packet_name: 'HEALTH_STATUS', item_name: 'TEMP2',
                     enabled: false, time_nsec: 0, message: 'test' })
      expect(cvt['THERMAL_ENABLED__C']).to eql 'FALSE'
      expect(cvt['SPACECRAFT_ENABLED__C']).to eql 'FALSE'
    end

    it "counts a child installed after its parent" do
      start({ 'SPACECRAFT' => [%w(COSMOS LIMITS_GROUP THERMAL), %w(INST HEALTH_STATUS TEMP3)] })
      change('TEMP1', 'RED')
      expect(cvt['SPACECRAFT__C']).to eql 'GREEN'
      store_groups({ 'SPACECRAFT' => [%w(COSMOS LIMITS_GROUP THERMAL), %w(INST HEALTH_STATUS TEMP3)],
                     'THERMAL' => [%w(INST HEALTH_STATUS TEMP1)] })
      @microservice.reload
      @microservice.publish
      expect(cvt['THERMAL__C']).to eql 'RED'
      expect(cvt['SPACECRAFT__C']).to eql 'RED'
    end

    it "publishes the first group within one reload and drops removed groups" do
      @microservice.reload
      @microservice.publish(force: true)
      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      @microservice.reload
      @microservice.publish
      expect(publishes).to eql 1
      expect(cvt).to have_key('TEMPS')

      # A member target uninstalled clears current_limits and the group keeps publishing
      Store.hdel("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP1")
      store_groups({})
      @microservice.reload
      @microservice.publish
      expect(publishes).to eql 2
      expect(cvt).to_not have_key('TEMPS')
    end

    it "survives a stored cycle" do
      start({ 'A' => [%w(COSMOS LIMITS_GROUP B), %w(INST HEALTH_STATUS TEMP1)], 'B' => [%w(COSMOS LIMITS_GROUP A)] })
      change('TEMP1', 'RED')
      expect(cvt['A__C']).to eql 'RED'
    end

    it "runs until shutdown" do
      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      stub_const("OpenC3::LimitsGroupMicroservice::READ_TIMEOUT_MS", 10)
      thread = Thread.new { @microservice.run }
      sleep 0.2
      @microservice.shutdown
      thread.join(5)
      expect(thread.alive?).to be false
      expect(publishes).to eql 1
    end
  end
end
