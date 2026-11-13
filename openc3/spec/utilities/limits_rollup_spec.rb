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

      it "maps GREEN states and BLUE to GREEN" do
        %w(GREEN GREEN_HIGH GREEN_LOW BLUE).each { |state| expect(LimitsRollup.color(state)).to eql 'GREEN' }
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
        expect(LimitsRollup.rollup([['GREEN', true], ['YELLOW_LOW', true]])).to eql ['YELLOW', true]
        expect(LimitsRollup.rollup([['RED_HIGH', true], ['YELLOW_LOW', true]])).to eql ['RED', true]
        expect(LimitsRollup.rollup([['BLUE', true], ['GREEN_HIGH', true]])).to eql ['GREEN', true]
      end

      it "ignores members with limits disabled and reports the group not enabled" do
        expect(LimitsRollup.rollup([['RED', false], ['GREEN', true]])).to eql ['GREEN', false]
      end

      it "ignores missing states on enabled members" do
        expect(LimitsRollup.rollup([[nil, true], ['YELLOW', true]])).to eql ['YELLOW', true]
      end

      it "has no color when enabled members have no state yet" do
        expect(LimitsRollup.rollup([[nil, true]])).to eql [nil, true]
      end

      it "has no color and is not enabled with no enabled members" do
        expect(LimitsRollup.rollup([['RED', false], ['YELLOW', false]])).to eql [nil, false]
      end

      it "has no color and is not enabled when the group is empty" do
        expect(LimitsRollup.rollup([])).to eql [nil, false]
      end
    end
  end
end
