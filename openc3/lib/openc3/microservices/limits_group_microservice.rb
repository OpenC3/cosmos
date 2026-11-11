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
  # target's packet only when one of its groups' values changes. Each read of
  # the events topic (up to 1000 events) is published once, so a burst of
  # events costs a few publishes rather than one per event.
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
      @packets = {}          # target => [group names, its LIMITS_GROUP packet]
      @settings_changed = false # settings must be reread before the next publish
      @warned = Set.new
      @received_counts = Hash.new(0) # target => packets published
      @event_count = 0             # limits events which changed a group's inputs
      @processing_seconds = 0.0    # time spent computing and publishing for them
      @limits_events_topic = "#{@scope}__openc3_limits_events"
      @config_topic = "#{@scope}#{ConfigTopic::PRIMARY_KEY}"
      @metric.set(name: 'limits_group_publish_total', value: @count, type: 'counter')
      set_event_metrics(0.0)
    end

    def run
      # Start reading events from now. Anything missed while we were down is
      # covered by recomputing every group from current_limits in reload.
      # Both topics are on db_shard 0 so one read covers them.
      topics = [@limits_events_topic, @config_topic]
      Topic.update_topic_offsets(topics)
      # Last limits event read, used to detect events trimmed before they were read.
      # Reading starts at or after this point so it can only cause an extra reload.
      @limits_event_offset = Topic.get_last_offset(@limits_events_topic)
      reload()
      publish(force: true)
      until @cancel_thread
        begin
          changed_targets = Set.new
          limits_events_checked = false
          events = 0
          seconds = 0.0
          Topic.read_topics(topics, nil, READ_TIMEOUT_MS) do |topic, msg_id, msg_hash, _redis|
            break if @cancel_thread

            if topic == @config_topic
              # Installing or removing a target writes its packet definitions and
              # limits groups before the event so they're ready to reread
              changed_targets << msg_hash['name'] if msg_hash['type'] == 'target'
            else
              # Any gap is before the first event in a read so only check once per read
              unless limits_events_checked
                reload_if_events_trimmed()
                limits_events_checked = true
              end
              @limits_event_offset = msg_id
              update_topic_lag(topic, msg_id, metric_name: 'limits_group_topic_delta_seconds', help: 'Delta time between limits event written to stream and limits group start')
              start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
              events += 1 if handle_event(JSON.parse(msg_hash['event'], allow_nan: true, create_additions: true))
              seconds += Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
            end
          end
          break if @cancel_thread

          # A plugin can install several targets at once so reload once per read
          reload(changed_targets: changed_targets.to_a) unless changed_targets.empty?
          # Publish once for everything this read changed
          if events > 0 or !changed_targets.empty?
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            flush()
            seconds += Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          end
          record_events(events, seconds) if events > 0
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
      @settings_changed = false
      load_definitions()
      @values = {}
      compute(@order)
    end

    # The limits events stream only keeps ~1000 entries so a flood of
    # LIMITS_CHANGE events (e.g. a target's first packets) can trim events
    # before a busy microservice reads them. current_limits and the settings
    # are always current so recompute every group from them.
    def reload_if_events_trimmed
      return unless LimitsEventTopic.events_trimmed?(@limits_event_offset, scope: @scope)

      @logger.warn("#{@name}: Limits events were trimmed before they could be read, reloading limits groups")
      reload()
      publish()
    end

    # Handles one event and publishes right away. The run loop instead handles
    # every event in a read with handle_event and then calls flush once.
    #
    # @param event [Hash] A limits event from the limits events topic
    def process_event(event)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return unless handle_event(event)

      flush()
      record_events(1, Process.clock_gettime(Process::CLOCK_MONOTONIC) - start)
    end

    # Recomputes the groups an event affects without publishing them
    #
    # @param event [Hash] A limits event from the limits events topic
    # @return [Boolean] Whether the event affects any group
    def handle_event(event)
      case event['type']
      when 'LIMITS_CHANGE', 'LIMITS_ENABLE_STATE'
        key = "#{event['target_name']}__#{event['packet_name']}__#{event['item_name']}"
        groups = @item_groups[key]
        return false unless groups

        # Read the stored state rather than trusting the event: events for stored
        # packets with suppress_stored don't update current_limits
        @current_limits[key] = Store.hget("#{@scope}__current_limits", key)
        settings = Store.hget("#{@scope}__current_limits_settings", key)
        @settings[key] = settings ? JSON.parse(settings, allow_nan: true, create_additions: true) : nil
        compute(with_ancestors(groups))
        true
      when 'LIMITS_GROUP_ENABLE_STATE', 'LIMITS_SETTINGS'
        # These can change the enabled flag of many items so reread them all,
        # once per read in flush
        @settings_changed = true
        true
      else
        false
      end
    end

    # Rereads the settings if an event changed them and publishes every target
    # whose groups changed since its last publish
    def flush
      if @settings_changed
        load_settings()
        compute(@order)
        @settings_changed = false
      end
      publish()
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
      @packets.select! { |target_name, _packet| by_target.key?(target_name) }

      by_target.each do |target_name, values|
        next if !force and values == @published[target_name]

        publish_target(target_name, values)
        @published[target_name] = values
      end
    end

    attr_reader :values

    private

    # @param events [Integer] Events which affected a group
    # @param seconds [Float] Time spent computing and publishing them
    def record_events(events, seconds)
      @event_count += events
      @processing_seconds += seconds
      set_event_metrics(seconds)
    end

    # The duration gauge is the last read's processing time. The totals let
    # a benchmark compute the average per event over any period from two samples.
    def set_event_metrics(duration)
      @metric.set(name: 'limits_group_duration_seconds', value: duration, type: 'gauge', unit: 'seconds', help: 'Time to roll up and publish the last read of limits events')
      @metric.set(name: 'limits_group_event_total', value: @event_count, type: 'counter', help: 'Limits events which affected a limits group')
      @metric.set(name: 'limits_group_processing_seconds_total', value: @processing_seconds, type: 'counter', unit: 'seconds', help: 'Time spent rolling up and publishing limits events')
    end

    def publish_target(target_name, values)
      # Building the packet means defining two items per group so only rebuild
      # it when the target's groups change. Every item is written below.
      groups, packet = @packets[target_name]
      unless groups == values.keys
        packet = PacketConfig.limits_group_packet(target_name, values.keys)
        @packets[target_name] = [values.keys, packet]
      end
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
