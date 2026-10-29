# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

from openc3.conversions.conversion import Conversion
from openc3.utilities.crc import Crc32


# Read conversion which calculates the CRC32 of another item in the packet.
# Used to verify the CRC sent by the target.
# See https://docs.openc3.com/docs/configuration/conversions
class Crc32Conversion(Conversion):
    # @param item_name [String] Name of the item to calculate the CRC over
    def __init__(self, item_name):
        super().__init__()
        self.item_name = item_name.upper()
        self.crc = Crc32()
        self.params = [self.item_name]

    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(self, value, packet, buffer):
        return self.crc.calc(packet.read(self.item_name, "RAW", buffer))
