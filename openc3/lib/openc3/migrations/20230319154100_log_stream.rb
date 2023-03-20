require 'openc3/utilities/migration'
require 'openc3/models/scope_model'

module OpenC3
  class LogStream < Migration
    def self.run
      ScopeModel.names.each do |scope|
        # Get all existing InterfaceModels and change json for log_raw to log_stream
        interface_models = InterfaceModel.all(scope: scope)
        interface_models.each do |key, model_hash|
          if model_hash.has_key?('log_raw')
            if model_hash['log_raw']
              model_hash['log_stream'] = []
            else
              model_hash['log_stream'] = nil
            end
            model_hash.delete('log_raw')
            InterfaceModel.from_json(model_hash, scope: scope).update
          end
        end
        router_models = RouterModel.all(scope: scope)
        router_models.each do |key, model_hash|
          if model_hash.has_key?('log_raw')
            if model_hash['log_raw']
              model_hash['log_stream'] = []
            else
              model_hash['log_stream'] = nil
            end
            model_hash.delete('log_raw')
            RouterModel.from_json(model_hash, scope: scope).update
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::LogStream.run
end
