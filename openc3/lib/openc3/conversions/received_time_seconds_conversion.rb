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
  # Converts the packet received time into floating point seconds.
  class ReceivedTimeSecondsConversion < Conversion
    # Initializes converted_type to :FLOAT and converted_bit_size to 64
    def initialize
      super()
      @converted_type = :FLOAT
      @converted_bit_size = 64
    end

    # @param (see Conversion#call)
    # @return [Float] Packet received time in seconds
    def call(value, packet, buffer)
      if packet.received_time
        return packet.received_time.to_f
      else
        return 0.0
      end
    end
  end # class ReceivedTimeSecondsConversion
end
