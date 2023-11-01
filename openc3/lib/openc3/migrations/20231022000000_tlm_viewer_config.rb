require 'openc3/utilities/migration'
require 'openc3/models/tool_config_model'

module OpenC3
  class TlmViewerConfig < Migration
    def self.run
      ScopeModel.names.each do |scope|
        # Get all existing ToolConfigModels and change keys from tlm_viewer to telemetry_viewer
        names = ToolConfigModel.list_configs('tlm_viewer')
        names.each do |name|
          config = ToolConfigModel.load_config('tlm_viewer', name)
          ToolConfigModel.save_config('telemetry_viewer', name, config)
          ToolConfigModel.delete_config('tlm_viewer', name)
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::TlmViewerConfig.run
end
