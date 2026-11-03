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

module OpenC3
  # Ensure every existing scope has the reserved COSMOS target which carries
  # system-generated telemetry such as COSMOS LIMITS_GROUP. New scopes get one
  # via ScopeModel#deploy; this backfills any scope created before that.
  class CosmosTarget < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        existing = TargetModel.get(name: 'COSMOS', scope: scope)
        if existing
          # A plugin installed before COSMOS was reserved owns this target
          if existing['plugin']
            Logger.warn("Scope #{scope} has a COSMOS target from plugin #{existing['plugin']}. COSMOS is now reserved for system-generated telemetry, so rename that target.")
          end
          next
        end

        TargetModel.new(name: 'COSMOS', shard: scope_model.shard, scope: scope).create
        Logger.info("Added COSMOS target to scope #{scope}")
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::CosmosTarget.run
end
