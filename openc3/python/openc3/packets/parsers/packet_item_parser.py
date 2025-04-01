# Copyright 2025 OpenC3, Inc.
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

from openc3.packets.packet_item import PacketItem
from openc3.config.config_parser import ConfigParser
from openc3.utilities.logger import Logger
from openc3.utilities.extract import hex_to_byte_string, convert_to_value


class PacketItemParser:
    COMMAND = "Command"
    TELEMETRY = "Telemetry"

    # Parses a packet item definition and creates a new PacketItem

    # This number is a little arbitrary but there are definitely issues at
    # 1 million and you really shouldn't be doing anything this big anyway
    BIG_ARRAY_SIZE = 100_000

    # self.param parser [ConfigParser] Configuration parser
    # self.param packet [Packet] The packet the item should be added to
    # self.param cmd_or_tlm [String] Whether this is a command or telemetry packet
    # self.param warnings [Array<String>] Array of warning strings from PacketConfig
    @classmethod
    def parse(cls, parser, packet, cmd_or_tlm, warnings):
        parser = PacketItemParser(parser, warnings)
        parser.verify_parameters(cmd_or_tlm)
        return parser.create_packet_item(packet, cmd_or_tlm)

    # self.param parser [ConfigParser] Configuration parser
    # self.param warnings [Array<String>] Array of warning strings from PacketConfig
    def __init__(self, parser, warnings):
        self.parser = parser
        self.warnings = warnings
        self.usage = self._get_usage()

    def verify_parameters(self, cmd_or_tlm):
        if "ITEM" in self.parser.keyword and cmd_or_tlm == PacketItemParser.COMMAND:
            raise self.parser.error("ITEM types are only valid with TELEMETRY", self.usage)
        elif "PARAMETER" in self.parser.keyword and cmd_or_tlm == PacketItemParser.TELEMETRY:
            raise self.parser.error("PARAMETER types are only valid with COMMAND", self.usage)

        # The usage is formatted with brackets <XXX> around each option so
        # count the number of open brackets to determine the number of options
        max_options = self.usage.count("<")
        # The last two options (description and endianness) are optional
        self.parser.verify_num_parameters(max_options - 2, max_options, self.usage)
        self.parser.verify_parameter_naming(1)  # Item name is the 1st parameter

    def create_packet_item(self, packet, cmd_or_tlm):
        try:
            item_name = self.parser.parameters[0].upper()
            if packet.items.get(item_name):
                msg = f"{packet.target_name} {packet.packet_name} {item_name} redefined."
                Logger.warn(msg)
                self.warnings.append(msg)
            item = PacketItem(
                item_name,
                self._get_bit_offset(),
                self._get_bit_size(),
                self._get_data_type(),
                self._get_endianness(packet),
                self._get_array_size(),
                "ERROR",
            )  # overflow
            if cmd_or_tlm == PacketItemParser.COMMAND:
                item.minimum = self._get_minimum()
                item.maximum = self._get_maximum()
                item.default = self._get_default()
            item.id_value = self._get_id_value(item)
            item.description = self._get_description()
            if self._append():
                item = packet.append(item)
            else:
                item = packet.define(item)
            return item
        except Exception as error:
            raise self.parser.error(error, self.usage)

    def _append(self):
        return "APPEND" in self.parser.keyword

    def _get_data_type(self):
        index = 2 if self._append() else 3
        # _get_data_type is called in usage before we verify
        # the parameters so we must check the length here
        if index >= len(self.parser.parameters):
            return None
        return self.parser.parameters[index].upper()

    def _get_bit_offset(self):
        if self._append():
            return 0
        try:
            return int(self.parser.parameters[1])
        except ValueError as error:
            raise self.parser.error(error, self.usage)

    def _get_bit_size(self):
        index = 1 if self._append() else 2
        try:
            return int(self.parser.parameters[index])
        except ValueError as error:
            raise self.parser.error(error, self.usage)

    def _get_array_size(self):
        if "ARRAY" not in self.parser.keyword:
            return None

        try:
            index = 3 if self._append() else 4
            array_bit_size = int(self.parser.parameters[index])
            items = int(array_bit_size / self._get_bit_size())
            if items >= PacketItemParser.BIG_ARRAY_SIZE:
                warning = (
                    "Performance Issue!\n"
                    f"In {self.parser.filename}:{self.parser.line_number} your definition of=\n"
                    f"{self.parser.line}\n"
                    f"creates an array with {items} elements. Consider creating a BLOCK if this is binary data."
                )
                Logger.warn(warning)
                self.warnings.append(warning)
            return array_bit_size
        except ValueError as error:
            raise self.parser.error(error, self.usage)

    def _get_endianness(self, packet):
        params = self.parser.parameters
        max_options = self.usage.count("<")
        if len(params) >= max_options:
            endianness = params[max_options - 1].upper()
            if endianness != "BIG_ENDIAN" and endianness != "LITTLE_ENDIAN":
                raise self.parser.error(
                    f"Invalid endianness {endianness}. Must be BIG_ENDIAN or LITTLE_ENDIAN.",
                    self.usage,
                )
        else:
            endianness = packet.default_endianness
        return endianness

    def _get_minimum(self):
        if "ARRAY" in self.parser.keyword:
            return None

        data_type = self._get_data_type()
        if data_type == "STRING" or data_type == "BLOCK":
            return None

        index = 3 if self._append() else 4
        if self.parser.parameters[index] == "nil":
            return None
        return ConfigParser.handle_defined_constants(
            convert_to_value(self.parser.parameters[index]),
            self._get_data_type(),
            self._get_bit_size(),
        )

    def _get_maximum(self):
        if "ARRAY" in self.parser.keyword:
            return None

        data_type = self._get_data_type()
        if data_type == "STRING" or data_type == "BLOCK":
            return None

        index = 4 if self._append() else 5
        if self.parser.parameters[index] == "nil":
            return None
        return ConfigParser.handle_defined_constants(
            convert_to_value(self.parser.parameters[index]),
            self._get_data_type(),
            self._get_bit_size(),
        )

    def _convert_string_value(self, index):
        # If the default value is 0x<data> (no quotes), it is treated as
        # binary data. Otherwise, the default value is considered to be a string.
        if (
            self.parser.parameters[index].upper().startswith("0X")
            and f'"{self.parser.parameters[index]}"' not in self.parser.line
            and f"'{self.parser.parameters[index]}'" not in self.parser.line
        ):
            return hex_to_byte_string(self.parser.parameters[index])
        else:
            return self.parser.parameters[index]

    def _get_default(self):
        if "ARRAY" in self.parser.keyword:
            return []

        index = 3 if self._append() else 4
        data_type = self._get_data_type()
        if data_type == "STRING" or data_type == "BLOCK":
            return self._convert_string_value(index)
        else:
            if data_type != "DERIVED":
                return ConfigParser.handle_defined_constants(
                    convert_to_value(self.parser.parameters[index + 2]),
                    self._get_data_type(),
                    self._get_bit_size(),
                )
            else:
                return convert_to_value(self.parser.parameters[index + 2])

    def _get_id_value(self, item):
        if "ID_" not in self.parser.keyword:
            return None
        data_type = self._get_data_type()
        if data_type == "DERIVED":
            raise self.parser.error("DERIVED data type not allowed for Identifier")
        # For PARAMETERS the default value is the ID value
        if "PARAMETER" in self.parser.keyword:
            return item.default

        index = 3 if self._append() else 4
        if data_type == "STRING" or data_type == "BLOCK":
            return self._convert_string_value(index)
        else:
            return ConfigParser.handle_defined_constants(
                convert_to_value(self.parser.parameters[index]),
                self._get_data_type(),
                self._get_bit_size(),
            )

    def _get_description(self):
        max_options = self.usage.count("<")
        if len(self.parser.parameters) >= max_options - 1:
            return self.parser.parameters[max_options - 2]
        return None

    # There are many different usages of the ITEM and PARAMETER keywords so
    # parse the keyword and parameters to generate the correct usage information.
    def _get_usage(self):
        keyword = self.parser.keyword or ""
        usage = f"{keyword} <ITEM NAME> "
        if "APPEND" not in keyword:
            usage += "<BIT OFFSET> "
        usage += self._bit_size_usage()
        usage += self._type_usage()
        if "ARRAY" in keyword:
            usage += "<TOTAL ARRAY BIT SIZE> "
        usage += self._id_usage()
        usage += "<DESCRIPTION (Optional)> <ENDIANNESS (Optional)>"
        return usage

    def _bit_size_usage(self):
        keyword = self.parser.keyword or ""
        if "ARRAY" in keyword:
            return "<ARRAY ITEM BIT SIZE> "
        else:
            return "<BIT SIZE> "

    def _type_usage(self):
        keyword = self.parser.keyword or ""
        # Item type usage is simple so just return it
        if "ITEM" in keyword:
            return "<TYPE: INT/UINT/FLOAT/STRING/BLOCK/DERIVED> "

        # Build up the parameter type usage based on the keyword
        usage = "<TYPE: "
        # ARRAY types don't have min or max or default values
        if "ARRAY" in keyword:
            usage += "INT/UINT/FLOAT/STRING/BLOCK> "
        else:
            try:
                data_type = self._get_data_type()
            except TypeError:
                # If the data type could not be determined set something
                data_type = "INT"
            # STRING and BLOCK types do not have min or max values
            if data_type == "STRING" or data_type == "BLOCK":
                usage += "STRING/BLOCK> "
            else:
                usage += "INT/UINT/FLOAT> <MIN VALUE> <MAX VALUE> "
            # ID Values do not have default values
            if "ID" not in keyword:
                usage += "<DEFAULT_VALUE> "
        return usage

    def _id_usage(self):
        keyword = self.parser.keyword or ""
        if "ID" not in keyword:
            return ""

        if "PARAMETER" in keyword:
            return "<DEFAULT AND ID VALUE> "
        else:
            return "<ID VALUE> "
