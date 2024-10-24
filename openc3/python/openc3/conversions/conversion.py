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


class Conversion:
    """Performs a general conversion via the implementation of the call method"""

    # self.return [Symbol] The converted data type. Must be one of
    #   {OpenC3::StructureItem#data_type}
    # attr_reader :converted_type
    # # self.return [Integer] The size in bits of the converted value
    # attr_reader :converted_bit_size
    # # self.return [Integer] The size in bits of the converted array value
    # attr_reader :converted_array_size
    # attr_reader :params

    # Create a new conversion
    def __init__(self):
        self.converted_type = None
        self.converted_bit_size = None
        self.converted_array_size = None
        self.params = None

    # Perform the conversion on the value.
    #
    # self.param value [Object] The value to convert
    # self.param packet [Packet] The packet which contains the value. This can
    #   be useful to reach into the packet and use other values in the
    #   conversion.
    # self.param buffer [String] The packet buffer
    # self.return The converted value
    def call(self, value, packet, buffer):
        raise RuntimeError("call method must be defined by subclass")

    # self.return [String] The conversion class
    def __str__(self):
        return self.__class__.__name__

    # self.param read_or_write [String] Either 'READ' or 'WRITE'
    # self.return [String] Config fragment for this conversion
    def to_config(self, read_or_write):
        return f"    {read_or_write}_CONVERSION {self.__class__.__name__}\n"

    def as_json(self):
        result = {}
        result["class"] = self.__class__.__name__
        if self.converted_type is not None:
            result["converted_type"] = self.converted_type
        if self.converted_bit_size is not None:
            result["converted_bit_size"] = self.converted_bit_size
        if self.converted_array_size is not None:
            result["converted_array_size"] = self.converted_array_size
        if self.params is not None:
            result["params"] = self.params
        return result
