# Copyright 2023 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.models.interface_model import InterfaceModel


class RouterModel(InterfaceModel):
    pass
    # # Called by the PluginModel to allow this class to validate it's top-level keyword: "ROUTER"
    # @classmethod
    # def handle_config(
    #     cls,
    #     parser,
    #     keyword,
    #     parameters,
    #     plugin=None,
    #     needs_dependencies=False,
    #     scope=None,
    # ):
    #     match keyword:
    #         case "ROUTER":
    #             parser.verify_num_parameters(
    #                 2, None, "ROUTER <Name> <Filename> <Specific Parameters>"
    #             )
    #             return RouterModel(
    #                 name=parameters[0].upper(),
    #                 config_params=parameters[1:],
    #                 plugin=plugin,
    #                 needs_dependencies=needs_dependencies,
    #                 scope=scope,
    #             )
    #         case _:
    #             raise ConfigParser.Error(
    #                 parser,
    #                 f"Unknown keyword and parameters for Router: {keyword} {' '.join(parameters)}",
    #             )
