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


from datetime import datetime, timezone
from openc3.conversions.conversion import Conversion


# Converts a unix format time: Epoch Jan 1 1970, seconds and microseconds
class UnixTimeConversion(Conversion):
    # Initializes the time item to grab from the packet
    #
    # @param seconds_item_name [String] The telemetry item in the packet which
    #   represents the number of seconds since the UNIX time epoch
    # @param microseconds_item_name [String] The telemetry item in the packet
    #   which represents microseconds
    def __init__(self, seconds_item_name, microseconds_item_name=None):
        super().__init__()
        self.seconds_item_name = seconds_item_name
        self.microseconds_item_name = microseconds_item_name
        self.converted_type = "RUBY_TIME"
        self.converted_bit_size = 0
        self.params = [seconds_item_name, microseconds_item_name]

    # @param (see Conversion#call)
    # @return [Float] Packet time in seconds since UNIX epoch
    def call(self, value, packet, buffer):
        time = packet.read(self.seconds_item_name, "RAW", buffer)
        if self.microseconds_item_name:
            time += packet.read(self.microseconds_item_name, "RAW", buffer) / 1000000.0
        return datetime.fromtimestamp(time, tz=timezone.utc)

    # @return [String] The name of the class followed by the time conversion
    def __str__(self):
        return f"UnixTimeConversion {self.seconds_item_name} {self.microseconds_item_name}"

    # @param (see Conversion#to_config)
    # @return [String] Config fragment for this conversion
    def to_config(self, read_or_write):
        return f"    {read_or_write}_CONVERSION {self.__class__.__name__} {self.seconds_item_name} {self.microseconds_item_name}\n"
