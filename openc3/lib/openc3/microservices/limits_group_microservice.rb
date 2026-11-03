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

require 'openc3/microservices/microservice'
require 'openc3/models/target_model'
require 'openc3/topics/limits_event_topic'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/utilities/limits_rollup'

module OpenC3
  # Rolls up the limits state of every limits group in the scope into the
  # COSMOS LIMITS_GROUP packet. Watches limits events, recomputes the groups an
  # event affects, and publishes the packet only when a group's value changes.
  #
  # Runs as a thread in the scope's SCOPEMULTI microservice. Group definitions,
  # current limits states and limits settings all live on db_shard 0 while the
  # packet is written to the COSMOS target's db_shard by write_packet.
  class LimitsGroupMicroservice < Microservice
    # Reload group definitions and recompute every group this often
    RELOAD_PERIOD_SECONDS = 10
    READ_TIMEOUT_MS = 1000

    def initialize(*args)
      super(*args)
      @groups = {}           # group => [[TGT, PKT, ITEM], ...]
      @order = []            # groups with children before their parents
      @item_groups = {}      # 'TGT__PKT__ITEM' => groups which directly contain the item
      @parents = {}          # child group => parent groups
      @definitions = {}      # 'TGT__PKT' => { item => limits enabled in the definition }
      @current_limits = {}   # 'TGT__PKT__ITEM' => limits state
      @settings = {}         # 'TGT__PKT__ITEM' => { 'enabled' => ... }
      @values = {}           # group => [color, enabled] as last computed
      @published = nil       # @values as last published
      @warned = Set.new
      @received_count = 0
      @limits_events_topic = "#{@scope}__openc3_limits_events"
      @metric.set(name: 'limits_group_publish_total', value: @count, type: 'counter')
    end

    def run
      # Start reading events from now. Anything missed while we were down is
      # covered by recomputing every group from current_limits in reload.
      Topic.update_topic_offsets([@limits_events_topic])
      reload()
      publish(force: true)
      next_reload = Time.now + RELOAD_PERIOD_SECONDS
      until @cancel_thread
        begin
          Topic.read_topics([@limits_events_topic], nil, READ_TIMEOUT_MS) do |_topic, _msg_id, msg_hash, _redis|
            break if @cancel_thread

            process_event(JSON.parse(msg_hash['event'], allow_nan: true, create_additions: true))
          end
          break if @cancel_thread

          if Time.now >= next_reload
            reload()
            publish()
            next_reload = Time.now + RELOAD_PERIOD_SECONDS
          end
        rescue => e
          @error = e
          @logger.error("Limits group microservice error: #{e.formatted}")
          sleep(1) unless @cancel_thread
        end
      end
    end

    # Reread the group definitions, item definitions, limits states and settings
    # and recompute every group
    def reload
      @groups = TargetModel.limits_groups(scope: @scope)
      build_indexes()
      @current_limits = Store.hgetall("#{@scope}__current_limits")
      load_settings()
      load_definitions()
      @values = {}
      compute(@order)
    end

    # @param event [Hash] A limits event from the limits events topic
    def process_event(event)
      case event['type']
      when 'LIMITS_CHANGE', 'LIMITS_ENABLE_STATE'
        key = "#{event['target_name']}__#{event['packet_name']}__#{event['item_name']}"
        groups = @item_groups[key]
        return unless groups

        # Read the stored state rather than trusting the event: events for stored
        # packets with suppress_stored don't update current_limits
        @current_limits[key] = Store.hget("#{@scope}__current_limits", key)
        settings = Store.hget("#{@scope}__current_limits_settings", key)
        @settings[key] = settings ? JSON.parse(settings, allow_nan: true, create_additions: true) : nil
        compute(with_ancestors(groups))
        publish()
      when 'LIMITS_GROUP_ENABLE_STATE', 'LIMITS_SETTINGS'
        # These can change the enabled flag of many items so reread them all
        load_settings()
        compute(@order)
        publish()
      end
    end

    # Publish COSMOS LIMITS_GROUP if any group's value changed since the last publish
    #
    # @param force [Boolean] Publish even if nothing changed (as long as there are groups)
    def publish(force: false)
      return if @values.empty? and (@published.nil? or @published.empty?)
      return if !force and @values == @published

      packet = TargetModel.limits_group_packet(@values.keys)
      @values.each do |group, (color, enabled)|
        item = packet.get_item(group)
        # A group with no enabled member reports GREEN with no limits state so
        # limits aware widgets show it uncolored
        packet.write_item(item, TargetModel::LIMITS_GROUP_STATES[color || 'GREEN'], :RAW)
        item.limits.state = color ? color.to_sym : nil
        enabled_item = packet.get_item("#{group}#{PacketConfig::LIMITS_GROUP_ENABLED_SUFFIX}")
        packet.write_item(enabled_item, TargetModel::LIMITS_GROUP_ENABLED_STATES[enabled ? 'TRUE' : 'FALSE'], :RAW)
      end
      @received_count += 1
      packet.received_time = Time.now.sys
      packet.received_count = @received_count
      packet.stored = false
      # write_packet updates the DECOM topic and the CVT but (unlike inject_tlm)
      # doesn't check limits so the rollup never raises limits events of its own
      TelemetryDecomTopic.write_packet(packet, scope: @scope)
      @published = @values.dup
      @count += 1
      @metric.set(name: 'limits_group_publish_total', value: @count, type: 'counter')
    end

    attr_reader :values

    private

    def build_indexes
      @item_groups = {}
      @parents = {}
      @groups.each do |group, members|
        members.each do |target_name, packet_name, item_name|
          if child_group?(target_name, packet_name)
            (@parents[item_name] ||= []) << group
          else
            (@item_groups["#{target_name}__#{packet_name}__#{item_name}"] ||= []) << group
          end
        end
      end

      # Order the groups so children are computed before their parents. Install
      # rejects cycles but if one is stored anyway skip the edge that closes it.
      @order = []
      done = Set.new
      visiting = Set.new
      visit = lambda do |group|
        return if done.include?(group)

        if visiting.include?(group)
          warn_once("cycle #{group}", "LIMITS_GROUP #{group} contains itself. Ignoring the nested group that closes the loop.")
          return
        end
        visiting << group
        @groups[group].each do |target_name, packet_name, item_name|
          visit.call(item_name) if child_group?(target_name, packet_name) and @groups[item_name]
        end
        visiting.delete(group)
        done << group
        @order << group
      end
      @groups.keys.sort.each { |group| visit.call(group) }
    end

    def load_settings
      @settings = {}
      Store.hgetall("#{@scope}__current_limits_settings").each do |key, json|
        @settings[key] = JSON.parse(json, allow_nan: true, create_additions: true)
      end
    end

    # Item definitions supply the limits enabled flag when no setting is stored
    # and tell us which members are unknown or have no limits
    def load_definitions
      @definitions = {}
      packets = Set.new
      @groups.each_value do |members|
        members.each do |target_name, packet_name, _item_name|
          packets << [target_name, packet_name] unless child_group?(target_name, packet_name)
        end
      end
      packets.each do |target_name, packet_name|
        begin
          packet = TargetModel.packet(target_name, packet_name, scope: @scope)
        rescue RuntimeError
          next # Unknown packet so all its members are ignored
        end
        items = {}
        packet['items'].each do |item|
          limits = item['limits']
          # Only items with limits (or state colors) have an enabled flag
          items[item['name']] = limits['enabled'] if limits and limits.key?('enabled')
        end
        @definitions["#{target_name}__#{packet_name}"] = items
      end
    end

    # @return [Array<String>] the groups plus every group above them
    def with_ancestors(groups)
      result = Set.new
      pending = groups.dup
      until pending.empty?
        group = pending.pop
        next if result.include?(group)

        result << group
        pending.concat(@parents[group] || [])
      end
      @order.select { |group| result.include?(group) }
    end

    # @param groups [Array<String>] groups to compute, children before parents
    def compute(groups)
      groups.each do |group|
        members = []
        @groups[group].each do |target_name, packet_name, item_name|
          if child_group?(target_name, packet_name)
            # A child which isn't defined (yet) is ignored like an unknown item
            child = @values[item_name]
            members << child if child
          else
            member = item_member(target_name, packet_name, item_name, group)
            members << member if member
          end
        end
        @values[group] = LimitsRollup.rollup(members)
      end
    end

    # @return [Array(String|nil, Boolean), nil] [limits state, enabled] or nil if the item is unknown
    def item_member(target_name, packet_name, item_name, group)
      definition = @definitions["#{target_name}__#{packet_name}"]
      unless definition and definition.key?(item_name)
        warn_once("#{group} #{target_name} #{packet_name} #{item_name}",
                  "LIMITS_GROUP #{group} member #{target_name} #{packet_name} #{item_name} does not exist or has no limits. Ignoring it.")
        return nil
      end

      key = "#{target_name}__#{packet_name}__#{item_name}"
      settings = @settings[key]
      if settings and settings.key?('enabled')
        enabled = settings['enabled']
      else
        enabled = definition[item_name]
      end
      [@current_limits[key], enabled ? true : false]
    end

    def child_group?(target_name, packet_name)
      target_name == 'COSMOS' and packet_name == 'LIMITS_GROUP'
    end

    def warn_once(key, message)
      return if @warned.include?(key)

      @warned << key
      @logger.warn(message)
    end
  end
end

if __FILE__ == $0
  OpenC3::LimitsGroupMicroservice.run
  OpenC3::ThreadManager.instance.shutdown
  OpenC3::ThreadManager.instance.join
end
