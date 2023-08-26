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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import importlib
from openc3.utilities.string import filename_to_class_name


class LimitsResponseParser:
    # self.param parser [ConfigParser] Configuration parser
    # self.param item [Packet] The current item
    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    @classmethod
    def parse(cls, parser, item, cmd_or_tlm):
        parser = LimitsResponseParser(parser)
        parser.verify_parameters(cmd_or_tlm)
        parser.create_limits_response(item)

    # self.param parser [ConfigParser] Configuration parser
    def __init__(self, parser):
        self.parser = parser

    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    def verify_parameters(self, cmd_or_tlm):
        if cmd_or_tlm == "Command":
            raise self.parser.error("LIMITS_RESPONSE only applies to telemetry items")

        self.usage = (
            "LIMITS_RESPONSE <RESPONSE CLASS FILENAME> <RESPONSE SPECIFIC OPTIONS>"
        )
        self.parser.verify_num_parameters(1, None, self.usage)

    # self.param item [PacketItem] The item the limits response should be added to
    def create_limits_response(self, item):
        try:
            class_name = filename_to_class_name(self.parser.parameters[0])
            my_module = importlib.import_module(
                self.parser.parameters[0], "openc3.packets"
            )
            klass = getattr(my_module, class_name)()
            if self.parser.parameters[1]:
                item.limits.response = klass(
                    *self.parser.parameters[1 : len(self.parser.parameters)]
                )
            else:
                item.limits.response = klass()
        except ModuleNotFoundError as error:
            raise self.parser.error(error, self.usage)
