# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import re
from ast import literal_eval
from typing import Any

from openc3.config.config_parser import ConfigParser


# Integer string syntax accepted by Ruby's Integer(): optional ASCII whitespace
# and sign, 0x/0b/0o/0d prefixes, and single underscores between digits. Plain
# digits may have leading zeros and stay decimal ("010" is 10), matching the
# LEADING_ZEROS strip in accessor.rb. re.ASCII keeps \d to 0-9, since Ruby's
# Integer() rejects other Unicode digits that int() would accept.
_INTEGER_STRING = re.compile(
    r"[ \t\n\v\f\r]*(?P<sign>[+-]?)(?:"
    r"0[xX](?P<hex>[0-9a-fA-F]+(?:_[0-9a-fA-F]+)*)"
    r"|0[bB](?P<bin>[01]+(?:_[01]+)*)"
    r"|0[oO](?P<oct>[0-7]+(?:_[0-7]+)*)"
    r"|0[dD](?P<dec>\d+(?:_\d+)*)"
    r"|(?P<plain>\d+(?:_\d+)*)"
    r")[ \t\n\v\f\r]*",
    re.ASCII,
)
_INTEGER_BASES = {"hex": 16, "bin": 2, "oct": 8, "dec": 10, "plain": 10}


def _convert_to_int(value: Any) -> int:
    """Convert a value to an integer the same way accessor.rb convert_to_int does.

    Strings must be integer literals: "3.7" and "1e3" are rejected, "0x10" is
    16, "0b10" is 2, and leading zeros are decimal ("010" is 10). Other values
    go through int(), so numpy integers and Decimal stay exact and floats
    truncate toward zero.

    Args:
        value: A str, bytes, bytearray, or any value int() accepts.

    Returns:
        The integer value.

    Raises:
        TypeError: The value does not support integer conversion.
        ValueError: The string is not an integer literal, or the value is NaN.
        OverflowError: The value is infinite.
    """
    if isinstance(value, (bytes, bytearray)):
        value = value.decode("ascii")
    if isinstance(value, str):
        match = _INTEGER_STRING.fullmatch(value)
        if match is None:
            raise ValueError(f"invalid value for Integer(): {value!r}")
        for name, base in _INTEGER_BASES.items():
            digits = match.group(name)
            if digits is not None:
                result = int(digits, base)
                return -result if match.group("sign") == "-" else result
    return int(value)


class Accessor:
    def __init__(self, packet=None):
        self.packet = packet
        self.args = []

    def read_item(self, item, buffer):
        if item.parent_item is not None:
            # Structure is used to read items with parent, not accessor
            parent_item = self.packet.get_item(item.parent_item)
            structure_buffer = self.read_item(parent_item, buffer)
            structure = parent_item.structure
            return structure.read(item.key, "RAW", structure_buffer)
        else:
            return self.__class__.class_read_item(item, buffer)

    def write_item(self, item, value, buffer):
        if item.parent_item is not None:
            # Structure is used to write items with parent, not accessor
            parent_item = self.packet.get_item(item.parent_item)
            structure_buffer = self.read_item(parent_item, buffer)
            structure = parent_item.structure
            structure.write(item.key, value, "RAW", structure_buffer)
            return self.__class__.class_write_item(parent_item, structure_buffer, buffer)
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
    def convert_to_type(cls, value: Any, item: Any) -> Any:
        """Convert a value to the data type declared by an item.

        Args:
            value: The scalar or array value to convert, or None.
            item: An item providing data_type and array_size attributes.

        Returns:
            The converted value, preserving None and exact integer inputs.

        Raises:
            TypeError: The data type or value does not support conversion.
            ValueError: A value cannot be parsed or converted to the requested type.
            SyntaxError: A string is not a valid Python literal.
            OverflowError: A numeric value cannot be converted without overflow.
        """
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
                    value = [_convert_to_int(x) for x in value]
                else:
                    value = _convert_to_int(value)
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
