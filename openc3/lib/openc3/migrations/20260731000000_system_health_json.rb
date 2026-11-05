# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'json'
require 'openc3/utilities/local_mode'
require 'openc3/utilities/migration'
require 'openc3/models/scope_model'
require 'openc3/models/setting_model'

module OpenC3
  # The system_health setting was originally stored as a Ruby Hash. Local mode
  # writes settings to disk with File.write and reads them back as a String, so
  # the Hash round tripped into a Ruby inspect String which nothing can parse.
  # Store it as a JSON string like every other setting and repair existing data.
  class SystemHealthJson < Migration
    def self.run
      setting = SettingModel.get(name: 'system_health')
      data = repair(setting && setting['data'])
      SettingModel.set({ name: 'system_health', data: JSON.generate(data) }, scope: 'DEFAULT')
      # Repair the local mode file as well or sync_settings puts the bad data back
      LocalMode.save_setting('DEFAULT', 'system_health', JSON.generate(data))
    end

    # @return [Hash] the existing settings if they can be recovered, otherwise defaults
    def self.repair(data)
      return ScopeModel::SYSTEM_HEALTH_DEFAULTS if data.nil?
      return data if Hash === data
      return ScopeModel::SYSTEM_HEALTH_DEFAULTS unless String === data
      begin
        parsed = JSON.parse(data)
      rescue JSON::ParserError
        # Ruby inspect format, e.g. {"cpu" => {"redThreshold" => 90, ... => nil}}
        # Ruby 3.3 and earlier had no spaces around the rocket. All the values are
        # numbers, booleans, or nil so there's nothing to accidentally rewrite.
        parsed = JSON.parse(data.gsub(/\s*=>\s*/, ': ').gsub(/\bnil\b/, 'null')) rescue nil
      end
      Hash === parsed ? parsed : ScopeModel::SYSTEM_HEALTH_DEFAULTS
    end
  end
end

unless ENV['OPENC3_NO_MIGRATE']
  OpenC3::SystemHealthJson.run
end
