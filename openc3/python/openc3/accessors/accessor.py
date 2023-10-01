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
        data_type = item.data_type
        if (data_type == "STRING") or (data_type == "BLOCK"):
            #######################################
            # Handle :STRING and :BLOCK data types
            #######################################
            value = str(value)

        elif (data_type == "INT") or (data_type == "UINT"):
            ###################################
            # Handle :INT data type
            ###################################
            value = int(value)

        elif data_type == "FLOAT":
            ##########################
            # Handle :FLOAT data type
            ##########################
            value = float(value)

        else:
            ############################
            # Handle Unknown data types
            ############################

            raise AttributeError(f"data_type {data_type} is not recognized")

        return value
