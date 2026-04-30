# encoding: ascii-8bit
require 'openc3/conversions/conversion'

module OpenC3
  # Custom conversion class
  # See https://docs.openc3.com/docs/configuration/conversions
  class BlockConversion < Conversion
    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(value, packet, buffer)
      byte = packet.given_values['BYTE'] || 0x55
      length = packet.given_values['LENGTH'] || 0
      [byte].pack('C') * length
    end
  end
end
