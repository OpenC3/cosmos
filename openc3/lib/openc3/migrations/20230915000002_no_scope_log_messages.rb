require 'openc3/utilities/migration'
require 'openc3/models/microservice_model'

module OpenC3
  class NoScopeLogMessages < Migration
    def self.run
      # Add NOSCOPE topic to log message microservice for DEFAULT scope
      model = MicroserviceModel.get_model(name: "DEFAULT__OPENC3__LOG", scope: 'DEFAULT')
      if model
        model.topics = ["DEFAULT__openc3_log_messages", "NOSCOPE__openc3_log_messages"]
        model.update
      end

      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        parent = "#{scope}__SCOPEMULTI__#{scope}"

        # Remove NOTIFICATION log microservice from scopes
        model = MicroserviceModel.get_model(name: "#{scope}__NOTIFICATION__LOG", scope: scope)
        if model
          model.destroy
        end

        # Add Scope Cleanup microservice to scopes
        model = MicroserviceModel.get_model(name: "#{scope}__SCOPECLEANUP__#{scope}", scope: scope)
        unless model
          scope_model.deploy_scopecleanup_microservice("", {}, parent)
        end

        model = MicroserviceModel.get_model(name: parent, scope: scope)
        if model
          model.cmd.delete("#{scope}__NOTIFICATION__LOG")
          unless model.cmd.include?("#{scope}__SCOPECLEANUP__#{scope}")
            model.cmd << "#{scope}__SCOPECLEANUP__#{scope}"
          end
          model.update
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::NoScopeLogMessages.run
end
