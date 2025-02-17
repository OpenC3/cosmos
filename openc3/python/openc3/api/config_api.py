# Copyright 2023 OpenC3, Inc
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
# if purchased from OpenC3, Inc.:

import json
from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.models.tool_config_model import ToolConfigModel

WHITELIST.extend(["config_tool_names", "list_configs", "load_config", "save_config", "delete_config"])


def config_tool_names(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    return ToolConfigModel.config_tool_names(scope=scope)


def list_configs(tool, scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    return ToolConfigModel.list_configs(tool, scope=scope)


def load_config(tool, name, scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    return json.loads(ToolConfigModel.load_config(tool, name, scope=scope))


def save_config(tool, name, data, local_mode=True, scope=OPENC3_SCOPE):
    authorize(permission="system_set", scope=scope)
    ToolConfigModel.save_config(tool, name, data, local_mode, scope)


def delete_config(tool, name, local_mode=True, scope=OPENC3_SCOPE):
    authorize(permission="system_set", scope=scope)
    ToolConfigModel.delete_config(tool, name, local_mode, scope)
