# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import re
import copy
from openc3.packets.structure_item import StructureItem
from openc3.packets.packet_item_limits import PacketItemLimits
from openc3.utilities.string import quote_if_necessary, simple_formatted
from openc3.conversions.conversion import Conversion


class PacketItem(StructureItem):
    # The allowable state colors
    STATE_COLORS = ["GREEN", "YELLOW", "RED"]

    def __init__(
        self,
        name,
        bit_offset,
        bit_size,
        data_type,
        endianness,
        array_size=None,
        overflow="ERROR",
    ):
        super().__init__(name, bit_offset, bit_size, data_type, endianness, array_size, overflow)
        self.format_string = None
        self.read_conversion = None
        self.write_conversion = None
        self.id_value = None
        self.states = None
        self.description = None
        self.units_full = None
        self.units = None
        self.default = None
        # self.range = None
        self.minimum = None
        self.maximum = None
        self.required = False
        self.hazardous = None
        self.messages_disabled = None
        self.state_colors = None
        self.limits = PacketItemLimits()
        self.persistence_setting = 1
        self.persistence_count = 0
        self.meta = None

    @property
    def format_string(self):
        return self.__format_string

    @format_string.setter
    def format_string(self, format_string):
        if format_string:
            if not isinstance(format_string, str):
                raise TypeError(
                    f"{self.name}: format_string must be a str but is a {format_string.__class__.__name__}"
                )
            if not re.search(r"%.*(b|B|d|i|o|u|x|X|e|E|f|g|G|a|A|c|p|s|%)", format_string):
                raise ValueError(f"{self.name}: format_string invalid '{format_string}'")
            self.__format_string = format_string
        else:
            self.__format_string = None

    @property
    def read_conversion(self):
        return self.__read_conversion

    @read_conversion.setter
    def read_conversion(self, read_conversion):
        if read_conversion:
            if not isinstance(read_conversion, Conversion):
                raise TypeError(
                    f"{self.name}: read_conversion must be a Conversion but is a {read_conversion.__class__.__name__}"
                )
            self.__read_conversion = read_conversion
        else:
            self.__read_conversion = None

    @property
    def write_conversion(self):
        return self.__write_conversion

    @write_conversion.setter
    def write_conversion(self, write_conversion):
        if write_conversion:
            if not isinstance(write_conversion, Conversion):
                raise TypeError(
                    f"{self.name}: write_conversion must be a Conversion but is a {write_conversion.__class__.__name__}"
                )
            self.__write_conversion = write_conversion
        else:
            self.__write_conversion = None

    @property
    def id_value(self):
        return self.__id_value

    @id_value.setter
    def id_value(self, id_value):
        if id_value is not None:
            self.__id_value = self.convert(id_value, self.data_type)
        else:
            self.__id_value = None

    # Assignment operator for states to make sure it is a dict with uppercase keys
    @property
    def states(self):
        return self.__states

    @states.setter
    def states(self, states):
        if states is not None:
            if not isinstance(states, dict):
                raise TypeError(f"{self.name}: states must be a dict but is a {states.__class__.__name__}")

            # Make sure all states are in upper case
            self.__states = {}
            self.__states_by_value = {}
            for key, value in states.items():
                upper = key.upper()
                self.__states[upper] = value
                self.__states_by_value[value] = upper
            if self.state_colors is None:
                self.state_colors = {}
        else:
            self.__states = None
            self.__states_by_value = None

    def states_by_value(self):
        return self.__states_by_value

    @property
    def description(self):
        return self.__description

    @description.setter
    def description(self, description):
        if description:
            if not isinstance(description, str):
                raise TypeError(
                    f"{self.name}: description must be a str but is a {description.__class__.__name__}"
                )
            self.__description = description
        else:
            self.__description = None

    @property
    def units_full(self):
        return self.__units_full

    @units_full.setter
    def units_full(self, units_full):
        if units_full:
            if not isinstance(units_full, str):
                raise TypeError(f"{self.name}: units_full must be a str but is a {units_full.__class__.__name__}")
            self.__units_full = units_full
        else:
            self.__units_full = None

    @property
    def units(self):
        return self.__units

    @units.setter
    def units(self, units):
        if units:
            if not isinstance(units, str):
                raise TypeError(f"{self.name}: units must be a str but is a {units.__class__.__name__}")
            self.__units = units
        else:
            self.__units = None

    def check_default_and_range_data_types(self):
        if self.default and not self.write_conversion:
            if self.array_size is not None:
                if not isinstance(self.default, list):
                    raise TypeError(
                        f"{self.name}: default must be a list but is a {self.default.__class__.__name__}"
                    )
            else:
                match self.data_type:
                    case "INT" | "UINT":
                        if not isinstance(self.default, int):
                            raise TypeError(
                                f"{self.name}: default must be a int but is a {self.default.__class__.__name__}"
                            )
                        if not isinstance(self.minimum, int):
                            raise TypeError(
                                f"{self.name}: minimum must be a int but is a {self.minimum.__class__.__name__}"
                            )
                        if not isinstance(self.maximum, int):
                            raise TypeError(
                                f"{self.name}: maximum must be a int but is a {self.maximum.__class__.__name__}"
                            )
                    case "FLOAT":
                        if not isinstance(self.default, (float, int)):
                            raise TypeError(
                                f"{self.name}: default must be a float but is a {self.default.__class__.__name__}"
                            )

                        self.default = float(self.default)

                        if not isinstance(self.minimum, (int, float)):
                            raise TypeError(
                                f"{self.name}: minimum must be a float but is a {self.minimum.__class__.__name__}"
                            )
                        if not isinstance(self.maximum, (int, float)):
                            raise TypeError(
                                f"{self.name}: maximum must be a float but is a {self.maximum.__class__.__name__}"
                            )
                    case "BLOCK" | "STRING":
                        if not isinstance(self.default, (str, bytes, bytearray)):
                            raise TypeError(
                                f"{self.name}: default must be a str but is a {self.default.__class__.__name__}"
                            )

    @property
    def hazardous(self):
        return self.__hazardous

    @hazardous.setter
    def hazardous(self, hazardous):
        if hazardous is not None:
            if not isinstance(hazardous, dict):
                raise TypeError(f"{self.name}: hazardous must be a dict but is a {hazardous.__class__.__name__}")
            self.__hazardous = hazardous
        else:
            self.__hazardous = None

    @property
    def messages_disabled(self):
        return self.__messages_disabled

    @messages_disabled.setter
    def messages_disabled(self, messages_disabled):
        if messages_disabled is not None:
            if not isinstance(messages_disabled, dict):
                raise TypeError(
                    f"{self.name}: messages_disabled must be a dict but is a {messages_disabled.__class__.__name__}"
                )

            self.__messages_disabled = messages_disabled
        else:
            self.__messages_disabled = None

    @property
    def state_colors(self):
        return self.__state_colors

    @state_colors.setter
    def state_colors(self, state_colors):
        if state_colors is not None:
            if not isinstance(state_colors, dict):
                raise TypeError(
                    f"{self.name}: state_colors must be a dict but is a {state_colors.__class__.__name__}"
                )

            self.__state_colors = state_colors
        else:
            self.__state_colors = None

    @property
    def limits(self):
        return self.__limits

    @limits.setter
    def limits(self, limits):
        if limits is not None:
            if not isinstance(limits, PacketItemLimits):
                raise TypeError(
                    f"{self.name}: limits must be a PacketItemLimits but is a {limits.__class__.__name__}"
                )

            self.__limits = limits
        else:
            self.__limits = None

    @property
    def meta(self):
        return self.__meta

    @meta.setter
    def meta(self, meta):
        if meta is not None:
            if not isinstance(meta, dict):
                raise TypeError(f"{self.name}: meta must be a dict but is a {meta.__class__.__name__}")

            self.__meta = meta
        else:
            self.__meta = {}

    # Make a light weight clone of this item
    def clone(self):
        item = copy.copy(self)
        # Since we're copying and not calling the constructor
        # we have to manually update the create_index
        item.create_index = StructureItem.create_index
        StructureItem.create_index += 1
        return item

    # def clone(self):
    #   item = super().clone()
    #   item.format_string = self.format_string.clone if self.format_string:
    #   item.read_conversion = self.read_conversion.clone if self.read_conversion:
    #   item.write_conversion = self.write_conversion.clone if self.write_conversion:
    #   item.states = self.states.clone if self.states:
    #   item.description = self.description.clone if self.description:
    #   item.units_full = self.units_full.clone if self.units_full:
    #   item.units = self.units.clone if self.units:
    #   item.default = self.default.clone if self.default and String === self.default:
    #   item.hazardous = self.hazardous.clone if self.hazardous:
    #   item.messages_disabled = self.messages_disabled.clone if self.messages_disabled:
    #   item.state_colors = self.state_colors.clone if self.state_colors:
    #   item.limits = self.limits.clone if self.limits:
    #   item.meta = self.meta.clone if self.meta:
    #   item

    def to_hash(self):
        item = {}
        item["format_string"] = self.format_string
        if self.read_conversion:
            item["read_conversion"] = str(self.read_conversion)
        else:
            item["read_conversion"] = None
        if self.write_conversion:
            item["write_conversion"] = str(self.write_conversion)
        else:
            item["write_conversion"] = None
        item["id_value"] = self.id_value
        item["states"] = self.states
        item["description"] = self.description
        item["units_full"] = self.units_full
        item["units"] = self.units
        item["default"] = self.default
        # item["range"] = self.range
        item["minimum"] = self.minimum
        item["maximum"] = self.maximum
        item["required"] = self.required
        item["hazardous"] = self.hazardous
        item["messages_disabled"] = self.messages_disabled
        item["state_colors"] = self.state_colors
        item["limits"] = self.limits.as_json()
        item["meta"] = None
        if self.meta:
            item["meta"] = self.meta
        return item

    # def calculate_range(self):
    #     first = self.range.first
    #     last = self.range.last
    #     if self.data_type == "FLOAT":
    #         if self.bit_size == 32:
    #             if self.range.first == -3.402823e38:
    #                 first = "MIN"
    #             if self.range.last == 3.402823e38:
    #                 last = "MAX"
    #         else:
    #             if self.range.first == -sys.float_info.max:
    #                 first = "MIN"
    #             if self.range.last == sys.float_info.max:
    #                 last = "MAX"
    #     return [first, last]

    def to_config(self, cmd_or_tlm, default_endianness):
        config = ""
        if self.description:
            description = self.description.replace('"', "'")
        else:
            description = ""
        if cmd_or_tlm == "TELEMETRY":
            if self.array_size is not None:
                config += f'  ARRAY_ITEM {quote_if_necessary(self.name)} {self.bit_offset} {self.bit_size} {self.data_type} {self.array_size} "{description}"'
            elif self.id_value:
                id_value = self.id_value
                if self.data_type == "BLOCK" or self.data_type == "STRING":
                    if not self.id_value.isascii():
                        id_value = "0x" + simple_formatted(self.id_value)
                    else:
                        id_value = f'"{self.id_value}"'
                config += f'  ID_ITEM {quote_if_necessary(self.name)} {self.bit_offset} {self.bit_size} {self.data_type} {id_value} "{description}"'
            else:
                config += f'  ITEM {quote_if_necessary(self.name)} {self.bit_offset} {self.bit_size} {self.data_type} "{description}"'
        else:  # 'COMMAND'
            if self.array_size is not None:
                config += f'  ARRAY_PARAMETER {quote_if_necessary(self.name)} {self.bit_offset} {self.bit_size} {self.data_type} {self.array_size} "{description}"'
            else:
                config += self.parameter_config()
        if self.endianness != default_endianness and self.data_type != "STRING" and self.data_type != "BLOCK":
            config += " {self.endianness}"
        config += "\n"

        if self.required:
            config += "    REQUIRED\n"
        if self.format_string:
            config += f"    FORMAT_STRING {quote_if_necessary(self.format_string)}\n"
        if self.units:
            config += f"    UNITS {quote_if_necessary(self.units_full)} {quote_if_necessary(self.units)}\n"
        if self.overflow != "ERROR":
            config += f"    OVERFLOW {self.overflow}\n"

        if self.states:
            for state_name, state_value in self.states.items():
                config += f"    STATE {quote_if_necessary(state_name)} {quote_if_necessary(str(state_value))}"
                if self.hazardous and self.hazardous[state_name]:
                    config += f" HAZARDOUS {quote_if_necessary(self.hazardous[state_name])}"
                if self.messages_disabled and self.messages_disabled[state_name]:
                    config += " DISABLE_MESSAGES"
                if self.state_colors and self.state_colors[state_name]:
                    config += f" {self.state_colors[state_name]}"
                config += "\n"

        if self.read_conversion:
            config += self.read_conversion.to_config("READ")
        if self.write_conversion:
            config += self.write_conversion.to_config("WRITE")

        if self.limits:
            if self.limits.values:
                for limits_set, limits_values in self.limits.values.items():
                    config += f"    LIMITS {limits_set} {self.limits.persistence_setting} {'ENABLED' if self.limits.enabled else 'DISABLED'} {limits_values[0]} {limits_values[1]} {limits_values[2]} {limits_values[3]}"
                    if len(limits_values) > 4:
                        config += f" {limits_values[4]} {limits_values[5]}\n"
                    else:
                        config += "\n"
            if self.limits.response:
                config += self.limits.response.to_config

        if self.meta:
            for key, values in self.meta.items():
                vals = " ".join([quote_if_necessary(x) for x in values])
                config += f"    META {quote_if_necessary(key)} {vals}\n"

        return config

    def as_json(self):
        config = {}
        config["name"] = self.name
        config["bit_offset"] = self.bit_offset
        config["bit_size"] = self.bit_size
        config["data_type"] = self.data_type
        if self.array_size is not None:
            config["array_size"] = self.array_size
        config["description"] = self.description
        if self.id_value is not None:
            config["id_value"] = self.id_value
        if self.default is not None:
            config["default"] = self.default
        config["minimum"] = self.minimum
        config["maximum"] = self.maximum
        config["endianness"] = self.endianness
        config["required"] = self.required
        if self.format_string:
            config["format_string"] = self.format_string
        if self.units:
            config["units"] = self.units
            config["units_full"] = self.units_full
        config["overflow"] = self.overflow
        if self.states:
            states = {}
            config["states"] = states
            for state_name, state_value in self.states.items():
                state = {}
                states[state_name] = state
                state["value"] = state_value
                if self.hazardous and self.hazardous.get(state_name) is not None:
                    state["hazardous"] = self.hazardous[state_name]
                if self.messages_disabled and self.messages_disabled.get(state_name) is not None:
                    state["messages_disabled"] = self.messages_disabled[state_name]
                if self.state_colors and self.state_colors.get(state_name) is not None:
                    state["color"] = self.state_colors[state_name]

        if self.read_conversion:
            config["read_conversion"] = self.read_conversion.as_json()
        if self.write_conversion:
            config["write_conversion"] = self.write_conversion.as_json()

        if self.limits:
            config["limits"] = {}
            if self.limits.enabled:
                config["limits"]["enabled"] = True
            else:
                config["limits"]["enabled"] = False
            if self.limits.values:
                config["limits"]["persistence_setting"] = self.limits.persistence_setting
                if self.limits.response:
                    config["limits"]["response"] = self.limits.response
                for limits_set, limits_values in self.limits.values.items():
                    limits = {}
                    limits["red_low"] = limits_values[0]
                    limits["yellow_low"] = limits_values[1]
                    limits["yellow_high"] = limits_values[2]
                    limits["red_high"] = limits_values[3]
                    if len(limits_values) > 4:
                        limits["green_low"] = limits_values[4]
                        limits["green_high"] = limits_values[5]
                    config["limits"][limits_set] = limits
            if self.limits.response:
                config["limits_response"] = self.limits.response.as_json()

        if self.meta:
            config["meta"] = self.meta
        return config

    @classmethod
    def from_json(cls, item_hash):
        # Convert strings to symbols
        endianness = item_hash.get("endianness")
        data_type = item_hash.get("data_type")
        overflow = item_hash.get("overflow")
        item = PacketItem(
            item_hash.get("name"),
            item_hash.get("bit_offset"),
            item_hash.get("bit_size"),
            data_type,
            endianness,
            item_hash.get("array_size"),
            overflow,
        )
        item.description = item_hash.get("description")
        item.id_value = item_hash.get("id_value")
        item.default = item_hash.get("default")
        item.minimum = item_hash.get("minimum")
        item.maximum = item_hash.get("maximum")
        item.required = item_hash.get("required")
        item.format_string = item_hash.get("format_string")
        item.units = item_hash.get("units")
        item.units_full = item_hash.get("units_full")
        if item_hash.get("states"):
            item.states = {}
            item.hazardous = {}
            item.messages_disabled = {}
            item.state_colors = {}
            for state_name, state in item_hash.get("states").items():
                item.states[state_name] = state.get("value")
                item.hazardous[state_name] = state.get("hazardous")
                item.messages_disabled[state_name] = state.get("messages_disabled")
                item.state_colors[state_name] = state.get("color")
        # Recreate OpenC3 built-in conversions
        #   if item_hash.get('read_conversion']:
        #     try:
        #       item.read_conversion = OpenC3::const_get(item_hash['read_conversion']['class'])(*item_hash['read_conversion']['params'])
        #     except:
        #       Logger.error(f"{item.name} read_conversion of {item_hash['read_conversion']} could not be instantiated due to {error}")
        #   if item_hash.get('write_conversion']:
        #     try:
        #       item.write_conversion = OpenC3::const_get(item_hash['write_conversion']['class'])(*item_hash['write_conversion']['params'])
        #     except:
        #       Logger.error(f"{item.name} write_conversion of {item_hash['write_conversion']} could not be instantiated due to {error}")

        item.limits = PacketItemLimits()
        if item_hash.get("limits"):
            # Delete the keys so the only ones left are limits sets
            persistence_setting = item_hash["limits"].pop("persistence_setting", None)
            if persistence_setting:
                item.limits.persistence_setting = persistence_setting
            item_hash["limits"].pop("response", None)  # Can't round trip response
            if item_hash["limits"].pop("enabled", None):
                item.limits.enabled = True
            values = {}
            for set, items in item_hash["limits"].items():
                values[set] = [
                    items["red_low"],
                    items["yellow_low"],
                    items["yellow_high"],
                    items["red_high"],
                ]
                if items.get("green_low") is not None and items.get("green_high") is not None:
                    values[set] += [items["green_low"], items["green_high"]]
            if len(values) > 0:
                item.limits.values = values
        item.meta = item_hash.get("meta")
        return item

    def parameter_config(self):
        if self.id_value:
            value = self.id_value
            config = "  ID_PARAMETER "
        else:
            value = self.default
            config = "  PARAMETER "
        config += f"{quote_if_necessary(self.name)} {self.bit_offset} {self.bit_size} {self.data_type} "

        if self.data_type == "BLOCK" or self.data_type == "STRING":
            if not value.isascii():
                val_string = "0x" + simple_formatted(value)
            else:
                val_string = f'"{value}"'
        else:
            # first, last = self.calculate_range()
            # config += f"{first} {last} "
            config += f"{self.minimum} {self.maximum} "
            val_string = value
        if self.description:
            description = self.description.replace('"', "'")
            config += f'{val_string} "{description}"'
        else:
            config += f"{val_string}"
        return config

    # Convert a value into the given data type
    def convert(self, value, data_type):
        try:
            match data_type:
                case "INT" | "UINT":
                    return int(value)
                case "FLOAT":
                    return float(value)
                case "STRING" | "BLOCK":
                    return value
        except ValueError:
            raise ValueError(f"{self.name}: Invalid value: {value} for data type: {data_type}")
