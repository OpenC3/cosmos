require 'openc3/utilities/migration'
require 'openc3/models/scope_model'

module OpenC3
  class AddTargetNames < Migration
    def self.run
      ScopeModel.names.each do |scope|
        # Get all existing InterfaceModels and add cmd_target_names / tlm_target_names if necessary
        interface_models = InterfaceModel.all(scope: scope)
        interface_models.each do |key, model_hash|
          target_names = model_hash['target_names']
          model_hash['cmd_target_names'] = target_names unless model_hash['cmd_target_names']
          model_hash['tlm_target_names'] = target_names unless model_hash['tlm_target_names']
          InterfaceModel.from_json(model_hash, scope: scope).update
        end
        router_models = RouterModel.all(scope: scope)
        router_models.each do |key, model_hash|
          target_names = model_hash['target_names']
          model_hash['cmd_target_names'] = target_names unless model_hash['cmd_target_names']
          model_hash['tlm_target_names'] = target_names unless model_hash['tlm_target_names']
          RouterModel.from_json(model_hash, scope: scope).update
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::AddTargetNames.run
end