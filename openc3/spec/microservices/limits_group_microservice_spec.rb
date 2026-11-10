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
    before(:each) do
      mock_redis()
      setup_system()
      # Members and INST LIMITS_GROUP on db_shard 1 and INST2 LIMITS_GROUP on db_shard 2
      setup_target_db_shards({ 'INST' => 1 })
      TargetModel.new(name: 'INST2', scope: 'DEFAULT', db_shard: 2).create
      Store.del("DEFAULT__limits_groups")
      allow_any_instance_of(OpenC3::Microservice).to receive(:at_exit)
      @microservice = LimitsGroupMicroservice.new("DEFAULT__LIMITSGROUP__DEFAULT")
    end

    after(:each) do
      @microservice.shutdown
    end

    # @param groups [Hash] Groups keyed by TARGET__GROUP or by GROUP for INST groups
    def store_groups(groups)
      Store.del("DEFAULT__limits_groups")
      groups.each do |group, items|
        group = "INST__#{group}" unless group.include?('__')
        Store.hset("DEFAULT__limits_groups", group, JSON.generate(items))
      end
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

    DB_SHARDS = { 'INST' => 1, 'INST2' => 2 }

    def cvt(target_name = 'INST')
      json = Store.instance(db_shard: DB_SHARDS[target_name]).hget("DEFAULT__tlm__#{target_name}", "LIMITS_GROUP")
      json ? JSON.parse(json) : nil
    end

    def publishes(target_name = 'INST')
      EphemeralStore.instance(db_shard: DB_SHARDS[target_name]).xrevrange("DEFAULT__DECOM__{#{target_name}}__LIMITS_GROUP", count: 100).length
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

    it "reads limits on db_shard 0 and writes each packet on its target's db_shard" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)], 'INST2__TEMPS' => [%w(INST HEALTH_STATUS TEMP2)] })
      expect(Store).to receive(:hget).with("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP1").and_call_original
      expect(Store).to receive(:hget).with("DEFAULT__current_limits_settings", "INST__HEALTH_STATUS__TEMP1").and_call_original
      change('TEMP1', 'RED')
      expect(cvt['TEMPS__C']).to eql 'RED'
      expect(cvt('INST2')['TEMPS__C']).to eql 'GREEN'
      expect(Store.instance(db_shard: 0).hexists("DEFAULT__tlm__INST", "LIMITS_GROUP")).to be false
      expect(Store.instance(db_shard: 0).hexists("DEFAULT__tlm__INST2", "LIMITS_GROUP")).to be false
      expect(EphemeralStore.instance(db_shard: 0).exists("DEFAULT__DECOM__{INST}__LIMITS_GROUP")).to eql 0
      expect(EphemeralStore.instance(db_shard: 0).exists("DEFAULT__DECOM__{INST2}__LIMITS_GROUP")).to eql 0
    end

    it "keeps groups with the same name in different targets apart and only publishes the target that changed" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)], 'INST2__TEMPS' => [%w(INST HEALTH_STATUS TEMP2)] })
      expect(publishes('INST')).to eql 1
      expect(publishes('INST2')).to eql 1
      change('TEMP2', 'YELLOW_LOW')
      expect(cvt('INST2')['TEMPS__C']).to eql 'YELLOW'
      expect(cvt('INST')['TEMPS__C']).to eql 'GREEN'
      expect(publishes('INST')).to eql 1
      expect(publishes('INST2')).to eql 2
      expect(cvt('INST2')['RECEIVED_COUNT']).to eql 2
    end

    it "never raises limits events or changes the overall limits state" do
      start({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      change('TEMP1', 'YELLOW')
      expect(Store.hkeys("DEFAULT__current_limits")).to_not include(a_string_including("LIMITS_GROUP"))
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
        "LIMITS_GROUP INST TEMPS member INST HEALTH_STATUS NOPE does not exist or has no limits. Ignoring it.",
        "LIMITS_GROUP INST TEMPS member NOPE PKT ITEM does not exist or has no limits. Ignoring it.",
      ]
    end

    it "rolls nested groups up to the top in one publish" do
      start({ 'SPACECRAFT' => [%w(INST LIMITS_GROUP THERMAL), %w(INST HEALTH_STATUS TEMP3)],
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
      start({ 'SPACECRAFT' => [%w(INST2 LIMITS_GROUP THERMAL), %w(INST HEALTH_STATUS TEMP3)] })
      change('TEMP1', 'RED')
      expect(cvt['SPACECRAFT__C']).to eql 'GREEN'
      store_groups({ 'SPACECRAFT' => [%w(INST2 LIMITS_GROUP THERMAL), %w(INST HEALTH_STATUS TEMP3)],
                     'INST2__THERMAL' => [%w(INST HEALTH_STATUS TEMP1)] })
      @microservice.reload
      @microservice.publish
      expect(cvt('INST2')['THERMAL__C']).to eql 'RED'
      expect(cvt['SPACECRAFT__C']).to eql 'RED'
    end

    it "rolls up a nested group of another target, not one with the same name" do
      start({ 'SPACECRAFT' => [%w(INST2 LIMITS_GROUP THERMAL)],
              'THERMAL' => [%w(INST HEALTH_STATUS TEMP1)],
              'INST2__THERMAL' => [%w(INST HEALTH_STATUS TEMP2)] })
      change('TEMP1', 'RED')
      expect(cvt['SPACECRAFT__C']).to eql 'GREEN'
      change('TEMP2', 'YELLOW')
      expect(cvt['SPACECRAFT__C']).to eql 'YELLOW'
    end

    it "publishes the first group within one reload and drops removed groups" do
      @microservice.reload
      @microservice.publish(force: true)
      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)], 'POWER' => [%w(INST HEALTH_STATUS TEMP2)] })
      @microservice.reload
      @microservice.publish
      expect(publishes).to eql 1
      expect(cvt).to have_key('TEMPS')

      # A member target uninstalled clears current_limits and the group keeps publishing
      Store.hdel("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP1")
      store_groups({ 'POWER' => [%w(INST HEALTH_STATUS TEMP2)] })
      @microservice.reload
      @microservice.publish
      expect(publishes).to eql 2
      expect(cvt).to_not have_key('TEMPS')

      # A target with no groups left has no packet to publish
      store_groups({})
      @microservice.reload
      @microservice.publish
      expect(publishes).to eql 2
    end

    it "skips groups stored before groups were owned by a target" do
      Store.hset("DEFAULT__limits_groups", "LEGACY", JSON.generate([%w(INST HEALTH_STATUS TEMP1)]))
      @microservice.reload
      @microservice.publish(force: true)
      expect(@microservice.values).to have_key("LEGACY")
      expect(cvt).to be_nil
    end

    it "survives a stored cycle" do
      start({ 'A' => [%w(INST LIMITS_GROUP B), %w(INST HEALTH_STATUS TEMP1)], 'B' => [%w(INST LIMITS_GROUP A)] })
      change('TEMP1', 'RED')
      expect(cvt['A__C']).to eql 'RED'
    end

    it "parses each packet definition once until its target changes" do
      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1), %w(INST HEALTH_STATUS TEMP2)] })
      # Members' definitions are read from their target's db_shard
      store = Store.instance(db_shard: 1)
      allow(Store).to receive(:instance).and_call_original
      expect(Store).to receive(:instance).with(db_shard: 1).at_least(:once).and_call_original
      expect(store).to receive(:hget).with("DEFAULT__openc3tlm__INST", "HEALTH_STATUS").twice.and_call_original
      @microservice.reload
      @microservice.reload
      @microservice.reload(changed_targets: ['INST2'])
      @microservice.reload(changed_targets: ['INST'])
    end

    it "rereads a target installed after a group which contains its items" do
      warnings = []
      allow_any_instance_of(Logger).to receive(:warn) { |_logger, message| warnings << message }
      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1), %w(INST3 HEALTH_STATUS TEMP1)] })
      @microservice.reload
      expect(warnings.length).to eql 1

      # INST3 is installed on db_shard 3 after we looked it up
      TargetModel.new(name: 'INST3', scope: 'DEFAULT', db_shard: 3).create
      Store.instance(db_shard: 3).hset("DEFAULT__openc3tlm__INST3", "HEALTH_STATUS",
                                       Store.instance(db_shard: 1).hget("DEFAULT__openc3tlm__INST", "HEALTH_STATUS"))
      Store.hset("DEFAULT__current_limits", "INST3__HEALTH_STATUS__TEMP1", "RED")
      allow(Store).to receive(:instance).and_call_original
      expect(Store).to receive(:instance).with(db_shard: 3).at_least(:once).and_call_original
      @microservice.reload(changed_targets: ['INST3'])
      @microservice.publish
      expect(cvt['TEMPS__C']).to eql 'RED'
    end

    it "reloads when a target is installed or removed, not on a timer" do
      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      stub_const("OpenC3::LimitsGroupMicroservice::READ_TIMEOUT_MS", 10)
      reloads = []
      allow(@microservice).to receive(:reload).and_wrap_original do |method, **kwargs|
        reloads << kwargs
        method.call(**kwargs)
      end
      thread = Thread.new { @microservice.run }
      sleep 0.2
      expect(reloads).to eql [{}]

      # Other config changes are ignored
      ConfigTopic.write({ kind: 'created', type: 'microservice', name: 'DEFAULT__USER__INST' }, scope: 'DEFAULT')
      sleep 0.2
      expect(reloads).to eql [{}]

      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)], 'POWER' => [%w(INST HEALTH_STATUS TEMP2)] })
      ConfigTopic.write({ kind: 'created', type: 'target', name: 'INST' }, scope: 'DEFAULT')
      sleep 0.2
      @microservice.shutdown
      thread.join(5)
      expect(reloads).to eql [{}, { changed_targets: ['INST'] }]
      expect(cvt).to have_key('POWER')
      expect(publishes).to eql 2
    end

    it "reloads after an error in case events were missed" do
      store_groups({ 'TEMPS' => [%w(INST HEALTH_STATUS TEMP1)] })
      stub_const("OpenC3::LimitsGroupMicroservice::READ_TIMEOUT_MS", 10)
      allow(@microservice).to receive(:sleep)
      allow_any_instance_of(Logger).to receive(:error)
      calls = 0
      allow(Topic).to receive(:read_topics).and_wrap_original do |method, *args, &block|
        calls += 1
        if calls == 1
          # A limits change whose event never arrives
          Store.hset("DEFAULT__current_limits", "INST__HEALTH_STATUS__TEMP1", "RED")
          raise "lost connection"
        end
        method.call(*args, &block)
      end
      thread = Thread.new { @microservice.run }
      sleep 0.2
      @microservice.shutdown
      thread.join(5)
      expect(cvt['TEMPS__C']).to eql 'RED'
      expect(publishes).to eql 2
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
