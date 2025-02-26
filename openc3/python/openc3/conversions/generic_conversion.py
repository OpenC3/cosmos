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
from openc3.accessors.binary_accessor import BinaryAccessor
from openc3.config.config_parser import ConfigParser


# Performs a generic conversion by evaluating Ruby code
class GenericConversion(Conversion):
    # self.param code_to_eval [String] The Ruby code to evaluate which should
    #   return the converted value
    # self.param converted_type [Symbol] The converted data type. Must be one of
    #   {BinaryAccessor='DATA_TYPES'}
    # self.param converted_bit_size [Integer] The size in bits of the converted
    #   value
    # self.param converted_array_size [Integer] The size in bits of the converted array
    #   value (full size of all items if array):
    def __init__(
        self,
        code_to_eval,
        converted_type=None,
        converted_bit_size=None,
        converted_array_size=None,
    ):
        super().__init__()
        self.code_to_eval = code_to_eval
        if ConfigParser.handle_none(converted_type):
            converted_type = converted_type.upper()
            if converted_type not in BinaryAccessor.DATA_TYPES:
                raise RuntimeError(f"Invalid type {converted_type}")
            self.converted_type = converted_type
        if ConfigParser.handle_none(converted_bit_size):
            self.converted_bit_size = int(converted_bit_size)
        if ConfigParser.handle_none(converted_array_size):
            self.converted_array_size = int(converted_array_size)
        self.params = [code_to_eval, converted_type, converted_bit_size, converted_array_size]

        # Setup multiline eval where the last line defines the return value for eval
        lines = code_to_eval.splitlines()
        exec_lines = lines[0:(len(lines) - 1)]
        self.exec_lines = compile("\n".join(exec_lines), "<string>", "exec")
        self.eval_line = compile(lines[-1], "<string>", "eval")

    def call(self, value, packet, buffer):
        myself = packet  # For backwards compatibility
        if myself:  # Remove unused variable warning for myself
            generic_globals = {"value": value, "myself": myself, "packet": packet, "buffer": buffer}
            exec(self.exec_lines, generic_globals)
            return eval(self.eval_line, generic_globals)

    # self.return [String] The conversion class followed by the code to evaluate
    def __str__(self):
        return self.code_to_eval

    # self.param (see Conversion#to_config)
    # self.return [String] Config fragment for this conversion
    def to_config(self, read_or_write):
        config = f"    GENERIC_{read_or_write}_CONVERSION_START"
        if self.converted_type is not None:
            config += f" {self.converted_type}"
        if self.converted_bit_size is not None:
            config += f" {self.converted_bit_size}"
        if self.converted_array_size is not None:
            config += f" {self.converted_array_size}"
        config += "\n"
        config << self.code_to_eval
        config += f"    GENERIC_{read_or_write}_CONVERSION_END\n"
        return config
