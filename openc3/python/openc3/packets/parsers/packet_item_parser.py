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

from ast import literal_eval

from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_item import PacketItem
from openc3.utilities.extract import convert_to_value, hex_to_byte_string
from openc3.utilities.logger import Logger


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
    def parse(cls, parser, packet_config, packet, cmd_or_tlm, warnings):
        parser = PacketItemParser(parser, packet_config, warnings)
        parser.verify_parameters(cmd_or_tlm)
        return parser.create_packet_item(packet, cmd_or_tlm)

    # self.param parser [ConfigParser] Configuration parser
    # self.param warnings [Array<String>] Array of warning strings from PacketConfig
    def __init__(self, parser, packet_config, warnings):
        self.parser = parser
        self.packet_config = packet_config
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
        if "STRUCTURE" in self.parser.keyword:
            self.parser.verify_num_parameters(max_options, max_options, self.usage)
        else:
            # The last two options (description and endianness) are optional
            self.parser.verify_num_parameters(max_options - 2, max_options, self.usage)
        self.parser.verify_parameter_naming(1)  # Item name is the 1st parameter

        # ARRAY items cannot have brackets in their name because brackets are used
        # for array indexing in the UI and would cause confusion
        if "ARRAY" in self.parser.keyword:
            item_name = self.parser.parameters[0]
            if "[" in item_name or "]" in item_name:
                raise self.parser.error(f"ARRAY items cannot have brackets in their name: {item_name}", self.usage)

    def create_packet_item(self, packet, cmd_or_tlm):
        try:
            item_name = self.parser.parameters[0].upper()
            if packet.items.get(item_name):
                msg = f"{packet.target_name} {packet.packet_name} {item_name} redefined."
                Logger.warn(msg)
                self.warnings.append(msg)
            if "STRUCTURE" in self.parser.keyword:
                item = PacketItem(
                    item_name,
                    self._get_bit_offset(),
                    self._get_bit_size(True),
                    "BLOCK",
                    "BIG_ENDIAN",
                    None,
                    "ERROR",  # overflow
                )
            else:
                item = PacketItem(
                    item_name,
                    self._get_bit_offset(),
                    self._get_bit_size(),
                    self._get_data_type(),
                    self._get_endianness(packet),
                    self._get_array_size(),
                    "ERROR",  # overflow
                )
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
            if "STRUCTURE" in self.parser.keyword:
                structure = self._lookup_packet(
                    self._get_cmd_or_tlm(), self._get_target_name(), self._get_packet_name()
                )
                packet.structurize_item(item, structure)
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
            return int(self.parser.parameters[1], 0)
        except ValueError as error:
            raise self.parser.error(error, self.usage)

    def _get_bit_size(self, check_structure=False):
        index = 1 if self._append() else 2
        try:
            bit_size = self.parser.parameters[index]
            if not check_structure or str(bit_size).upper() != "DEFINED":
                return int(bit_size, 0)
            else:
                structure = self._lookup_packet(
                    self._get_cmd_or_tlm(), self._get_target_name(), self._get_packet_name()
                )
                return structure.defined_length_bits

        except ValueError as error:
            raise self.parser.error(error, self.usage)

    def _get_array_size(self):
        if "ARRAY" not in self.parser.keyword:
            return None

        try:
            index = 3 if self._append() else 4
            array_bit_size = int(self.parser.parameters[index], 0)
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
        if data_type != "INT" and data_type != "UINT" and data_type != "FLOAT":
            return None

        index = 3 if self._append() else 4
        value = self.parser.parameters[index]
        if str(value).upper() == "NIL" or str(value).upper() == "NONE":
            return None
        return ConfigParser.handle_defined_constants(
            convert_to_value(value),
            self._get_data_type(),
            self._get_bit_size(),
        )

    def _get_maximum(self):
        if "ARRAY" in self.parser.keyword:
            return None

        data_type = self._get_data_type()
        if data_type != "INT" and data_type != "UINT" and data_type != "FLOAT":
            return None

        index = 4 if self._append() else 5
        value = self.parser.parameters[index]
        if str(value).upper() == "NIL" or str(value).upper() == "NONE":
            return None
        return ConfigParser.handle_defined_constants(
            convert_to_value(value),
            self._get_data_type(),
            self._get_bit_size(),
        )

    def _get_cmd_or_tlm(self):
        index = 2 if self._append() else 3
        cmd_or_tlm = str(self.parser.parameters[index])
        if cmd_or_tlm not in ["CMD", "TLM", "COMMAND", "TELEMETRY"]:
            raise TypeError(f"Unknown type: {cmd_or_tlm}")
        return cmd_or_tlm

    def _get_target_name(self):
        index = 3 if self._append() else 4
        return str(self.parser.parameters[index]).upper()

    def _get_packet_name(self):
        index = 4 if self._append() else 5
        return str(self.parser.parameters[index]).upper()

    def _lookup_packet(self, cmd_or_tlm, target_name, packet_name):
        if cmd_or_tlm == "CMD" or cmd_or_tlm == "COMMAND":
            return self.packet_config.commands[target_name][packet_name]
        else:
            return self.packet_config.telemetry[target_name][packet_name]

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
        if data_type == "BOOL":
            value = str(self.parser.parameters[index]).upper()
            if value == "TRUE" or value == "FALSE":
                return ConfigParser.handle_true_false(self.parser.parameters[index])
            else:
                raise self.parser.error("Default for BOOL data type must be TRUE or FALSE")
        if data_type == "ARRAY":
            value = str(self.parser.parameters[index])
            try:
                value = literal_eval(value)
            except Exception:
                raise self.parser.error(f"Unparsable value for ARRAY: {value}")
            if isinstance(value, list):
                return value
            else:
                raise self.parser.error("Default for ARRAY data type must be an Array")
        if data_type == "OBJECT":
            value = str(self.parser.parameters[index])
            try:
                value = literal_eval(value)
            except Exception:
                raise self.parser.error(f"Unparsable value for OBJECT: {value}")
            if isinstance(value, dict):
                return value
            else:
                raise self.parser.error("Default for OBJECT data type must be a Hash")
        if data_type == "ANY":
            value = str(self.parser.parameters[index])
            if len(value) > 0:
                try:
                    return literal_eval(value)
                except Exception:
                    return value
            else:
                return ""
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
        if data_type == "BOOL":
            value = str(self.parser.parameters[index]).upper()
            if value == "TRUE" or value == "FALSE":
                return ConfigParser.handle_true_false(self.parser.parameters[index])
            else:
                raise self.parser.error("ID Value for BOOL data type must be TRUE or FALSE")
        if data_type == "ARRAY":
            value = str(self.parser.parameters[index])
            try:
                value = literal_eval(value)
            except Exception:
                raise self.parser.error(f"Unparsable value for ARRAY: {value}")
            if isinstance(value, list):
                return value
            else:
                raise self.parser.error("ID Value for ARRAY data type must be an Array")
        if data_type == "OBJECT":
            value = str(self.parser.parameters[index])
            try:
                value = literal_eval(value)
            except Exception:
                raise self.parser.error(f"Unparsable value for OBJECT: {value}")
            if isinstance(value, dict):
                return value
            else:
                raise self.parser.error("ID Value for OBJECT data type must be a Hash")
        if data_type == "ANY":
            value = str(self.parser.parameters[index])
            if len(value) > 0:
                try:
                    return literal_eval(value)
                except Exception:
                    return value
            else:
                return ""
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
        if "STRUCTURE" not in self.parser.keyword:
            usage += self._type_usage()
            if "ARRAY" in keyword:
                usage += "<TOTAL ARRAY BIT SIZE> "
            usage += self._id_usage()
            usage += "<DESCRIPTION (Optional)> <ENDIANNESS (Optional)>"
        else:
            usage += "<CMD or TLM> <Target Name> <Packet Name>"
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
            return "<TYPE: INT/UINT/FLOAT/STRING/BLOCK/DERIVED/BOOL/ARRAY/OBJECT/ANY> "

        # Build up the parameter type usage based on the keyword
        usage = "<TYPE: "
        # ARRAY types don't have min or max or default values
        if "ARRAY" in keyword:
            usage += "INT/UINT/FLOAT/STRING/BLOCK/BOOL/OBJECT/ANY> "
        else:
            try:
                data_type = self._get_data_type()
            except TypeError:
                # If the data type could not be determined set something
                data_type = "INT"
            if data_type == "INT" or data_type == "UINT" or data_type == "FLOAT" or data_type == "DERIVED":
                usage += "INT/UINT/FLOAT/DERIVED> <MIN VALUE> <MAX VALUE> "
            else:
                usage += "STRING/BLOCK/BOOL/ARRAY/OBJECT/ANY> "
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
