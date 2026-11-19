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
      'GREEN' => 'GREEN', 'GREEN_HIGH' => 'GREEN', 'GREEN_LOW' => 'GREEN',
      'BLUE' => 'BLUE',
    }.freeze
    # BLUE ranks below GREEN so a rollup is only BLUE when every state is BLUE
    SEVERITY = { 'BLUE' => -1, 'GREEN' => 0, 'YELLOW' => 1, 'RED' => 2 }.freeze
    # A group whose members all have limits disabled
    DISABLED = 'DISABLED'.freeze
    # Whether limits are enabled on a group's members: all, none, or some of them
    ENABLED_TRUE = 'TRUE'.freeze
    ENABLED_FALSE = 'FALSE'.freeze
    ENABLED_PARTIAL = 'PARTIAL'.freeze

    # @param state [String, nil] An item limits state such as RED_HIGH or BLUE
    # @return [String, nil] 'BLUE', 'GREEN', 'YELLOW' or 'RED', or nil for a missing or unknown state
    def self.color(state)
      COLORS[state]
    end

    # @param states [Array<String, nil>] Item limits states
    # @return [String, nil] The most severe color, or nil if no state counts
    def self.worst(states)
      states.map { |state| color(state) }.compact.max_by { |color| SEVERITY[color] }
    end

    # @param enabled [Boolean, String] true or false for an item, or
    #   ENABLED_TRUE, ENABLED_FALSE or ENABLED_PARTIAL for a nested group
    # @return [String] ENABLED_TRUE, ENABLED_FALSE or ENABLED_PARTIAL
    def self.enabled_state(enabled)
      case enabled
      when true then ENABLED_TRUE
      when false, nil then ENABLED_FALSE
      else enabled
      end
    end

    # Roll up a limits group from its members.
    #
    # The group is enabled (ENABLED_TRUE) when every member is, disabled
    # (ENABLED_FALSE) when no member is or the group is empty, and otherwise
    # ENABLED_PARTIAL. A disabled group's state is DISABLED. Otherwise it's the
    # most severe state of the members which aren't disabled, ignoring missing states.
    #
    # @param members [Array<Array(String|nil, Boolean|String)>] [limits_state, enabled]
    #   per member. Items pass true or false for enabled, nested groups pass
    #   their rolled up [state, enabled].
    # @return [Array(String|nil, String)] [state, enabled] where state is nil
    #   when no member which counts has a state
    def self.rollup(members)
      members = members.map { |state, enabled| [state, enabled_state(enabled)] }
      enabled_states = members.map { |_state, enabled| enabled }.uniq
      if enabled_states.empty? or enabled_states == [ENABLED_FALSE]
        return [DISABLED, ENABLED_FALSE]
      end

      enabled = enabled_states == [ENABLED_TRUE] ? ENABLED_TRUE : ENABLED_PARTIAL
      states = members.reject { |_state, member_enabled| member_enabled == ENABLED_FALSE }.map { |state, _enabled| state }
      return [worst(states), enabled]
    end
  end
end
