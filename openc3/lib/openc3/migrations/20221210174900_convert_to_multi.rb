require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/target_model'

module OpenC3
  class ConvertToMulti < Migration
    def self.run
      # Add parent to preexisting scope microservies and deploy new periodic and multi
      ScopeModel.get_all_models.each do |scope_model|
        scope = scope_model.name
        parent = "#{scope}__SCOPEMULTI__#{scope}"
        model = MicroserviceModel.get_model(name: "#{scope}__OPENC3__LOG", scope: scope)
        if model
          model.parent = parent
          model.update
        end
        model = MicroserviceModel.get_model(name: "#{scope}__NOTIFICATION__LOG", scope: scope)
        if model
          model.parent = parent
          model.update
        end
        model = MicroserviceModel.get_model(name: "#{scope}__COMMANDLOG__UNKNOWN", scope: scope)
        if model
          model.parent = parent
          model.update
        end
        model = MicroserviceModel.get_model(name: "#{scope}__PACKETLOG__UNKNOWN", scope: scope)
        if model
          model.parent = parent
          model.update
        end
        scope_model.deploy_periodic_microservice("", {}, parent)
        scope_model.deploy_scopemulti_microservice("", {})

        # Add parent to preexisting target microservices and deploy new multi
        TargetModel.get_all_models(scope: scope).each do |target_model|
          parent = "#{scope}__MULTI__#{target_model.name}"
          %w(DECOM COMMANDLOG DECOMCMDLOG PACKETLOG DECOMLOG REDUCER CLEANUP).each do |type|
            model = MicroserviceModel.get_model(name: "#{scope}__#{type}__#{target_model.name}", scope: scope)
            if model
              model.parent = parent
              model.update
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
