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
  # - Store each limits group under the target which defines it (TARGET__GROUP)
  #   rather than just its name
  # - Define the <TARGET> LIMITS_GROUP packet for each target with limits groups
  # - Add the limits group microservice to the scope's SCOPEMULTI
  # New scopes get the microservice via ScopeModel#deploy and installing a target
  # stores its groups and defines its packet.
  class LimitsGroupBackfill < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        backfill_targets(scope)
        add_microservice(scope, scope_model)
      end
    end

    def self.backfill_targets(scope)
      groups = Store.hgetall("#{scope}__limits_groups")
      rekeyed = Set.new
      TargetModel.get_all_models(scope: scope).each do |target_name, model|
        group_names = model.limits_groups || []
        next if group_names.empty?

        group_names.each do |group|
          # Before groups were owned by a target they were stored by name alone
          next unless groups[group]

          Store.hset("#{scope}__limits_groups", LimitsEventTopic.limits_group_key(target_name, group), groups[group])
          rekeyed << group
        end

        store = Store.instance(db_shard: model.db_shard)
        if store.hexists("#{scope}__openc3tlm__#{target_name}", PacketConfig::LIMITS_GROUP_PACKET)
          Logger.warn("Target #{target_name} in scope #{scope} has its own #{PacketConfig::LIMITS_GROUP_PACKET} packet so its limits groups won't be published. Rename the packet and reinstall the target.")
        else
          add_limits_group_packet(model, group_names)
        end
      end
      Store.hdel("#{scope}__limits_groups", *rekeyed.to_a) unless rekeyed.empty?
    end

    # Installing a target adds this packet like any other
    # (see PacketConfig#build_limits_group_packet)
    def self.add_limits_group_packet(model, group_names)
      packet = PacketConfig.generate_limits_group_packet(model.name, group_names)
      TargetModel.set_packet(model.name, packet.packet_name, packet, scope: model.scope)
      # Seed the CVT like TargetModel#update_store_telemetry so the packet can be read
      # before the limits group microservice publishes it. HSETNX never overwrites values.
      json_hash = packet.sorted_items.to_h { |item| [item.name, nil] }
      Store.instance(db_shard: model.db_shard).hsetnx("#{model.scope}__tlm__#{model.name}", packet.packet_name, JSON.generate(json_hash, allow_nan: true))
      packet.sorted_items.each { |item| TargetModel.add_to_target_allitems_list(model.name, item.name, scope: model.scope) }
      model.update_store_item_map
    end

    def self.add_microservice(scope, scope_model)
      parent = "#{scope}__SCOPEMULTI__#{scope}"
      options = ScopeModel.limits_group_microservice_options(scope, scope_model.shard, parent)
      return if MicroserviceModel.get_model(name: options[:name], scope: scope)

      MicroserviceModel.new(**options).create
      # SCOPEMULTI starts its children from its command line so add this one.
      # Updating the model makes the operator restart SCOPEMULTI.
      multi = MicroserviceModel.get_model(name: parent, scope: scope)
      if multi
        multi.cmd << options[:name] unless multi.cmd.include?(options[:name])
        multi.update
      end
      Logger.info("Added limits group microservice to scope #{scope}")
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::LimitsGroupBackfill.run
end
