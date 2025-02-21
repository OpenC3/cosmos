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


class IpWriteConversion(Conversion):
    def __init__(self):
        super().__init__()
        self.converted_type = "UINT"
        self.converted_bit_size = 32

    # Perform the conversion on the value.
    #
    # @param value [Object] The value to convert
    # @param packet [Packet] The packet which contains the value. This can
    #   be useful to reach into the packet and use other values in the
    #   conversion.
    # @param buffer [String] The packet buffer
    # @return The converted value
    def call(self, value, _packet, _buffer):
        octets = value.split('.')
        return (int(octets[0]) << 24) | (int(octets[1]) << 16) | (int(octets[2]) << 8) | int(octets[3])

    # @return [String] The conversion class
    def __str__(self):
        return "IpWriteConversion"

    # @param read_or_write [String] Either 'READ' or 'WRITE'
    # @return [String] Config fragment for this conversion
    def to_config(read_or_write):
        return f"{read_or_write}_CONVERSION openc3/conversions/ip_write_conversion.py\n"
