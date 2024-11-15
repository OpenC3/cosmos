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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.conversions.conversion import Conversion


class BitReverseConversion(Conversion):
    def __init__(self, converted_type, converted_bit_size):
        super().__init__()
        self.converted_type = str(converted_type).upper()
        self.converted_bit_size = int(converted_bit_size)
        if self.converted_type == "FLOAT":
            raise RuntimeError("Float Bit Reverse Not Yet Supported")
        self.params = [self.converted_type, self.converted_bit_size]

    # Perform the conversion on the value.
    #
    # @param value [Object] The value to convert
    # @param packet [Packet] The packet which contains the value. This can
    #   be useful to reach into the packet and use other values in the
    #   conversion.
    # @param buffer [String] The packet buffer
    # @return The converted value
    def call(self, value, _packet, _buffer):
        b = "{:0{width}b}".format(value, width=self.converted_bit_size)
        return int(b[::-1], 2)

    # @return [String] The conversion class
    def __str__(self):
        return f"BitReverseConversion {self.converted_type} {self.converted_bit_size}"

    # @param read_or_write [String] Either 'READ' or 'WRITE'
    # @return [String] Config fragment for this conversion
    def to_config(self, read_or_write):
        return f"{read_or_write}_CONVERSION openc3/conversions/bit_reverse_conversion.py {self.converted_type} {self.converted_bit_size}\n"
