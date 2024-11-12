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


from openc3.conversions.conversion import Conversion
from openc3.config.config_parser import ConfigParser
from openc3.accessors.binary_accessor import BinaryAccessor


class ProcessorConversion(Conversion):
    # @param processor_name [String] The name of the associated processor
    # @param result_name [String] The name of the associated result in the processor
    # @param converted_type [String or nil] The datatype of the result of the processor
    # @param converted_bit_size [Integer or nil] The bit size of the result of the processor
    # @param converted_array_size [Integer or nil] The total array bit size of the result of the processor
    def __init__(
        self,
        processor_name,
        result_name,
        converted_type=None,
        converted_bit_size=None,
        converted_array_size=None,
    ):
        super().__init__()
        self.processor_name = str(processor_name).upper()
        self.result_name = str(result_name).upper()
        self.params = [self.processor_name, self.result_name]
        if ConfigParser.handle_none(converted_type):
            self.converted_type = str(converted_type).upper()
            if self.converted_type not in BinaryAccessor.DATA_TYPES:
                raise TypeError(f"Unknown converted type: {converted_type}")
            self.params.append(self.converted_type)
        if ConfigParser.handle_none(converted_bit_size):
            self.converted_bit_size = int(converted_bit_size)
            self.params.append(self.converted_bit_size)
        if ConfigParser.handle_none(converted_array_size):
            self.converted_array_size = int(converted_array_size)
            self.params.append(self.converted_array_size)

    # @param (see Conversion#call)
    # @return [Varies] The result of the associated processor
    def call(self, value, packet, buffer):
        result = packet.processors[self.processor_name].results[self.result_name]
        if result is not None:
            return result
        else:
            return 0

    # @return [String] The type of processor
    def __str__(self):
        return f"ProcessorConversion {self.processor_name} {self.result_name}"

    # @param (see Conversion#to_config)
    # @return [String] Config fragment for this conversion
    def to_config(self, read_or_write):
        config = f"    {read_or_write}_CONVERSION {self.__class__.__name__} {self.processor_name} {self.result_name}"
        if self.converted_type is not None:
            config += f" {self.converted_type}"
        if self.converted_bit_size is not None:
            config += f" {self.converted_bit_size}"
        if self.converted_array_size is not None:
            config += f" {self.converted_array_size}"
        config += "\n"
        return config
