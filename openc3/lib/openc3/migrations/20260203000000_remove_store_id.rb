require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/plugin_model'

module OpenC3
  # Removes the store_id property from plugin models. It got renamed to
  # store_plugin_id in PR #2858 but that also depends on having
  # store_version_id, which didn't exist prior to this version and can't
  # be determined without some introspection on the plugin and querying
  # the app store (online). When store_plugin_id is unset, COSMOS treats
  # the plugin like it was installed from a gem file.
  class RemoveStoreId < Migration
    def self.run
      ScopeModel.get_all_models(scope: nil).each do |scope, _scope_model|
        plugin_models = PluginModel.all(scope: scope)
        plugin_models.each do |_name, plugin_model|
          plugin_model.delete("store_id")
          model = PluginModel.from_json(plugin_model, scope: scope)
          model.update()
        end
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::RemoveStoreId.run
end
