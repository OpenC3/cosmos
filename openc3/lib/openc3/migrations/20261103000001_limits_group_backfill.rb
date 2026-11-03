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

module OpenC3
  # Backfill COSMOS LIMITS_GROUP for scopes created before it existed: define the
  # packet from the limits groups already installed and add the limits group
  # microservice to the scope's SCOPEMULTI. New scopes get the microservice
  # via ScopeModel#deploy and the packet when a plugin is installed.
  class LimitsGroupBackfill < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        TargetModel.sync_limits_group_packet(scope: scope)

        parent = "#{scope}__SCOPEMULTI__#{scope}"
        options = ScopeModel.limits_group_microservice_options(scope, scope_model.shard, parent)
        next if MicroserviceModel.get_model(name: options[:name], scope: scope)

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
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::LimitsGroupBackfill.run
end
