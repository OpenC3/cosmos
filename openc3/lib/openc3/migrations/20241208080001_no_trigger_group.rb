require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/microservice_model'

module OpenC3
  class NoTriggerGroups < Migration
    begin
      require 'openc3-enterprise/models/cmd_authority_model'
      require 'openc3-enterprise/models/critical_cmd_model'
      BASE = false
    rescue LoadError
      BASE = true
    end

    def self.run
      MicroserviceModel.get_all_models(scope: 'DEFAULT').each do |microservice_name, microservice_model|
        if microservice_name =~ /__TRIGGER_GROUP__/
          if BASE
            # Only remove the trigger group microservice if we're not enterprise
            microservice_model.destroy
          else
            # Need to update working dir for Enterprise
            microservice_model.work_dir = '/openc3-enterprise/lib/openc3-enterprise/microservices'
            microservice_model.update
          end
        end

        if microservice_name =~ /__OPENC3__REACTION/
          # Need to update working dir for Enterprise
          microservice_model.work_dir = '/openc3-enterprise/lib/openc3-enterprise/microservices'
          microservice_model.update
        end

        if microservice_name =~ /__TIMELINE__/
          # Need to update working dir for Enterprise
          microservice_model.work_dir = '/openc3-enterprise/lib/openc3-enterprise/microservices'
          microservice_model.update
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::NoTriggerGroups.run
end
