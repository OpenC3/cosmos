# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/target_model'
require 'openc3/models/microservice_model'
require 'openc3/topics/limits_event_topic'

module OpenC3
  # Backfill limits groups as telemetry for scopes created before it existed:
  # - Fail before changing anything if a target has a telemetry packet of its own
  #   named LIMITS_GROUP, which is now reserved (see check_limits_group_packets)
  # - Store each limits group under the target which defines it (TARGET__GROUP)
  #   rather than just its name. Groups whose names can't become LIMITS_GROUP
  #   items are removed with a warning, like installing skips them.
  # - Define the <TARGET> LIMITS_GROUP packet for each target with limits groups
  #   and add it to the target's TSDB microservice
  # - Add the limits group microservice to the scope's SCOPEMULTI
  # New scopes get the microservice via ScopeModel#deploy and installing a target
  # stores its groups and defines its packet.
  class LimitsGroupBackfill < Migration
    def self.run
      scopes = ScopeModel.get_all_models(scope: nil)
      check_limits_group_packets(scopes.keys)
      scopes.each do |scope, scope_model|
        backfill_targets(scope)
        add_microservice(scope, scope_model)
      end
    end

    # LIMITS_GROUP is now a reserved telemetry packet name. Raising fails the
    # upgrade before anything is changed and the migration runs again on the
    # next start, so the targets can be fixed on the previous version first.
    def self.check_limits_group_packets(scopes)
      targets = []
      scopes.each do |scope|
        TargetModel.get_all_models(scope: scope).each do |target_name, model|
          json = Store.instance(db_shard: model.db_shard).hget("#{scope}__openc3tlm__#{target_name}", PacketConfig::LIMITS_GROUP_PACKET)
          next unless json

          # A previous run which failed later on already stored the generated packet.
          # config_name hashes the name, layout and states of every item.
          groups = model.limits_groups || []
          next if !groups.empty? and JSON.parse(json, allow_nan: true, create_additions: true)['config_name'] == PacketConfig.generate_limits_group_packet(target_name, groups).config_name

          targets << "#{target_name} (scope #{scope})"
        end
      end
      return if targets.empty?

      raise "Telemetry packet name #{PacketConfig::LIMITS_GROUP_PACKET} is now reserved for the limits groups a target defines, but these targets have a telemetry packet named #{PacketConfig::LIMITS_GROUP_PACKET}: #{targets.join(', ')}. Go back to the previous COSMOS version, rename the packet in each target's telemetry definition, reinstall the plugins, then upgrade again."
    end

    # Every step can run again: the migration is only recorded once every scope
    # is done so a failure (e.g. in add_microservice) reruns the whole thing.
    def self.backfill_targets(scope)
      models = TargetModel.get_all_models(scope: scope)
      rekey_groups(scope, models)
      stored = Store.hkeys("#{scope}__limits_groups").to_set
      models.each do |target_name, model|
        group_names = valid_group_names(model, stored)
        next if group_names.empty?

        # Storing the packet again on a rerun is harmless (see add_limits_group_packet)
        add_limits_group_packet(model, PacketConfig.generate_limits_group_packet(target_name, group_names))
      end
    end

    # Before groups became items in <TARGET> LIMITS_GROUP any name was allowed.
    # Drop the ones which can't, and the ones rekey_groups couldn't give to a
    # single target, which it removed from the store.
    #
    # @param stored [Set<String>] The group keys in the store
    # @return [Array<String>] The target's group names which can be LIMITS_GROUP items
    def self.valid_group_names(model, stored)
      group_names = model.limits_groups || []
      valid = group_names.select do |group|
        !PacketConfig.limits_group_name_error(group) and stored.include?(LimitsEventTopic.limits_group_key(model.name, group))
      end
      if valid.length != group_names.length
        model.limits_groups = valid
        model.update
      end
      valid
    end

    # Store each group under the target which defines it. Names could contain
    # '__' before groups were owned by a target so a legacy name can be a key
    # written here (e.g. INST's group SYSTEM__TEMPS and SYSTEM's group TEMPS).
    # The two can't be told apart afterwards so the new keys, the deletes and a
    # marker are written together and a rerun skips a scope already done.
    def self.rekey_groups(scope, models)
      done_key = "#{scope}__limits_groups_rekeyed"
      return if Store.get(done_key)

      groups = Store.hgetall("#{scope}__limits_groups")
      # Before groups were owned by a target they were stored by name alone
      owners = Hash.new { |hash, group| hash[group] = [] }
      models.each do |target_name, model|
        (model.limits_groups || []).each do |group|
          if groups[group]
            owners[group] << target_name
          else
            # e.g. another target defined it too and uninstalling that one deleted it
            Logger.warn("Removed LIMITS_GROUP #{group} of target #{target_name} in scope #{scope}: its definition isn't stored. Reinstall the target to use it.")
          end
        end
      end
      rekeyed = {}
      legacy = Set.new
      # A stored group no target defines would be read as TARGET__GROUP if its name
      # contains '__' so remove it if it can't be a group. Others stay ownerless.
      groups.each_key do |group|
        next if owners.key?(group) or !(error = PacketConfig.limits_group_name_error(group))

        Logger.warn("Removed LIMITS_GROUP #{group} in scope #{scope}: no target defines it and the name #{error}.")
        legacy << group
      end
      owners.each do |group, target_names|
        legacy << group
        target_names.each do |target_name|
          if (error = PacketConfig.limits_group_name_error(group))
            Logger.warn("Removed LIMITS_GROUP #{group} of target #{target_name} in scope #{scope}: the name #{error}. Rename the group and reinstall the target to use it.")
          elsif target_names.length > 1
            # Each install overwrote the group so only the last one's items were kept
            Logger.warn("Removed LIMITS_GROUP #{group} of target #{target_name} in scope #{scope}: targets #{target_names.sort.join(', ')} all define it but only one of their definitions was stored. Reinstall the target to use it.")
          else
            rekeyed[LimitsEventTopic.limits_group_key(target_name, group)] = groups[group]
          end
        end
      end
      legacy.subtract(rekeyed.keys)
      Store.multi do |multi|
        rekeyed.each { |key, items| multi.hset("#{scope}__limits_groups", key, items) }
        multi.hdel("#{scope}__limits_groups", *legacy.to_a) unless legacy.empty?
        multi.set(done_key, 'true')
      end
    end

    # Installing a target adds this packet like any other
    # (see PacketConfig#build_limits_group_packet)
    def self.add_limits_group_packet(model, packet)
      TargetModel.set_packet(model.name, packet.packet_name, packet, scope: model.scope)
      # Seed the CVT like TargetModel#update_store_telemetry so the packet can be read
      # before the limits group microservice publishes it. HSETNX never overwrites values.
      json_hash = packet.sorted_items.to_h { |item| [item.name, nil] }
      Store.instance(db_shard: model.db_shard).hsetnx("#{model.scope}__tlm__#{model.name}", packet.packet_name, JSON.generate(json_hash, allow_nan: true))
      packet.sorted_items.each { |item| TargetModel.add_to_target_allitems_list(model.name, item.name, scope: model.scope) }
      model.update_store_item_map
      # Installing subscribes the TSDB microservice to every packet's DECOM topic.
      # Like TargetModel#dynamic_update tell a running one and update its model.
      tsdb = "#{model.scope}__TSDB__#{model.name}"
      if MicroserviceModel.get_model(name: tsdb, scope: model.scope)
        topics = ["#{model.scope}__DECOM__{#{model.name}}__#{packet.packet_name}"]
        Topic.write_topic("MICROSERVICE__#{tsdb}", { 'command' => 'ADD_TOPICS', 'topics' => topics.to_json }, db_shard: model.db_shard)
        model.add_topics_to_microservice(tsdb, topics)
      end
    end

    def self.add_microservice(scope, scope_model)
      parent = "#{scope}__SCOPEMULTI__#{scope}"
      options = ScopeModel.limits_group_microservice_options(scope, scope_model.shard, parent)
      created = false
      unless MicroserviceModel.get_model(name: options[:name], scope: scope)
        MicroserviceModel.new(**options).create
        created = true
      end
      # SCOPEMULTI starts its children from its command line so add this one.
      # Updating the model makes the operator restart SCOPEMULTI. Checked even
      # when the child exists in case a previous run stopped before this.
      multi = MicroserviceModel.get_model(name: parent, scope: scope)
      if multi and !multi.cmd.include?(options[:name])
        multi.cmd << options[:name]
        multi.update
        created = true
      end
      Logger.info("Added limits group microservice to scope #{scope}") if created
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::LimitsGroupBackfill.run
end
