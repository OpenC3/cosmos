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
require 'openc3/models/microservice_model'
require 'openc3/models/bridge_model'

module OpenC3
  # Ensure every existing scope has a DEFAULT bridge_microservice (the Iroh hub
  # that lets openc3-app run COSMOS interfaces on the host). New scopes get one
  # via ScopeModel#deploy; this backfills any scope created before that.
  class DefaultBridge < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        name = "#{scope}__BRIDGE__DEFAULT"
        next if MicroserviceModel.get_model(name: name, scope: scope)

        BridgeModel.build_microservice(bridge_name: "DEFAULT", scope: scope, shard: scope_model.shard).create
        Logger.info("Added DEFAULT bridge_microservice to scope #{scope}")
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::DefaultBridge.run
end
