# Copyright 2024 OpenC3, Inc.
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

class Accessor:
    def __init__(self, packet=None):
        self.packet = packet
        self.args = []

    def read_item(self, item, buffer):
        if item.parent_item is not None:
            # Structure is used to read items with parent, not accessor
            structure_buffer = self.read_item(item.parent_item, buffer)
            structure = item.parent_item.structure
            return structure.read(item.key, 'RAW', structure_buffer)
        else:
            return self.__class__.class_read_item(item, buffer)

    def write_item(self, item, value, buffer):
        if item.parent_item is not None:
            # Structure is used to write items with parent, not accessor
            structure_buffer = self.read_item(item.parent_item, buffer)
            structure = item.parent_item.structure
            structure.write(item.key, value, 'RAW', structure_buffer)
            return self.__class__.class_write_item(item.parent_item, structure_buffer, buffer)
        else:
            return self.__class__.class_write_item(item, value, buffer)

    def read_items(self, items, buffer):
        result = {}
        for item in items:
            result[item.name] = self.read_item(item, buffer)
        return result

    def write_items(self, items, values, buffer):
        for index, item in enumerate(items):
            self.write_item(item, values[index], buffer)
        return values

    def enforce_encoding(self):
        return "ASCII-8BIT"

    def enforce_length(self):
        return True

    def enforce_short_buffer_allowed(self):
        return False

    def enforce_derived_write_conversion(self, item):
        return True

    @classmethod
    def class_read_item(cls, item, buffer):
        raise RuntimeError("Must be defined by subclass")

    @classmethod
    def class_write_item(cls, item, value, buffer):
        raise RuntimeError("Must be defined by subclass")

    @classmethod
    def class_read_items(cls, items, buffer):
        result = {}
        for item in items:
            result[item.name] = cls.class_read_item(item, buffer)
        return result

    @classmethod
    def class_write_items(cls, items, values, buffer):
        for index, item in enumerate(items):
            cls.class_write_item(item, values[index], buffer)
        return values

    @classmethod
    def convert_to_type(cls, value, item):
        if value is None:
            return None
        match item.data_type:
            case "ANY":
                try:
                    if isinstance(value, str):
                        # Thought about using json.loads here but it doesn't
                        # support basic examples like "[2.2, '3', 4]"
                        # Seems it's pretty strict about quotes and escaping
                        value = literal_eval(value)
                except Exception:
                    # Just leave value as is
                    pass
            case "BOOL":
                if isinstance(value, str):
                    value = ConfigParser.handle_true_false(value)
            case "OBJECT" | "ARRAY":
                if isinstance(value, str):
                    # Thought about using json.loads here but it doesn't
                    # support basic examples like "[2.2, '3', 4]"
                    # Seems it's pretty strict about quotes and escaping
                    value = literal_eval(value)
            case "STRING":
                if item.array_size is not None:
                    if isinstance(value, str):
                        # Thought about using json.loads here but it doesn't
                        # support basic examples like "[2.2, '3', 4]"
                        # Seems it's pretty strict about quotes and escaping
                        value = literal_eval(value)
                    value = [str(x) for x in value]
                else:
                    value = str(value)
            case "BLOCK":
                if item.array_size is not None:
                    if isinstance(value, str):
                        # Thought about using json.loads here but it doesn't
                        # support basic examples like "[2.2, '3', 4]"
                        # Seems it's pretty strict about quotes and escaping
                        value = literal_eval(value)
                else:
                    if isinstance(value, str):
                        value = bytearray(value.encode())
                    else:
                        value = bytearray(value)
            case "INT" | "UINT":
                if item.array_size is not None:
                    if isinstance(value, str):
                        value = literal_eval(value)
                    value = [int(float(x)) for x in value]
                else:
                    value = int(float(value))
            case "FLOAT":
                if item.array_size is not None:
                    if isinstance(value, str):
                        value = literal_eval(value)
                    value = [float(x) for x in value]
                else:
                    value = float(value)
            case _:
                raise TypeError(f"data_type {item.data_type} is not recognized")

        return value
