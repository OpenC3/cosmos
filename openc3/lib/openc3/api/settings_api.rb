# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/setting_model'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'list_settings',
                       'get_all_settings',
                       'get_setting',
                       'get_settings',
                       'save_setting'
                     ])

    def list_settings(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      SettingModel.names(scope: scope)
    end

    def get_all_settings(scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      SettingModel.all(scope: scope).transform_values { |hash| JSON.parse(hash['data'], :allow_nan => true, :create_additions => true) }
    end

    def get_setting(name, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      result = SettingModel.get(name: name, scope: scope)
      if result
        JSON.parse(result['data'], :allow_nan => true, :create_additions => true)
      else
        nil
      end
    end

    def get_settings(*settings, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      result = []
      settings.each { |name| result << get_setting(name, scope: scope, token: token) }
      result
    end

    def save_setting(name, data, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'admin', scope: scope, token: token)
      json = JSON.generate(data.as_json(:allow_nan => true))
      SettingModel.set({ name: name, data: json }, scope: scope)
      LocalMode.save_setting(scope, name, json)
    end
  end
end
