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


class FormatStringParser:
    # self.param parser [ConfigParser] Configuration parser
    # self.param item [Packet] The current item
    @classmethod
    def parse(cls, parser, item):
        parser = FormatStringParser(parser)
        parser.verify_parameters()
        parser.create_format_string(item)

    # self.param parser [ConfigParser] Configuration parser
    def __init__(self, parser):
        self.parser = parser

    def verify_parameters(self):
        self.usage = "FORMAT_STRING <PRINTF STYLE STRING>"
        self.parser.verify_num_parameters(1, 1, self.usage)

    # self.param item [PacketItem] The item the limits response should be added to
    def create_format_string(self, item):
        item.format_string = self.parser.parameters[0]
        # Only test the format string if there is not a read conversion because:
        # read conversion can return any type
        if item.read_conversion is None:
            self._test_format_string(item)

    def _test_format_string(self, item):
        try:
            match item.data_type:
                case "INT" | "UINT":
                    f"{item.format_string}" % 0
                case "FLOAT":
                    f"{item.format_string}" % 0.0
                case "STRING" | "BLOCK":
                    f"{item.format_string}" % "Hello"
        except TypeError as error:
            raise self.parser.error(
                f"Invalid FORMAT_STRING specified for type {item.data_type}: {self.parser.parameters[0]}",
                self.usage,
            ) from error
