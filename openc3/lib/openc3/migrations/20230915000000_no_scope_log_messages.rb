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
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::NoScopeLogMessages.run
end
