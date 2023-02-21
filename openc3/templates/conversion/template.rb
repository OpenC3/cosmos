# encoding: ascii-8bit

# Copyright 2023 OpenC3, Inc
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/conversions/conversion'

module OpenC3
  # Converts the packet received time object into a formatted string.
  class <%= conversion_class %> < Conversion
    def initialize
      super()
      # Should be one of :INT, :UINT, :FLOAT, :STRING, :BLOCK
      @converted_type = :STRING
      # Size of the converted type in bits
      # Use 0 for :STRING or :BLOCK where the size can be variable
      @converted_bit_size = 0
    end

    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(value, packet, buffer)
      # Typically perform conversion logic directly on value
      # e.g. value.upcase()
    end
  end
end
