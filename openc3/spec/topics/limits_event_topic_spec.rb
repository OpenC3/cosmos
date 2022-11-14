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
        puts out
        expect(out.length).to eql 1
        expect(out[0][0]).to eql "TGT"
        expect(out[0][1]).to eql "PKT"
        expect(out[0][2]).to eql "ITEM"
        expect(out[0][3]).to eql "YELLOW_LOW"
      end
    end

    describe "self.delete" do
      it "removes all items from the out_of_limits list" do
        event = { type: :LIMITS_CHANGE, target_name: "TGT1", packet_name: "PKT1",
            item_name: "ITEM1", old_limits_state: :GREEN, new_limits_state: :YELLOW_LOW,
            time_nsec: 123456789, message: "test change" }
        LimitsEventTopic.write(event, scope: "DEFAULT")
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
        LimitsEventTopic.delete("TGT1", "PKT2", scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 2
        LimitsEventTopic.delete("TGT2", "PKT1", scope: "DEFAULT")
        out = LimitsEventTopic.out_of_limits(scope: "DEFAULT")
        expect(out.length).to eql 0
      end
    end
  end
end
