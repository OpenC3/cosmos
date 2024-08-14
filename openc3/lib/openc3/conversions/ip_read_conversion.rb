# encoding: ascii-8bit

# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/conversions/conversion'

module OpenC3
  class IpReadConversion < Conversion
    def initialize
      @converted_type = :STRING
      @converted_bit_size = 120
      @converted_array_size = nil
    end

    # Perform the conversion on the value.
    #
    # @param value [Object] The value to convert
    # @param packet [Packet] The packet which contains the value. This can
    #   be useful to reach into the packet and use other values in the
    #   conversion.
    # @param buffer [String] The packet buffer
    # @return The converted value
    def call(value, _packet, _buffer)
      byte4 = (value & 0xFF)
      value = value >> 8
      byte3 = (value & 0xFF)
      value = value >> 8
      byte2 = (value & 0xFF)
      value = value >> 8
      byte1 = (value & 0xFF)
      return "#{byte1}.#{byte2}.#{byte3}.#{byte4}"
    end

    # @return [String] The conversion class
    def to_s
      "#{self.class.to_s.split('::')[-1]}.new"
    end

    # @param read_or_write [String] Either 'READ' or 'WRITE'
    # @return [String] Config fragment for this conversion
    def to_config(read_or_write)
      "    #{read_or_write}_CONVERSION #{self.class.name.class_name_to_filename}\n"
    end
  end
end
