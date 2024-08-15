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
  class IpWriteConversion < Conversion
    def initialize
      @converted_type = :UINT
      @converted_bit_size = 32
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
      bytes = value.split('.')
      result = 0
      result += Integer(bytes[0])
      result = result << 8
      result += Integer(bytes[1])
      result = result << 8
      result += Integer(bytes[2])
      result = result << 8
      result += Integer(bytes[3])
      return result
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
