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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/models/tool_config_model'

module OpenC3
  module Api
    WHITELIST ||= []
    WHITELIST.concat([
      'config_tool_names',
      'list_configs',
      'load_config',
      'save_config',
      'delete_config'
    ])

    def config_tool_names(manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      ToolConfigModel.config_tool_names(scope: scope)
    end

    def list_configs(tool, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      ToolConfigModel.list_configs(tool, scope: scope)
    end

    def load_config(tool, name, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system', manual: manual, scope: scope, token: token)
      ToolConfigModel.load_config(tool, name, scope: scope)
    end

    def save_config(tool, name, data, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system_set', manual: manual, scope: scope, token: token)
      ToolConfigModel.save_config(tool, name, data, scope: scope)
    end

    def delete_config(tool, name, manual: false, scope: $openc3_scope, token: $openc3_token)
      authorize(permission: 'system_set', manual: manual, scope: scope, token: token)
      ToolConfigModel.delete_config(tool, name, scope: scope)
    end
  end
end
