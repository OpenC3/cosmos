require 'openc3/utilities/migration'
require 'openc3/models/scope_model'

module OpenC3
  class ScopeCriticalCmd < Migration
    def self.run
      ScopeModel.names.each do |scope|
        scope_model = ScopeModel.get_model(name: scope)
        parent = "#{scope}__SCOPEMULTI__#{scope}"
        scope_model.deploy_critical_cmd_microservice("/notexist", {}, parent)
        microservice_model = MicroserviceModel.get_model(name: parent, scope: scope)
        microservice_model.cmd << "#{scope}__CRITICALCMD__#{scope}"
        microservice_model.update
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::ScopeCriticalCmd.run
end
