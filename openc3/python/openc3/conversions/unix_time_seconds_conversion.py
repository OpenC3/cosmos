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


from openc3.conversions.unix_time_conversion import UnixTimeConversion


# Converts a unix format time: Epoch Jan 1 1970, seconds and microseconds,
# into a floating point number.
class UnixTimeSecondsConversion(UnixTimeConversion):
    # Initializes converted_type to :FLOAT and converted_bit_size to 64
    #
    # @param seconds_item_name [String] The telemetry item in the packet which
    #   represents the number of seconds since the UNIX time epoch
    # @param microseconds_item_name [String] The telemetry item in the packet
    #   which represents microseconds
    def __init__(self, seconds_item_name, microseconds_item_name=None):
        # self.params is set by the parent class in super()
        super().__init__(seconds_item_name, microseconds_item_name)
        self.converted_type = "FLOAT"
        self.converted_bit_size = 64

    # @param (see Conversion#call)
    # @return [Float] Packet time in seconds since UNIX epoch
    def call(self, value, packet, buffer):
        return super().call(value, packet, buffer).timestamp()

    # @return [String] The name of the class followed by the time conversion
    def __str__(self):
        result = f"UnixTimeSecondsConversion {self.seconds_item_name}"
        if self.microseconds_item_name:
            result += f" {self.microseconds_item_name}"
        return result
