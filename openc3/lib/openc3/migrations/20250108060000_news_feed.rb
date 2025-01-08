require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/setting_model'

module OpenC3
  class NewsFeed < Migration
    def self.run
      ScopeModel.names.each do |scope|
        setting = SettingModel.get(name: 'news_feed')
        SettingModel.set({ name: 'news_feed', data: true }, scope: scope) unless setting
      end
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::NewsFeed.run
end
