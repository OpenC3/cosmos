require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/microservice_model'

module OpenC3
  class NoCriticalCmd < Migration
    begin
      require 'openc3-enterprise/models/cmd_authority_model'
      require 'openc3-enterprise/models/critical_cmd_model'
      BASE = false
    rescue LoadError
      BASE = true
    end

    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        model = MicroserviceModel.get_model(name: "#{scope}__CRITICALCMD__#{scope}", scope: scope)
        if BASE # Only remove the critical command model if we're not enterprise
          model.destroy if model
        else
          model.work_dir = '/openc3-enterprise/lib/openc3-enterprise/microservices'
          model.update
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::NoCriticalCmd.run
end
