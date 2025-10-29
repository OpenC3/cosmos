require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/microservice_model'

module OpenC3
  class RemoveUniqueId < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        target_models = TargetModel.all(scope: scope)
        target_models.each do |name, target_model|
          target_model.delete("cmd_unique_id_mode")
          target_model.delete("tlm_unique_id_mode")
          model = TargetModel.from_json(target_model, scope: scope)
          model.update()
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::RemoveUniqueId.run
end
