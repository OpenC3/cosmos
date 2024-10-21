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
from openc3.models.target_model import TargetModel
from openc3.models.interface_model import InterfaceModel

WHITELIST.extend(
    [
        "get_target_names",
        "get_target",
        "get_target_interfaces",
    ]
)


# Returns the list of all target names
#
# @return [Array<String>] All target names
def get_target_names(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    return TargetModel.names(scope=scope)


# Gets the full target hash
#
# @since 5.0.0
# @param target_name [String] Target name
# @return [Hash] Hash of all the target properties
def get_target(target_name, scope=OPENC3_SCOPE):
    authorize(permission="system", target_name=target_name, scope=scope)
    return TargetModel.get(name=target_name, scope=scope)


# Get all targets and their interfaces
#
# @return [Array<Array<String, String] Array of Arrays \[name, interfaces]
def get_target_interfaces(scope=OPENC3_SCOPE):
    authorize(permission="system", scope=scope)
    info = []
    interfaces = InterfaceModel.all(scope=scope)
    for target_name in get_target_names(scope=scope):
        interface_names = []
        for _, interface in interfaces.items():
            if target_name in interface["target_names"]:
                interface_names.append(interface["name"])
        info.append([target_name, ",".join(interface_names)])
    return info
