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
  class RemoveDecomLogSettings < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        target_models = TargetModel.all(scope: scope)
        target_models.each do |name, target_model|
          # Remove deprecated decom log settings from target model
          target_model.delete("cmd_decom_log_cycle_time")
          target_model.delete("cmd_decom_log_cycle_size")
          target_model.delete("cmd_decom_log_retain_time")
          target_model.delete("tlm_decom_log_cycle_time")
          target_model.delete("tlm_decom_log_cycle_size")
          target_model.delete("tlm_decom_log_retain_time")
          target_model.delete("reduced_minute_log_retain_time")
          target_model.delete("reduced_hour_log_retain_time")
          target_model.delete("reduced_day_log_retain_time")
          target_model.delete("reduced_log_retain_time")
          target_model.delete("reducer_disable")
          target_model.delete("reducer_max_cpu_utilization")

          # Remove deprecated microservice types from target_microservices hash
          if target_model["target_microservices"]
            target_model["target_microservices"].delete("DECOMCMDLOG")
            target_model["target_microservices"].delete("DECOMLOG")
            target_model["target_microservices"].delete("REDUCER")
          end

          model = TargetModel.from_json(target_model, scope: scope)
          model.update()

          # Remove DECOMCMDLOG DECOMLOG REDUCER microservices
          %w(DECOMCMDLOG DECOMLOG REDUCER).each do |type|
            microservice = MicroserviceModel.get_model(name: "#{scope}__#{type}__#{name}", scope: scope)
            microservice.destroy if microservice
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::RemoveDecomLogSettings.run
end
