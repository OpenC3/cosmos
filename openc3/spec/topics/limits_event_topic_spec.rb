# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'spec_helper'
require 'openc3/topics/limits_event_topic'

module OpenC3
  describe LimitsEventTopic do
    before(:each) do
      mock_redis()
      setup_system()
    end

    describe "self.write, self.read" do
      it "writes and reads LIMITS_CHANGE events" do
        event = { type: :LIMITS_CHANGE, target_name: "TGT", packet_name: "PKT",
            item_name: "ITEM", old_limits_state: :GREEN, new_limits_state: :YELLOW_LOW,
            time_nsec: 123456789, message: "test change" }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        events = LimitsEventTopic.read(scope: "DEFAULT")
        expect(events.length).to eql 1
        expect(events[0][0]).to match(/\d+-0/) # ID
        expect(events[0][1]['type']).to eql "LIMITS_CHANGE"

        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 1
        expect(out[0][0]).to eql "TGT"
        expect(out[0][1]).to eql "PKT"
        expect(out[0][2]).to eql "ITEM"
        expect(out[0][3]).to eql "YELLOW_LOW"
      end

      it "writes and reads LIMITS_SETTINGS events" do
        event = { type: :LIMITS_SETTINGS, limits_set: :DEFAULT, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", red_low: -50.0, yellow_low: -40.0, yellow_high: 40.0, red_high: 50.0,
            persistence: 1 }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event = { type: :LIMITS_SETTINGS, limits_set: :DEFAULT, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", red_low: -50.0, yellow_low: -40.0, yellow_high: 40.0, red_high: 50.0,
            green_low: -10.0, green_high: 10.0,  persistence: 5 }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        sleep 0.1
        events = LimitsEventTopic.read("0-0", scope: "DEFAULT")
        expect(events.length).to eql 2

        expect(events[0][1]["type"]).to eql "LIMITS_SETTINGS"
        expect(events[0][1]["target_name"]).to eql "TGT1"
        expect(events[0][1]["packet_name"]).to eql "PKT1"
        expect(events[0][1]["item_name"]).to eql "ITEM1"
        expect(events[0][1]["red_low"]).to eql(-50.0)
        expect(events[0][1]["yellow_low"]).to eql(-40.0)
        expect(events[0][1]["yellow_high"]).to eql 40.0
        expect(events[0][1]["red_high"]).to eql 50.0
        expect(events[0][1]["green_low"]).to be nil
        expect(events[0][1]["green_high"]).to be nil
        expect(events[0][1]["persistence"]).to eql 1

        expect(events[1][1]["type"]).to eql "LIMITS_SETTINGS"
        expect(events[1][1]["target_name"]).to eql "TGT1"
        expect(events[1][1]["packet_name"]).to eql "PKT1"
        expect(events[1][1]["item_name"]).to eql "ITEM1"
        expect(events[1][1]["red_low"]).to eql(-50.0)
        expect(events[1][1]["yellow_low"]).to eql(-40.0)
        expect(events[1][1]["yellow_high"]).to eql 40.0
        expect(events[1][1]["red_high"]).to eql 50.0
        expect(events[1][1]["green_low"]).to be(-10.0)
        expect(events[1][1]["green_high"]).to be 10.0
        expect(events[1][1]["persistence"]).to eql 5
      end

      it "writes and reads LIMITS_EVENT_STATE" do
        event = { type: :LIMITS_ENABLE_STATE, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", enabled: true, time_nsec: Time.now.to_nsec_from_epoch, message: "TEST1" }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event = { type: :LIMITS_ENABLE_STATE, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", enabled: false, time_nsec: Time.now.to_nsec_from_epoch, message: "TEST2" }
        LimitsEventTopic.write(event, scope: "DEFAULT")

        events = LimitsEventTopic.read("0-0", scope: "DEFAULT")
        expect(events.length).to eql 2

        expect(events[0][1]["type"]).to eql "LIMITS_ENABLE_STATE"
        expect(events[0][1]["target_name"]).to eql "TGT1"
        expect(events[0][1]["packet_name"]).to eql "PKT1"
        expect(events[0][1]["item_name"]).to eql "ITEM1"
        expect(events[0][1]["enabled"]).to eql true
        expect(events[0][1]["message"]).to eql "TEST1"

        expect(events[1][1]["type"]).to eql "LIMITS_ENABLE_STATE"
        expect(events[1][1]["target_name"]).to eql "TGT1"
        expect(events[1][1]["packet_name"]).to eql "PKT1"
        expect(events[1][1]["item_name"]).to eql "ITEM1"
        expect(events[1][1]["enabled"]).to eql false
        expect(events[1][1]["message"]).to eql "TEST2"
      end

      it "writes and reads LIMITS_SET" do
        sets = LimitsEventTopic.sets(scope: "DEFAULT")
        expect(sets).to eql({})

        event = { type: :LIMITS_SETTINGS, limits_set: "TVAC", target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", red_low: -50.0, yellow_low: -40.0, yellow_high: 40.0, red_high: 50.0,
            persistence: 1 }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        LimitsEventTopic.write({ type: :LIMITS_SET, set: "TVAC",
            time_nsec: Time.now.to_nsec_from_epoch, message: "Limits Set" }, scope: "DEFAULT")

            events = LimitsEventTopic.read(scope: "DEFAULT")
        expect(events.length).to eql 1
        expect(events[0][1]["type"]).to eql "LIMITS_SET"
        expect(events[0][1]["message"]).to eql "Limits Set"

        sets = LimitsEventTopic.sets(scope: "DEFAULT")
        expect(sets).to eql({"TVAC" => "true"})
      end

      it "raises on LIMITS_SET when set does not exist" do
        expect {
          LimitsEventTopic.write({ type: :LIMITS_SET, set: "TVAC",
              time_nsec: Time.now.to_nsec_from_epoch, message: "Limits Set" }, scope: "DEFAULT")
        }.to raise_error(RuntimeError, "Set 'TVAC' does not exist!")
      end
    end

    describe "self.delete" do
      it "removes individual items from the out_of_limits list" do
        # Create a LIMITS_SETTINGS event so the delete will clear that too
        event = { type: :LIMITS_SETTINGS, limits_set: :DEFAULT, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", red_low: -50.0, yellow_low: -40.0, yellow_high: 40.0, red_high: 50.0 }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event = { type: :LIMITS_CHANGE, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", old_limits_state: :GREEN, new_limits_state: :YELLOW_LOW,
            time_nsec: 123456789, message: "test change" }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        settings = Store.hgetall("DEFAULT__current_limits_settings")
        expect(settings.keys).to eql ["TGT1__PKT1__ITEM1"]

        event[:packet_name] = "PKT2"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event[:item_name] = "ITEM2"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event[:target_name] = "TGT2"
        event[:packet_name] = "PKT1"
        event[:item_name] = "ITEM1"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event[:item_name] = "ITEM2"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 5
        LimitsEventTopic.delete("TGT1", "PKT1", scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 4
        settings = Store.hgetall("DEFAULT__current_limits_settings")
        expect(settings).to eql({}) # deleted

        LimitsEventTopic.delete("TGT1", "PKT2", scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 2
        LimitsEventTopic.delete("TGT2", "PKT1", scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 0
      end

      it "removes all items from the out_of_limits list" do
        # Create a LIMITS_SETTINGS event so the delete will clear that too
        event = { type: :LIMITS_SETTINGS, limits_set: :DEFAULT, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", red_low: -50.0, yellow_low: -40.0, yellow_high: 40.0, red_high: 50.0 }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event = { type: :LIMITS_CHANGE, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", old_limits_state: :GREEN, new_limits_state: :YELLOW_LOW,
            time_nsec: 123456789, message: "test change" }
        LimitsEventTopic.write(event, scope: "DEFAULT")
        settings = Store.hgetall("DEFAULT__current_limits_settings")
        expect(settings.keys).to eql ["TGT1__PKT1__ITEM1"]

        event[:packet_name] = "PKT2"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event[:item_name] = "ITEM2"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event[:target_name] = "TGT2"
        event[:packet_name] = "PKT1"
        event[:item_name] = "ITEM1"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        event[:item_name] = "ITEM2"
        LimitsEventTopic.write(event, scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 5
        LimitsEventTopic.delete("TGT1", scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 2
        settings = Store.hgetall("DEFAULT__current_limits_settings")
        expect(settings).to eql({}) # deleted

        LimitsEventTopic.delete("TGT2", scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 0
      end
    end

    describe "self.sync_system" do
      it "syncs our system with an event" do
        # event = { type: :LIMITS_ENABLE_STATE, target_name: "INST", packet_name: "HEALTH_STATUS",
        #     item_name: "TEMP1", enabled: true, time_nsec: Time.now.to_nsec_from_epoch, message: "TEST1" }
        # LimitsEventTopic.write(event, scope: "DEFAULT")

        limits_settings = {}
        limits_settings["enabled"] = false
        Store.hset(
            "DEFAULT__current_limits_settings",
            "INST__HEALTH_STATUS__TEMP1",
            JSON.generate(limits_settings),
        )

        expect(System.limits.enabled?("INST", "HEALTH_STATUS", "TEMP1")).to be true
        LimitsEventTopic.sync_system(scope: "DEFAULT")
        expect(System.limits.enabled?("INST", "HEALTH_STATUS", "TEMP1")).to be false

        limits_settings["enabled"] = true
        Store.hset(
            "DEFAULT__current_limits_settings",
            "INST__HEALTH_STATUS__TEMP1",
            JSON.generate(limits_settings),
        )
        LimitsEventTopic.sync_system(scope: "DEFAULT")
        expect(System.limits.enabled?("INST", "HEALTH_STATUS", "TEMP1")).to be true

        limits = System.limits.get("INST", "HEALTH_STATUS", "TEMP1")
        expect(limits[0]).to eql :DEFAULT
        expect(limits[1]).to eql 1
        expect(limits[2]).to eql true
        expect(limits[3]).to eql(-80.0)
        expect(limits[4]).to eql(-70.0)
        expect(limits[5]).to eql 60.0
        expect(limits[6]).to eql 80.0
        expect(limits[7]).to eql(-20.0)
        expect(limits[8]).to eql 20.0

        limits = {}
        limits["red_low"] = -50.0
        limits["yellow_low"] = -40.0
        limits["yellow_high"] = 40.0
        limits["red_high"] = 50.0
        limits_settings["DEFAULT"] = limits
        limits_settings["persistence_setting"] = 5
        Store.hset(
            "DEFAULT__current_limits_settings",
            "INST__HEALTH_STATUS__TEMP1",
            JSON.generate(limits_settings),
        )
        LimitsEventTopic.sync_system(scope: "DEFAULT")
        limits = System.limits.get("INST", "HEALTH_STATUS", "TEMP1")
        expect(limits[0]).to eql :DEFAULT
        expect(limits[1]).to eql 5
        expect(limits[2]).to eql true
        expect(limits[3]).to eql(-50.0)
        expect(limits[4]).to eql(-40.0)
        expect(limits[5]).to eql 40.0
        expect(limits[6]).to eql 50.0
        expect(limits[7]).to be nil
        expect(limits[8]).to be nil
      end
    end
  end
end
