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
  # Converts the packet received count as a derived telemetry item
  class ReceivedCountConversion < Conversion
    # Initializes converted_type to :UINT and converted_bit_size to 32
    def initialize
      super()
      @converted_type = :UINT
      @converted_bit_size = 32
    end

    # @param (see Conversion#call)
    # @return [Integer] packet.received_count
    def call(value, packet, buffer)
      packet.received_count
    end
  end # class ReceivedCountConversion
end
