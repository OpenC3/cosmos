# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.


from openc3.conversions.conversion import Conversion


# Converts the packet received count as a derived telemetry item
class ReceivedCountConversion(Conversion):
    # Initializes converted_type to 'UINT' and converted_bit_size to 32
    def __init__(self):
        super().__init__()
        self.converted_type = "UINT"
        self.converted_bit_size = 32

    # self.param (see Conversion#call)
    # self.return [Integer] packet.received_count
    def call(self, value, packet, buffer):
        return packet.received_count
