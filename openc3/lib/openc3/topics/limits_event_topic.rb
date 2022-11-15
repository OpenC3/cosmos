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

require 'openc3/topics/topic'

module OpenC3
  # LimitsEventTopic keeps track of not only the <SCOPE>__openc3_limits_events topic
  # but also the ancillary key value stores. The LIMITS_CHANGE event updates the
  # <SCOPE>__current_limits key. The LIMITS_SET event updates the <SCOPE>__limits_sets.
  # The LIMITS_SETTINGS event updates the <SCOPE>__current_limits_settings.
  # While this isn't a clean separation of topics (streams) and models (key-value)
  # it helps maintain consistency as the topic and model are linked.
  class LimitsEventTopic < Topic
    def self.write(event, scope:)
      case event[:type]
      when :LIMITS_CHANGE
        # The current_limits hash keeps only the current limits state of items
        # It is used by the API to determine the overall limits state
        field = "#{event[:target_name]}__#{event[:packet_name]}__#{event[:item_name]}"
        Store.hset("#{scope}__current_limits", field, event[:new_limits_state])

      when :LIMITS_SETTINGS
        # Limits updated in limits_api.rb to avoid circular reference to TargetModel
        unless sets(scope: scope).has_key?(event[:limits_set])
          Store.hset("#{scope}__limits_sets", event[:limits_set], 'false')
        end

        field = "#{event[:target_name]}__#{event[:packet_name]}__#{event[:item_name]}"
        limits_settings = Store.hget("#{scope}__current_limits_settings", field)
        if limits_settings
          limits_settings = JSON.parse(limits_settings, :allow_nan => true, :create_additions => true)
        else
          limits_settings = {}
        end
        limits = {}
        limits['red_low'] = event[:red_low]
        limits['yellow_low'] = event[:yellow_low]
        limits['yellow_high'] = event[:yellow_high]
        limits['red_high'] = event[:red_high]
        limits['green_low'] = event[:green_low] if event[:green_low] && event[:green_high]
        limits['green_high'] = event[:green_high] if event[:green_low] && event[:green_high]
        limits_settings[event[:limits_set]] = limits
        limits_settings['persistence_setting'] = event[:persistence] if event[:persistence]
        limits_settings['enabled'] = event[:enabled] if not event[:enabled].nil?
        Store.hset("#{scope}__current_limits_settings", field, JSON.generate(limits_settings, :allow_nan => true))

      when :LIMITS_ENABLE_STATE
        field = "#{event[:target_name]}__#{event[:packet_name]}__#{event[:item_name]}"
        limits_settings = Store.hget("#{scope}__current_limits_settings", field)
        if limits_settings
          limits_settings = JSON.parse(limits_settings, :allow_nan => true, :create_additions => true)
        else
          limits_settings = {}
        end
        limits_settings['enabled'] = event[:enabled]
        Store.hset("#{scope}__current_limits_settings", field, JSON.generate(limits_settings, :allow_nan => true))

      when :LIMITS_SET
        sets = sets(scope: scope)
        raise "Set '#{event[:set]}' does not exist!" unless sets.key?(event[:set])

        # Set all existing sets to "false"
        sets = sets.transform_values! { |_key, _value| "false" }
        sets[event[:set]] = "true" # Enable the requested set
        Store.hmset("#{scope}__limits_sets", *sets)
      else
        raise "Invalid limits event type '#{event[:type]}'"
      end

      Topic.write_topic("#{scope}__openc3_limits_events", {event: JSON.generate(event, :allow_nan => true)}, '*', 1000)
    end

    # Remove the JSON encoding to return hashes directly
    def self.read(offset = nil, count: 100, scope:)
      final_result = []
      topic = "#{scope}__openc3_limits_events"
      if offset
        result = Topic.read_topics([topic], [offset], nil, count)
        if not result.empty?
          # result is a hash with the topic key followed by an array of results
          # This returns just the array of arrays [[offset, hash], [offset, hash], ...]
          final_result = result[topic]
        end
      else
        result = Topic.get_newest_message(topic)
        final_result = [result] if result
      end
      parsed_result = []
      final_result.each do |offset, hash|
        parsed_result << [offset, JSON.parse(hash['event'], :allow_nan => true, :create_additions => true)]
      end
      return parsed_result
    end

    def self.out_of_limits(scope:)
      out_of_limits = []
      limits = Store.hgetall("#{scope}__current_limits")
      limits.each do |item, limits_state|
        if %w(RED RED_HIGH RED_LOW YELLOW YELLOW_HIGH YELLOW_LOW).include?(limits_state)
          target_name, packet_name, item_name = item.split('__')
          out_of_limits << [target_name, packet_name, item_name, limits_state]
        end
      end
      out_of_limits
    end

    # Returns all the limits sets as keys with the value 'true' or 'false'
    # where only the active set is 'true'
    #
    # @return [Hash{String => String}] Set name followed by 'true' if enabled else 'false'
    def self.sets(scope:)
      Store.hgetall("#{scope}__limits_sets")
    end

    def self.current_set(scope:)
      sets(scope: scope).key('true') || "DEFAULT"
    end

    # Cleanups up the current_limits and current_limits_settings keys for
    # a target or target/packet combination
    def self.delete(target_name, packet_name = nil, scope:)
      limits = Store.hgetall("#{scope}__current_limits")
      limits.each do |item, _limits_state|
        if packet_name
          if item =~ /^#{target_name}__#{packet_name}__/
            Store.hdel("#{scope}__current_limits", item)
          end
        else
          if item =~ /^#{target_name}__/
            Store.hdel("#{scope}__current_limits", item)
          end
        end
      end

      limits_settings = Store.hgetall("#{scope}__current_limits_settings")
      limits_settings.each do |item, _limits_settings|
        if packet_name
          if item =~ /^#{target_name}__#{packet_name}__/
            Store.hdel("#{scope}__current_limits_settings", item)
          end
        else
          if item =~ /^#{target_name}__/
            Store.hdel("#{scope}__current_limits_settings", item)
          end
        end
      end
    end

    # Update the local System based on overall state
    def self.sync_system(scope:)
      all_limits_settings = Store.hgetall("#{scope}__current_limits_settings")
      telemetry = System.telemetry.all
      all_limits_settings.each do |item, limits_settings|
        target_name, packet_name, item_name = item.split('__')
        target = telemetry[target_name]
        if target
          packet = target[packet_name]
          if packet
            limits_settings = JSON.parse(limits_settings, :allow_nan => true, :create_additions => true)
            enabled = limits_settings['enabled']
            persistence = limits_settings['persistence_setting']
            limits_settings.each do |limits_set, settings|
              next unless Hash === limits_set
              System.limits.set(target_name, packet_name, item_name, settings['red_low'], settings['yellow_low'], settings['yellow_high'], settings['red_high'], settings['green_low'], settings['green_high'], limits_set.to_s.intern, persistence, enabled)
            end
            if not enabled.nil?
              if enabled
                System.limits.enable(target_name, packet_name, item_name)
              else
                System.limits.disable(target_name, packet_name, item_name)
              end
            end
          end
        end
      end
    end

    # Update the local system based on limits events
    def self.sync_system_thread_body(scope:, block_ms: nil)
      telemetry = System.telemetry.all
      topics = ["#{scope}__openc3_limits_events"]
      Topic.read_topics(topics, nil, block_ms) do |topic, msg_id, event, redis|
        event = JSON.parse(event['event'], :allow_nan => true, :create_additions => true)
        case event['type']
        when 'LIMITS_CHANGE'
          # Ignore
        when 'LIMITS_SETTINGS'
          target_name = event['target_name']
          packet_name = event['packet_name']
          item_name = event['item_name']
          target = telemetry[target_name]
          if target
            packet = target[packet_name]
            if packet
              enabled = ConfigParser.handle_true_false_nil(event['enabled'])
              persistence = event['persistence']
              System.limits.set(target_name, packet_name, item_name, event['red_low'], event['yellow_low'], event['yellow_high'], event['red_high'], event['green_low'], event['green_high'], event['limits_set'], persistence, enabled)
            end
          end

        when 'LIMITS_ENABLE_STATE'
          target_name = event['target_name']
          packet_name = event['packet_name']
          item_name = event['item_name']
          target = telemetry[target_name]
          if target
            packet = target[packet_name]
            if packet
              enabled = ConfigParser.handle_true_false_nil(event['enabled'])
              if enabled
                System.limits.enable(target_name, packet_name, item_name)
              else
                System.limits.disable(target_name, packet_name, item_name)
              end
            end
          end

        when 'LIMITS_SET'
          System.limits_set = event['set']
        end
      end
    end
  end
end
