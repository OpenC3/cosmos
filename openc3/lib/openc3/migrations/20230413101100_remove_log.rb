require 'openc3/utilities/migration'
require 'openc3/models/scope_model'

module OpenC3
  class RemoveLog < Migration
    def self.run
      ScopeModel.names.each do |scope|
        # Get all existing InterfaceModels and remove log from json
        interface_models = InterfaceModel.all(scope: scope)
        interface_models.each do |key, model_hash|
          if model_hash.has_key?('log')
            model_hash.delete('log')
            InterfaceModel.from_json(model_hash, scope: scope).update
          end
        end
        router_models = RouterModel.all(scope: scope)
        router_models.each do |key, model_hash|
          if model_hash.has_key?('log')
            model_hash.delete('log')
            RouterModel.from_json(model_hash, scope: scope).update
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::RemoveLog.run
end
