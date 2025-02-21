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


class Accessor:
    def __init__(self, packet=None):
        self.packet = packet
        self.args = []

    def read_item(self, item, buffer):
        return self.__class__.class_read_item(item, buffer)

    def write_item(self, item, value, buffer):
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
            case "OBJECT" | "ARRAY":
                pass  # No conversion on complex OBJECT types
            case "STRING" | "BLOCK":
                if item.array_size is not None:
                    if isinstance(value, str):
                        # Thought about using json.loads here but it doesn't
                        # support basic examples like "[2.2, '3', 4]"
                        # Seems it's pretty strict about quotes and escaping
                        value = literal_eval(value)
                    value = [str(x) for x in value]
                else:
                    value = str(value)
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
