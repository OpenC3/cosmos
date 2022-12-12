require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/target_model'

module OpenC3
  class ConvertToMulti < Migration
    def self.run
      # Add parent to preexisting scope microservies and deploy new periodic and multi
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        parent = "#{scope}__SCOPEMULTI__#{scope}"
        model = MicroserviceModel.get_model(name: "#{scope}__OPENC3__LOG", scope: scope)
        if model
          model.parent = parent
          model.update
          scope_model.children << "#{scope}__OPENC3__LOG"
        end
        model = MicroserviceModel.get_model(name: "#{scope}__NOTIFICATION__LOG", scope: scope)
        if model
          model.parent = parent
          model.update
          scope_model.children << "#{scope}__NOTIFICATION__LOG"
        end
        model = MicroserviceModel.get_model(name: "#{scope}__COMMANDLOG__UNKNOWN", scope: scope)
        if model
          model.parent = parent
          model.update
          scope_model.children << "#{scope}__COMMANDLOG__UNKNOWN"
        end
        model = MicroserviceModel.get_model(name: "#{scope}__PACKETLOG__UNKNOWN", scope: scope)
        if model
          model.parent = parent
          model.update
          scope_model.children << "#{scope}__PACKETLOG__UNKNOWN"
        end
        scope_model.deploy_periodic_microservice("", {}, parent)
        scope_model.deploy_scopemulti_microservice("", {})

        # Add parent to preexisting target microservices and deploy new multi
        TargetModel.get_all_models(scope: scope).each do |target_name, target_model|
          next if target_name == 'UNKNOWN'
          parent = "#{scope}__MULTI__#{target_name}"
          %w(DECOM COMMANDLOG DECOMCMDLOG PACKETLOG DECOMLOG REDUCER CLEANUP).each do |type|
            model = MicroserviceModel.get_model(name: "#{scope}__#{type}__#{target_name}", scope: scope)
            if model
              model.parent = parent
              model.update
              target_model.children << "#{scope}__#{type}__#{target_name}"
            end
          end
          target_model.deploy_multi_microservice("", {}, nil)
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::ConvertToMulti.run
end
