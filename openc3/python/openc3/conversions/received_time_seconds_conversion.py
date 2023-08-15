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


# Converts the packet received time into floating point seconds.
class ReceivedTimeSecondsConversion(Conversion):
    # Initializes converted_type to 'FLOAT' and converted_bit_size to 64
    def __init__(self):
        super().__init__()
        self.converted_type = "FLOAT"
        self.converted_bit_size = 64

    # self.param (see Conversion#call)
    # self.return [Float] Packet received time in seconds
    def call(value, packet, buffer):
        if packet.received_time:
            return float(packet.received_time)
        else:
            return 0.0
