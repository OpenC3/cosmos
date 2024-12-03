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
      if BASE # Only remove the trigger group microservice if we're not enterprise
        MicroserviceModel.get_all_models(scope: 'DEFAULT').each do |microservice_name, microservice_model|
          if microservice_name =~ /__TRIGGER_GROUP__/
            microservice_model.destroy
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::NoTriggerGroups.run
end
