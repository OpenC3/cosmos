require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/microservice_model'

module OpenC3
  class PeriodicOnlyDefault < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        next if scope == 'DEFAULT'
        model = MicroserviceModel.get_model(name: "#{scope}__SCOPEMULTI__#{scope}", scope: scope)
        if model
          model.cmd.delete("#{scope}__PERIODIC__#{scope}")
          model.update
        end
        model = MicroserviceModel.get_model(name: "#{scope}__PERIODIC__#{scope}", scope: scope)
        model.destroy if model
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::PeriodicOnlyDefault.run
end
