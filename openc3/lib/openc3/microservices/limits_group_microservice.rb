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
require 'openc3/topics/config_topic'
require 'openc3/topics/limits_event_topic'
require 'openc3/topics/telemetry_decom_topic'
require 'openc3/utilities/limits_rollup'

module OpenC3
  # Rolls up the limits state of every limits group in the scope into the
  # <TARGET> LIMITS_GROUP packet of the target which defines the group. Watches
  # limits events, recomputes the groups an event affects, and publishes a
  # target's packet only when one of its groups' values changes.
  #
  # Group and item definitions only change when a target is installed or
  # removed, which writes a target event to the scope's config topic. Those
  # events trigger a reload, as does an error in the event loop in case events
  # were missed.
  #
  # Runs as a thread in the scope's SCOPEMULTI microservice since groups can
  # contain items of any target. Group definitions, current limits states and
  # limits settings all live on db_shard 0 while write_packet writes each packet
  # to its target's db_shard.
  class LimitsGroupMicroservice < Microservice
    READ_TIMEOUT_MS = 1000

    def initialize(*args)
      super(*args)
      # Groups are keyed by TARGET__GROUP (LimitsEventTopic.limits_group_key)
      @groups = {}           # group => [[TGT, PKT, ITEM], ...]
      @order = []            # groups with children before their parents
      @item_groups = {}      # 'TGT__PKT__ITEM' => groups which directly contain the item
      @parents = {}          # child group => parent groups
      @definitions = {}      # target => { packet => { item => limits enabled in the definition } }
      @current_limits = {}   # 'TGT__PKT__ITEM' => limits state
      @settings = {}         # 'TGT__PKT__ITEM' => { 'enabled' => ... }
      @values = {}           # group => [color, enabled] as last computed
      @published = {}        # target => its groups' @values as last published
      @warned = Set.new
      @received_counts = Hash.new(0) # target => packets published
      @limits_events_topic = "#{@scope}__openc3_limits_events"
      @config_topic = "#{@scope}#{ConfigTopic::PRIMARY_KEY}"
      @metric.set(name: 'limits_group_publish_total', value: @count, type: 'counter')
    end

    def run
      # Start reading events from now. Anything missed while we were down is
      # covered by recomputing every group from current_limits in reload.
      # Both topics are on db_shard 0 so one read covers them.
      topics = [@limits_events_topic, @config_topic]
      Topic.update_topic_offsets(topics)
      reload()
      publish(force: true)
      until @cancel_thread
        begin
          changed_targets = Set.new
          Topic.read_topics(topics, nil, READ_TIMEOUT_MS) do |topic, _msg_id, msg_hash, _redis|
            break if @cancel_thread

            if topic == @config_topic
              # Installing or removing a target writes its packet definitions and
              # limits groups before the event so they're ready to reread
              changed_targets << msg_hash['name'] if msg_hash['type'] == 'target'
            else
              process_event(JSON.parse(msg_hash['event'], allow_nan: true, create_additions: true))
            end
          end
          break if @cancel_thread

          # A plugin can install several targets at once so reload once per read
          unless changed_targets.empty?
            reload(changed_targets: changed_targets.to_a)
            publish()
          end
        rescue => e
          @error = e
          @logger.error("Limits group microservice error: #{e.formatted}")
          sleep(1) unless @cancel_thread
          # Events may have been missed so recompute everything from the store
          begin
            reload(changed_targets: changed_targets.to_a) unless @cancel_thread
            publish() unless @cancel_thread
          rescue => e
            @logger.error("Limits group microservice reload error: #{e.formatted}")
          end
        end
      end
    end

    # Reread the group definitions, limits states and settings and recompute
    # every group. Item definitions are cached per packet and only reread for
    # packets not yet cached and those of the changed targets.
    #
    # @param changed_targets [Array<String>] Targets installed or removed since the last reload
    def reload(changed_targets: [])
      changed_targets.each { |target_name| @definitions.delete(target_name) }
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

    # Publish the LIMITS_GROUP packet of each target whose groups' values changed
    # since its last publish
    #
    # @param force [Boolean] Publish every target's packet even if nothing changed
    def publish(force: false)
      by_target = {}
      @values.each do |key, value|
        target_name, group_name = LimitsEventTopic.split_limits_group_key(key)
        # Groups stored before groups were owned by a target have no packet to publish
        next unless target_name

        (by_target[target_name] ||= {})[group_name] = value
      end
      # A target whose groups are all gone has no packet any more
      @published.select! { |target_name, _values| by_target.key?(target_name) }

      by_target.each do |target_name, values|
        next if !force and values == @published[target_name]

        publish_target(target_name, values)
        @published[target_name] = values
      end
    end

    attr_reader :values

    private

    def publish_target(target_name, values)
      packet = PacketConfig.limits_group_packet(target_name, values.keys)
      values.each do |group, (color, enabled)|
        item = packet.get_item(group)
        # A group with no enabled member reports GREEN with no limits state so
        # limits aware widgets show it uncolored
        packet.write_item(item, PacketConfig::LIMITS_GROUP_STATES[color || 'GREEN'], :RAW)
        item.limits.state = color ? color.to_sym : nil
        enabled_item = packet.get_item("#{group}#{PacketConfig::LIMITS_GROUP_ENABLED_SUFFIX}")
        packet.write_item(enabled_item, PacketConfig::LIMITS_GROUP_ENABLED_STATES[enabled ? 'TRUE' : 'FALSE'], :RAW)
      end
      @received_counts[target_name] += 1
      packet.received_time = Time.now.sys
      packet.received_count = @received_counts[target_name]
      packet.stored = false
      # write_packet updates the DECOM topic and the CVT but (unlike inject_tlm)
      # doesn't check limits so the rollup never raises limits events of its own
      TelemetryDecomTopic.write_packet(packet, scope: @scope)
      @count += 1
      @metric.set(name: 'limits_group_publish_total', value: @count, type: 'counter')
    end

    def build_indexes
      @item_groups = {}
      @parents = {}
      @groups.each do |group, members|
        members.each do |target_name, packet_name, item_name|
          if child_group?(packet_name)
            (@parents[LimitsEventTopic.limits_group_key(target_name, item_name)] ||= []) << group
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
          warn_once("cycle #{group}", "LIMITS_GROUP #{display(group)} contains itself. Ignoring the nested group that closes the loop.")
          return
        end
        visiting << group
        @groups[group].each do |target_name, packet_name, item_name|
          next unless child_group?(packet_name)

          child = LimitsEventTopic.limits_group_key(target_name, item_name)
          visit.call(child) if @groups[child]
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
    # and tell us which members are unknown or have no limits. Only the enabled
    # flags are kept, per packet, so each packet definition is parsed once until
    # its target is installed or removed again.
    def load_definitions
      packets = Set.new
      @groups.each_value do |members|
        members.each do |target_name, packet_name, _item_name|
          packets << [target_name, packet_name] unless child_group?(packet_name)
        end
      end
      # Drop packets no group references any more
      @definitions.each do |target_name, target_packets|
        target_packets.select! { |packet_name, _items| packets.include?([target_name, packet_name]) }
      end
      @definitions.reject! { |_target_name, target_packets| target_packets.empty? }

      db_shards = {}
      packets.each do |target_name, packet_name|
        next if @definitions.dig(target_name, packet_name)

        # Read the store rather than TargetModel.packet, and the target's
        # db_shard rather than Store.db_shard_for_target, since both caches can
        # hold what they saw before the target was just installed
        db_shard = (db_shards[target_name] ||= target_db_shard(target_name))
        next unless db_shard # Unknown target so all its members are ignored

        json = Store.instance(db_shard: db_shard).hget("#{@scope}__openc3tlm__#{target_name}", packet_name)
        next unless json # Unknown packet so all its members are ignored

        items = {}
        JSON.parse(json, allow_nan: true, create_additions: true)['items'].each do |item|
          limits = item['limits']
          # Only items with limits (or state colors) have an enabled flag
          items[item['name']] = limits['enabled'] if limits and limits.key?('enabled')
        end
        (@definitions[target_name] ||= {})[packet_name] = items
      end
    end

    # @return [Integer, nil] the target's db_shard or nil if it isn't installed
    def target_db_shard(target_name)
      json = Store.hget("#{@scope}__openc3_targets", target_name)
      json ? JSON.parse(json, allow_nan: true, create_additions: true)['db_shard'].to_i : nil
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
          if child_group?(packet_name)
            # A child which isn't defined (yet) is ignored like an unknown item
            child = @values[LimitsEventTopic.limits_group_key(target_name, item_name)]
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
      definition = @definitions.dig(target_name, packet_name)
      unless definition and definition.key?(item_name)
        warn_once("#{group} #{target_name} #{packet_name} #{item_name}",
                  "LIMITS_GROUP #{display(group)} member #{target_name} #{packet_name} #{item_name} does not exist or has no limits. Ignoring it.")
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

    # Nested groups are the members <TARGET> LIMITS_GROUP <GROUP>
    def child_group?(packet_name)
      packet_name == PacketConfig::LIMITS_GROUP_PACKET
    end

    # @return [String] TARGET GROUP for log messages
    def display(group)
      LimitsEventTopic.split_limits_group_key(group).compact.join(' ')
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
