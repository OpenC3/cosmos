# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/conversions/conversion'

module OpenC3
  # Converts the packet received time object into a formatted string.
  class ReceivedTimeFormattedConversion < Conversion
    # Initializes converted_type to :STRING and converted_bit_size to 0
    def initialize
      super()
      @converted_type = :STRING
      @converted_bit_size = 0
    end

    # @param (see Conversion#call)
    # @return [String] Formatted packet time
    def call(value, packet, buffer)
      if packet.received_time
        return packet.received_time.formatted
      else
        return 'No Packet Received Time'
      end
    end
  end # class ReceivedTimeFormattedConversion
end
