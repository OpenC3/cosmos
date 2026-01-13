require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/plugin_model'

module OpenC3
  class ReinstallPlugins < Migration
    def self.run
      # Get all scopes
      ScopeModel.get_all_models(scope: nil).each do |scope, scope_model|
        next if scope == 'DEFAULT'

        # Get all plugins for this scope
        plugins = PluginModel.all(scope: scope)
        plugins.each do |plugin_name, plugin_data|
          begin
            Logger.info("Reinstalling plugin #{plugin_name} in scope #{scope}")

            # Get the plugin model
            plugin_model = PluginModel.from_json(plugin_data, scope: scope)

            # Undeploy and then restore (reinstall) the plugin
            plugin_model.undeploy
            plugin_model.restore

            Logger.info("Successfully reinstalled plugin #{plugin_name} in scope #{scope}")
          rescue Exception => e
            Logger.error("Error reinstalling plugin #{plugin_name} in scope #{scope}: #{e.formatted}")
            # Continue with other plugins even if one fails
          end
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::ReinstallPlugins.run
end
