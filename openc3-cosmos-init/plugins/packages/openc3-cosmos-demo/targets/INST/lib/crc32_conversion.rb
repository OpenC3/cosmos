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
  # Read conversion which calculates the CRC32 of another item in the packet.
  # Used to verify the CRC sent by the target.
  # See https://docs.openc3.com/docs/configuration/conversions
  class Crc32Conversion < Conversion
    # @param item_name [String] Name of the item to calculate the CRC over
    def initialize(item_name)
      super()
      @item_name = item_name.to_s.upcase
      @crc = Crc32.new
      @params = [@item_name]
    end

    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(_value, packet, buffer)
      @crc.calc(packet.read(@item_name, :RAW, buffer))
    end
  end
end
