from openc3.conversions.conversion import Conversion


# Custom conversion class
# See https://docs.openc3.com/docs/configuration/conversions
class BlockConversion(Conversion):
    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(self, value, packet, buffer):
        byte = packet.given_values.get('BYTE', 0x55)
        length = packet.given_values.get('LENGTH', 0)
        return bytes([byte]) * length
