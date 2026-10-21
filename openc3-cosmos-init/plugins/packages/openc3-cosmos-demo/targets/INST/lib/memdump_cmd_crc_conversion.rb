# encoding: ascii-8bit

# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/conversions/conversion'
require 'openc3/utilities/crc'

module OpenC3
  # Write conversion which calculates the MEMDUMP command CRC32 over the
  # big endian OFFSET and SIZE parameters so the user never has to.
  # Send the command with cmd_raw to bypass this conversion and set a bad CRC.
  # See https://docs.openc3.com/docs/configuration/conversions
  class MemdumpCmdCrcConversion < Conversion
    def initialize
      super()
      @crc = Crc32.new
    end

    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(value, packet, buffer)
      # Write conversions run before the given parameters are written to the
      # buffer so use the given values and fall back to the defaults
      given = packet.given_values || {}
      offset = Integer(given['OFFSET'] || packet.get_item('OFFSET').default)
      size = Integer(given['SIZE'] || packet.get_item('SIZE').default)
      @crc.calc([offset, size].pack('NN'))
    end
  end
end
