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

module OpenC3
  # Reduces item limits states to a single color. Shared by
  # get_overall_limits_state and the limits group rollup so they rank
  # states the same way. Keep in sync with python/openc3/utilities/limits_rollup.py
  module LimitsRollup
    COLORS = {
      'RED' => 'RED', 'RED_HIGH' => 'RED', 'RED_LOW' => 'RED',
      'YELLOW' => 'YELLOW', 'YELLOW_HIGH' => 'YELLOW', 'YELLOW_LOW' => 'YELLOW',
      'GREEN' => 'GREEN', 'GREEN_HIGH' => 'GREEN', 'GREEN_LOW' => 'GREEN', 'BLUE' => 'GREEN',
    }.freeze
    SEVERITY = { 'GREEN' => 0, 'YELLOW' => 1, 'RED' => 2 }.freeze

    # @param state [String, nil] An item limits state such as RED_HIGH or BLUE
    # @return [String, nil] 'GREEN', 'YELLOW' or 'RED', or nil for a missing or unknown state
    def self.color(state)
      COLORS[state]
    end

    # @param states [Array<String, nil>] Item limits states
    # @return [String, nil] The most severe color, or nil if no state counts
    def self.worst(states)
      states.map { |state| color(state) }.compact.max_by { |color| SEVERITY[color] }
    end

    # Roll up a limits group from its members.
    #
    # Members with limits disabled are ignored for the color, as are missing states.
    # The group is enabled only when it has members and every one is enabled.
    #
    # @param members [Array<Array(String|nil, Boolean)>] [limits_state, enabled] per member
    # @return [Array(String|nil, Boolean)] [color, enabled] where color is nil
    #   when no enabled member has a state
    def self.rollup(members)
      states = members.select { |_state, enabled| enabled }.map { |state, _enabled| state }
      enabled = !members.empty? && members.all? { |_state, member_enabled| member_enabled }
      return [worst(states), enabled]
    end
  end
end
