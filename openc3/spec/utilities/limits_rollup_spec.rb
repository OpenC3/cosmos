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
require 'openc3/utilities/limits_rollup'

module OpenC3
  describe LimitsRollup do
    describe "color" do
      it "maps every RED state to RED" do
        %w(RED RED_HIGH RED_LOW).each { |state| expect(LimitsRollup.color(state)).to eql 'RED' }
      end

      it "maps every YELLOW state to YELLOW" do
        %w(YELLOW YELLOW_HIGH YELLOW_LOW).each { |state| expect(LimitsRollup.color(state)).to eql 'YELLOW' }
      end

      it "maps every GREEN state to GREEN" do
        %w(GREEN GREEN_HIGH GREEN_LOW).each { |state| expect(LimitsRollup.color(state)).to eql 'GREEN' }
      end

      it "keeps BLUE" do
        expect(LimitsRollup.color('BLUE')).to eql 'BLUE'
      end

      it "returns nil for a missing or unknown state" do
        expect(LimitsRollup.color(nil)).to be_nil
        expect(LimitsRollup.color('STALE')).to be_nil
      end
    end

    describe "worst" do
      it "returns the most severe color" do
        expect(LimitsRollup.worst(%w(GREEN BLUE))).to eql 'GREEN'
        expect(LimitsRollup.worst(%w(GREEN_HIGH YELLOW_LOW BLUE))).to eql 'YELLOW'
        expect(LimitsRollup.worst(%w(YELLOW_HIGH RED_LOW GREEN))).to eql 'RED'
        expect(LimitsRollup.worst(%w(RED_HIGH YELLOW))).to eql 'RED'
      end

      it "is BLUE only when every state is BLUE" do
        expect(LimitsRollup.worst(%w(BLUE BLUE))).to eql 'BLUE'
        expect(LimitsRollup.worst(['BLUE', nil])).to eql 'BLUE'
        expect(LimitsRollup.worst(%w(BLUE GREEN_LOW))).to eql 'GREEN'
      end

      it "ignores missing states" do
        expect(LimitsRollup.worst([nil, 'YELLOW_HIGH', nil])).to eql 'YELLOW'
      end

      it "returns nil when no state counts" do
        expect(LimitsRollup.worst([])).to be_nil
        expect(LimitsRollup.worst([nil])).to be_nil
      end
    end

    describe "rollup" do
      it "rolls up an all-enabled group" do
        expect(LimitsRollup.rollup([['GREEN', true], ['YELLOW_LOW', true]])).to eql ['YELLOW', 'TRUE']
        expect(LimitsRollup.rollup([['RED_HIGH', true], ['YELLOW_LOW', true]])).to eql ['RED', 'TRUE']
        expect(LimitsRollup.rollup([['BLUE', true], ['GREEN_HIGH', true]])).to eql ['GREEN', 'TRUE']
      end

      it "is BLUE when every member is BLUE" do
        expect(LimitsRollup.rollup([['BLUE', true], ['BLUE', true]])).to eql ['BLUE', 'TRUE']
        # A disabled member doesn't count
        expect(LimitsRollup.rollup([['BLUE', true], ['GREEN', false]])).to eql ['BLUE', 'PARTIAL']
        # A BLUE nested group
        expect(LimitsRollup.rollup([['BLUE', 'TRUE'], ['BLUE', true]])).to eql ['BLUE', 'TRUE']
      end

      it "ignores members with limits disabled and reports the group PARTIAL" do
        expect(LimitsRollup.rollup([['RED', false], ['GREEN', true]])).to eql ['GREEN', 'PARTIAL']
      end

      it "ignores missing states on enabled members" do
        expect(LimitsRollup.rollup([[nil, true], ['YELLOW', true]])).to eql ['YELLOW', 'TRUE']
      end

      it "has no color when enabled members have no state yet" do
        expect(LimitsRollup.rollup([[nil, true]])).to eql [nil, 'TRUE']
      end

      it "is DISABLED with no enabled members" do
        expect(LimitsRollup.rollup([['RED', false], ['YELLOW', false]])).to eql ['DISABLED', 'FALSE']
      end

      it "is DISABLED when the group is empty" do
        expect(LimitsRollup.rollup([])).to eql ['DISABLED', 'FALSE']
      end

      it "ignores a disabled nested group and reports the group PARTIAL" do
        expect(LimitsRollup.rollup([['DISABLED', 'FALSE'], ['YELLOW', true]])).to eql ['YELLOW', 'PARTIAL']
      end

      it "counts a partly enabled nested group and reports the group PARTIAL" do
        expect(LimitsRollup.rollup([['RED', 'PARTIAL'], ['GREEN', true]])).to eql ['RED', 'PARTIAL']
        expect(LimitsRollup.rollup([['RED', 'PARTIAL']])).to eql ['RED', 'PARTIAL']
      end

      it "is DISABLED when every nested group is disabled" do
        expect(LimitsRollup.rollup([['DISABLED', 'FALSE'], ['DISABLED', 'FALSE']])).to eql ['DISABLED', 'FALSE']
        expect(LimitsRollup.rollup([['DISABLED', 'FALSE'], ['GREEN', false]])).to eql ['DISABLED', 'FALSE']
      end
    end
  end
end
