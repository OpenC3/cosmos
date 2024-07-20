# encoding: ascii-8bit

# Copyright 2022 OpenC3, Inc
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/offline_access_model'
require 'openc3/utilities/authentication'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
                       'offline_access_needed',
                       'set_offline_access'
                     ])

    def offline_access_needed(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', scope: scope, token: token)
      begin
        authorize(permission: 'script_run', manual: manual, scope: scope, token: token)
      rescue
        # Not needed if can't run scripts
        return false
      end
      info = user_info(token)
      if info['roles'].to_s.include?("offline_access")
        username = info['username']
        if username and username != ''
          model = OfflineAccessModel.get_model(name: username, scope: scope)
          if model and model.offline_access_token
            auth = OpenC3KeycloakAuthentication.new(ENV['OPENC3_KEYCLOAK_URL'])
            valid_token = auth.get_token_from_refresh_token(model.offline_access_token)
            if valid_token
              return false
            else
              model.offline_access_token = nil
              model.update
              return true
            end
          end
          return true
        else
          return false
        end
      else
        return false
      end
    end

    def set_offline_access(offline_access_token, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'script_run', manual: manual, scope: scope, token: token)
      info = user_info(token)
      username = info['username']
      raise "Invalid username" if not username or username == ''
      model = OfflineAccessModel.get_model(name: username, scope: scope)
      if model
        model.offline_access_token = offline_access_token
        model.update
      else
        model = OfflineAccessModel.new(name: username, offline_access_token: offline_access_token, scope: scope)
        model.create
      end
    end
  end
end
