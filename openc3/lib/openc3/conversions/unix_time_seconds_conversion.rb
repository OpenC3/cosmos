# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/conversions/unix_time_conversion'

module OpenC3
  # Converts a unix format time: Epoch Jan 1 1970, seconds and microseconds,
  # into a floating point number.
  class UnixTimeSecondsConversion < UnixTimeConversion
    # Initializes converted_type to :FLOAT and converted_bit_size to 64
    #
    # @param seconds_item_name [String] The telemetry item in the packet which
    #   represents the number of seconds since the UNIX time epoch
    # @param microseconds_item_name [String] The telemetry item in the packet
    #   which represents microseconds
    def initialize(seconds_item_name, microseconds_item_name = nil, seconds_type = 'RAW', microseconds_type = 'RAW')
      # @params is set by the parent class in super()
      super(seconds_item_name, microseconds_item_name, seconds_type, microseconds_type)
      @converted_type = :FLOAT
      @converted_bit_size = 64
    end

    # @param (see Conversion#call)
    # @return [Float] Packet time in seconds since UNIX epoch
    def call(value, packet, buffer)
      super.to_f
    end

    # @return [String] The name of the class followed by the time conversion
    def to_s
      super << ".to_f"
    end
  end
end
