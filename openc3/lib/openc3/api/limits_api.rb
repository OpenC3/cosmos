# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/api/target_api'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'get_out_of_limits',
                       'get_overall_limits_state',
                       'limits_enabled?',
                       'enable_limits',
                       'disable_limits',
                       'get_limits',
                       'set_limits',
                       'get_limits_groups',
                       'enable_limits_group',
                       'disable_limits_group',
                       'get_limits_sets',
                       'set_limits_set',
                       'get_limits_set',
                       'get_limits_events',
                     ])

    # Return an array of arrays indicating all items in the packet that are out of limits
    #   [[target name, packet name, item name, item limits state], ...]
    #
    # @return [Array<Array<String, String, String, String>>]
    def get_out_of_limits(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', scope: scope, token: token)
      LimitsEventTopic.out_of_limits(scope: scope)
    end

    # Get the overall limits state which is the worse case of all limits items.
    # For example if any limits are YELLOW_LOW or YELLOW_HIGH then the overall limits state is YELLOW.
    # If a single limit item then turns RED_HIGH the overall limits state is RED.
    #
    # @param ignored_items [Array<Array<String, String, String|nil>>] Array of [TGT, PKT, ITEM] strings
    #   to ignore when determining overall state. Note, ITEM can be nil to indicate to ignore entire packet.
    # @return [String] The overall limits state for the system, one of 'GREEN', 'YELLOW', 'RED'
    def get_overall_limits_state(ignored_items = nil, scope: $openc3_scope, token: $openc3_token)
      # We only need to check out of limits items so call get_out_of_limits() which authorizes
      out_of_limits = get_out_of_limits(scope: scope, token: token)
      overall = 'GREEN'

      # Build easily matchable ignore list
      if ignored_items
        ignored_items.map! do |item|
          raise "Invalid ignored item: #{item}. Must be [TGT, PKT, ITEM] where ITEM can be nil." if item.length != 3

          item.join('__')
        end
      else
        ignored_items = []
      end

      out_of_limits.each do |target_name, packet_name, item_name, limits_state|
        # Ignore this item if we match one of the ignored items. Checking against /^#{item}/
        # allows us to detect matches against a TGT__PKT__ with no item defined.
        next if ignored_items.detect { |item| "#{target_name}__#{packet_name}__#{item_name}" =~ /^#{item}/ }

        if limits_state == 'RED' || limits_state == 'RED_HIGH' || limits_state == 'RED_LOW'
          overall = limits_state
          break # Red is as high as we go so no need to look for more
        end

        case overall
          # If our overall state is currently blue or green we can go to any state
        when 'BLUE', 'GREEN', 'GREEN_HIGH', 'GREEN_LOW'
          overall = limits_state
        # else YELLOW - Stay at YELLOW until we find a red
        end
      end
      overall = 'GREEN' if overall == 'GREEN_HIGH' || overall == 'GREEN_LOW' || overall == 'BLUE'
      overall = 'YELLOW' if overall == 'YELLOW_HIGH' || overall == 'YELLOW_LOW'
      overall = 'RED' if overall == 'RED_HIGH' || overall == 'RED_LOW'
      return overall
    end

    # Whether the limits are enabled for the given item
    #
    # Accepts two different calling styles:
    #   limits_enabled?("TGT PKT ITEM")
    #   limits_enabled?('TGT','PKT','ITEM')
    #
    # Favor the first syntax where possible as it is more succinct.
    #
    # @param args [String|Array<String>] See the description for calling style
    # @return [Boolean] Whether limits are enable for the itme
    def limits_enabled?(*args, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name = tlm_process_args(args, 'limits_enabled?', scope: scope)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, scope: scope, token: token)
      return TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)['limits']['enabled'] ? true : false
    end

    # Enable limits checking for a telemetry item
    #
    # Accepts two different calling styles:
    #   enable_limits("TGT PKT ITEM")
    #   enable_limits('TGT','PKT','ITEM')
    #
    # Favor the first syntax where possible as it is more succinct.
    #
    # @param args [String|Array<String>] See the description for calling style
    def enable_limits(*args, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name = tlm_process_args(args, 'enable_limits', scope: scope)
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, scope: scope, token: token)
      packet = TargetModel.packet(target_name, packet_name, scope: scope)
      found_item = nil
      packet['items'].each do |item|
        if item['name'] == item_name
          item['limits']['enabled'] = true
          found_item = item
          break
        end
      end
      raise "Item '#{target_name} #{packet_name} #{item_name}' does not exist" unless found_item

      TargetModel.set_packet(target_name, packet_name, packet, scope: scope)

      message = "Enabling Limits For '#{target_name} #{packet_name} #{item_name}'"
      Logger.info(message, scope: scope)

      event = { type: :LIMITS_ENABLE_STATE, target_name: target_name, packet_name: packet_name,
                item_name: item_name, enabled: true, time_nsec: Time.now.to_nsec_from_epoch, message: message }
      LimitsEventTopic.write(event, scope: scope)
    end

    # Disable limit checking for a telemetry item
    #
    # Accepts two different calling styles:
    #   disable_limits("TGT PKT ITEM")
    #   disable_limits('TGT','PKT','ITEM')
    #
    # Favor the first syntax where possible as it is more succinct.
    #
    # @param args [String|Array<String>] See the description for calling style
    def disable_limits(*args, scope: $openc3_scope, token: $openc3_token)
      target_name, packet_name, item_name = tlm_process_args(args, 'disable_limits', scope: scope)
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, scope: scope, token: token)
      packet = TargetModel.packet(target_name, packet_name, scope: scope)
      found_item = nil
      packet['items'].each do |item|
        if item['name'] == item_name
          item['limits'].delete('enabled')
          found_item = item
          break
        end
      end
      raise "Item '#{target_name} #{packet_name} #{item_name}' does not exist" unless found_item

      TargetModel.set_packet(target_name, packet_name, packet, scope: scope)

      message = "Disabling Limits For '#{target_name} #{packet_name} #{item_name}'"
      Logger.info(message, scope: scope)

      event = { type: :LIMITS_ENABLE_STATE, target_name: target_name, packet_name: packet_name,
                item_name: item_name, enabled: false, time_nsec: Time.now.to_nsec_from_epoch, message: message }
      LimitsEventTopic.write(event, scope: scope)
    end

    # Get a Hash of all the limits sets defined for an item. Hash keys are the limit
    # set name in uppercase (note there is always a DEFAULT) and the value is an array
    # of limit values: red low, yellow low, yellow high, red high, <green low, green high>.
    # Green low and green high are optional.
    #
    # For example: {'DEFAULT' => [-80, -70, 60, 80, -20, 20],
    #               'TVAC' => [-25, -10, 50, 55] }
    #
    # @return [Hash{String => Array<Number, Number, Number, Number, Number, Number>}]
    def get_limits(target_name, packet_name, item_name, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', target_name: target_name, packet_name: packet_name, scope: scope, token: token)
      limits = {}
      item = TargetModel.packet_item(target_name, packet_name, item_name, scope: scope)
      item['limits'].each do |key, vals|
        next unless vals.is_a?(Hash)

        limits[key] = [vals['red_low'], vals['yellow_low'], vals['yellow_high'], vals['red_high']]
        limits[key].concat([vals['green_low'], vals['green_high']]) if vals['green_low']
      end
      return limits
    end

    # Change the limits settings for a given item. By default, a new limits set called 'CUSTOM'
    # is created to avoid overriding existing limits.
    def set_limits(target_name, packet_name, item_name, red_low, yellow_low, yellow_high, red_high,
                   green_low = nil, green_high = nil, limits_set = 'CUSTOM', persistence = nil, enabled = true,
                   scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm_set', target_name: target_name, packet_name: packet_name, scope: scope, token: token)
      if (red_low > yellow_low) || (yellow_low >= yellow_high) || (yellow_high > red_high)
        raise "Invalid limits specified. Ensure yellow limits are within red limits."
      end
      if (green_low && green_high) && ((yellow_low > green_low) || (green_low >= green_high) || (green_high > yellow_high))
        raise "Invalid limits specified. Ensure green limits are within yellow limits."
      end
      packet = TargetModel.packet(target_name, packet_name, scope: scope)
      found_item = nil
      packet['items'].each do |item|
        if item['name'] == item_name
          if item['limits']
            item['limits']['persistence_setting'] = persistence if persistence
            if enabled
              item['limits']['enabled'] = true
            else
              item['limits'].delete('enabled')
            end
            limits = {}
            limits['red_low'] = red_low
            limits['yellow_low'] = yellow_low
            limits['yellow_high'] = yellow_high
            limits['red_high'] = red_high
            limits['green_low'] = green_low if green_low && green_high
            limits['green_high'] = green_high if green_low && green_high
            item['limits'][limits_set] = limits
            found_item = item
            break
          else
            raise "Cannot set_limits on item without any limits"
          end
        end
      end
      raise "Item '#{target_name} #{packet_name} #{item_name}' does not exist" unless found_item
      message = "Setting '#{target_name} #{packet_name} #{item_name}' limits to #{red_low} #{yellow_low} #{yellow_high} #{red_high}"
      message << " #{green_low} #{green_high}" if green_low && green_high
      message << " in set #{limits_set} with persistence #{persistence} as enabled #{enabled}"
      Logger.info(message, scope: scope)

      TargetModel.set_packet(target_name, packet_name, packet, scope: scope)

      event = { type: :LIMITS_SETTINGS, target_name: target_name, packet_name: packet_name,
                item_name: item_name, red_low: red_low, yellow_low: yellow_low, yellow_high: yellow_high, red_high: red_high,
                green_low: green_low, green_high: green_high, limits_set: limits_set, persistence: persistence, enabled: enabled,
                time_nsec: Time.now.to_nsec_from_epoch, message: message }
      LimitsEventTopic.write(event, scope: scope)
    end

    # Returns all limits_groups and their members
    # @since 5.0.0 Returns hash with values
    # @return [Hash{String => Array<Array<String, String, String>>]
    def get_limits_groups(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', scope: scope, token: token)
      TargetModel.limits_groups(scope: scope)
    end

    # Enables limits for all the items in the group
    #
    # @param group_name [String] Name of the group to enable
    def enable_limits_group(group_name, scope: $openc3_scope, token: $openc3_token)
      _limits_group(group_name, action: :enable, scope: scope, token: token)
    end

    # Disables limits for all the items in the group
    #
    # @param group_name [String] Name of the group to disable
    def disable_limits_group(group_name, scope: $openc3_scope, token: $openc3_token)
      _limits_group(group_name, action: :disable, scope: scope, token: token)
    end

    # Returns all defined limits sets
    #
    # @return [Array<String>] All defined limits sets
    def get_limits_sets(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', scope: scope, token: token)
      LimitsEventTopic.sets(scope: scope).keys
    end

    # Changes the active limits set that applies to all telemetry
    #
    # @param limits_set [String] The name of the limits set
    def set_limits_set(limits_set, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm_set', scope: scope, token: token)
      message = "Setting Limits Set: #{limits_set}"
      Logger.info(message, scope: scope)
      LimitsEventTopic.write({ type: :LIMITS_SET, set: limits_set.to_s,
        time_nsec: Time.now.to_nsec_from_epoch, message: message }, scope: scope)
    end

    # Returns the active limits set that applies to all telemetry
    #
    # @return [String] The current limits set
    def get_limits_set(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', scope: scope, token: token)
      LimitsEventTopic.current_set(scope: scope)
    end

    # Returns limits events starting at the provided offset. Passing nil for an
    # offset will return the last received limits event and associated offset.
    #
    # @param offset [Integer] Offset to start reading limits events. Nil to return
    #   the last received limits event (if any).
    # @param count [Integer] The total number of events returned. Default is 100.
    # @return [Hash, Integer] Event hash followed by the offset. The offset can
    #   be used in subsequent calls to return events from where the last call left off.
    def get_limits_events(offset = nil, count: 100, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'tlm', scope: scope, token: token)
      LimitsEventTopic.read(offset, count: count, scope: scope)
    end

    ###########################################################################
    # PRIVATE implementation details
    ###########################################################################

    # Enables or disables a limits group
    def _limits_group(group_name, action:, scope:, token:)
      authorize(permission: 'tlm_set', scope: scope, token: token)
      group_name.upcase!
      group = get_limits_groups(scope: scope, token: token)[group_name]
      raise "LIMITS_GROUP #{group_name} undefined. Ensure your telemetry definition contains the line: LIMITS_GROUP #{group_name}" unless group

      Logger.info("#{action.to_s.capitalize} Limits Group: #{group_name}", scope: scope)
      last_target_name = nil
      last_packet_name = nil
      packet = nil
      group.sort.each do |target_name, packet_name, item_name|
        if last_target_name != target_name || last_packet_name != packet_name
          if last_target_name && last_packet_name
            TargetModel.set_packet(last_target_name, last_packet_name, packet, scope: scope)
          end
          packet = TargetModel.packet(target_name, packet_name, scope: scope)
        end
        packet['items'].each do |item|
          if item['name'] == item_name
            if action == :enable
              enabled = true
              item['limits']['enabled'] = true
              message = "Enabling Limits For '#{target_name} #{packet_name} #{item_name}'"
            elsif action == :disable
              enabled = false
              item['limits'].delete('enabled')
              message = "Disabling Limits For '#{target_name} #{packet_name} #{item_name}'"
            end
            Logger.info(message, scope: scope)

            event = { type: :LIMITS_ENABLE_STATE, target_name: target_name, packet_name: packet_name,
                      item_name: item_name, enabled: enabled, time_nsec: Time.now.to_nsec_from_epoch, message: message }
            LimitsEventTopic.write(event, scope: scope)
            break
          end
        end
        last_target_name = target_name
        last_packet_name = packet_name
      end
      if last_target_name && last_packet_name
        TargetModel.set_packet(last_target_name, last_packet_name, packet, scope: scope)
      end
    end
  end
end
