from openc3.conversions.conversion import Conversion

# Custom conversion class
# See https://openc3.com/docs/v5/telemetry#read_conversion
class <%= conversion_class %>(Conversion):
    def __init__(self):
        super().__init__()
        # Should be one of 'INT', 'UINT', 'FLOAT', 'STRING', 'BLOCK'
        self.converted_type = 'STRING'
        # Size of the converted type in bits
        # Use 0 for 'STRING' or 'BLOCK' where the size can be variable
        self.converted_bit_size = 0

    # @param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # @param packet [Packet] The packet object where the conversion is defined
    # @param buffer [String] The raw packet buffer
    def call(self, value, packet, buffer):
        # Read values from the packet and do a conversion
        # Used for DERIVED items that don't have a value
        # item1 = packet.read("ITEM1") # returns CONVERTED value (default)
        # item2 = packet.read("ITEM2", 'RAW') # returns RAW value
        # return (item1 + item2) / 2
        #
        # Perform conversion logic directly on value
        # Used when conversion is applied to a regular (not DERIVED) item
        # NOTE: You can also use packet.read("ITEM") to get additional values
        # return value / 2 * packet.read("OTHER_ITEM")
