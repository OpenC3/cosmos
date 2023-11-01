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

from openc3.api import WHITELIST
from openc3.environment import OPENC3_SCOPE
from openc3.utilities.authorization import authorize
from openc3.models.setting_model import SettingModel
from openc3.utilities.local_mode import LocalMode

WHITELIST.extend(
    [
        "list_settings",
        "get_all_settings",
        "get_setting",
        "get_settings",
        "set_setting",
        "save_setting",  # DEPRECATED
    ]
)


def list_settings(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    return SettingModel.names(scope=scope)


def get_all_settings(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    return SettingModel.all(scope=scope)


def get_setting(name, scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    setting = SettingModel.get(name=name, scope=scope)
    if setting:
        return setting["data"]
    else:
        return None


def get_settings(*settings, scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    result = []
    for name in settings:
        result.append(get_setting(name, scope))
    return result


def set_setting(name, data, local_mode=True, scope=OPENC3_SCOPE):
    authorize(permission="admin", scope=scope)
    SettingModel.set({"name": name, "data": data}, scope=scope)
    if local_mode:
        LocalMode.save_setting(scope, name, data)


# DEPRECATED
def save_setting(name, data, local_mode=True, scope=OPENC3_SCOPE):
    set_setting(name, data, local_mode, scope)
