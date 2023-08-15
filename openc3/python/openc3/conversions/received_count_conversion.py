#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
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


# Converts the packet received count as a derived telemetry item
class ReceivedCountConversion(Conversion):
    # Initializes converted_type to 'UINT' and converted_bit_size to 32
    def __init__(self):
        super().__init__()
        self.converted_type = "UINT"
        self.converted_bit_size = 32

    # self.param (see Conversion#call)
    # self.return [Integer] packet.received_count
    def call(value, packet, buffer):
        packet.received_count
