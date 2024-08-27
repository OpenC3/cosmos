import unittest
from datetime import datetime
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem

'''
This test program covers the following aspects:

1. `test_check_bit_offsets()`: Tests the `check_bit_offsets()` method for cases with no overlaps, with overlaps, and with `ignore_overlap` set to True.

2. `test_packed()`: Tests the `packed()` method for cases with packed items and with a gap between items.

3. `test_read_item()`: Tests the `read_item()` method for various value types (RAW, CONVERTED, FORMATTED, WITH_UNITS), with read conversions, format strings, units, states, and derived items.

These tests cover the main functionality of the specified methods and include error cases such as invalid value types. You can run this test program directly, and it will execute all the test cases, providing a report on their success or failure.
'''

class TestPacket(unittest.TestCase):
    def setUp(self):
        self.packet = Packet("TGT", "PKT")

    def test_check_bit_offsets(self):
        # Test with no overlaps
        self.packet.append_item("ITEM1", 8, "UINT")
        self.packet.append_item("ITEM2", 8, "UINT")
        self.assertEqual(self.packet.check_bit_offsets(), [])

        # Test with overlap
        self.packet.append_item("ITEM3", 8, "UINT", bit_offset=8)
        warnings = self.packet.check_bit_offsets()
        self.assertEqual(len(warnings), 1)
        self.assertIn("Bit definition overlap", warnings[0])

        # Test with ignore_overlap
        self.packet.ignore_overlap = True
        self.assertEqual(self.packet.check_bit_offsets(), [])

    def test_packed(self):
        # Test with packed items
        self.packet.append_item("ITEM1", 8, "UINT")
        self.packet.append_item("ITEM2", 8, "UINT")
        self.assertTrue(self.packet.packed())

        # Test with gap
        self.packet.append_item("ITEM3", 8, "UINT", bit_offset=24)
        self.assertFalse(self.packet.packed())

    def test_read_item(self):
        item = self.packet.append_item("ITEM", 16, "UINT")
        self.packet.write("ITEM", 0x1234)

        # Test RAW read
        self.assertEqual(self.packet.read_item(item, "RAW"), 0x1234)

        # Test CONVERTED read
        item.read_conversion = lambda x: x * 2
        self.assertEqual(self.packet.read_item(item, "CONVERTED"), 0x2468)

        # Test FORMATTED read
        item.format_string = "0x%04X"
        self.assertEqual(self.packet.read_item(item, "FORMATTED"), "0x2468")

        # Test WITH_UNITS read
        item.units = "V"
        self.assertEqual(self.packet.read_item(item, "WITH_UNITS"), "0x2468 V")

        # Test invalid value_type
        with self.assertRaises(AttributeError):
            self.packet.read_item(item, "INVALID")

        # Test read with states
        item.states = {"OFF": 0, "ON": 1}
        self.packet.write("ITEM", 1)
        self.assertEqual(self.packet.read_item(item, "CONVERTED"), "ON")

        # Test read with derived item
        derived_item = self.packet.append_item("DERIVED", 0, "DERIVED")
        derived_item.read_conversion = lambda x, packet: packet.read("ITEM") + 1
        self.assertEqual(self.packet.read_item(derived_item, "CONVERTED"), 2)

if __name__ == '__main__':
    unittest.main()
