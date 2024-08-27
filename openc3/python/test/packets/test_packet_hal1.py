import unittest
from datetime import datetime, timezone
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem

'''
This test program covers the requested functions:

1. `packet_time()`
2. `identify()`
3. `read_id_values()`
4. `config_name()`
5. `set_received_time()`
6. `received_time()`

The tests cover various scenarios for each function, including edge cases and error conditions. You can run this test program directly to execute all the unit tests.
'''

class TestPacket(unittest.TestCase):
    def setUp(self):
        self.packet = Packet("TARGET", "PACKET")
        self.packet.append_item("ITEM1", 8, "UINT")
        self.packet.append_item("ITEM2", 8, "UINT")
        self.packet.append_item("ITEM3", 8, "UINT")
        self.packet.append_item("PACKET_TIME", 0, "DERIVED")

    def test_packet_time(self):
        # Test when PACKET_TIME item exists
        self.assertIsNone(self.packet.packet_time)

        # Test when PACKET_TIME item doesn't exist
        self.packet.remove_item("PACKET_TIME")
        self.assertIsNone(self.packet.packet_time)

        # Test when received_time is set
        test_time = datetime.now(timezone.utc)
        self.packet.received_time = test_time
        self.assertEqual(self.packet.packet_time, test_time)

    def test_identify(self):
        # Test with no id_items
        self.assertTrue(self.packet.identify(b'\x00\x00\x00'))

        # Test with id_items
        self.packet.get_item("ITEM1").id_value = 0x01
        self.assertTrue(self.packet.identify(b'\x01\x00\x00'))
        self.assertFalse(self.packet.identify(b'\x02\x00\x00'))

        # Test with virtual packet
        self.packet.virtual = True
        self.assertFalse(self.packet.identify(b'\x01\x00\x00'))

    def test_read_id_values(self):
        self.packet.get_item("ITEM1").id_value = 0x01
        self.packet.get_item("ITEM2").id_value = 0x02

        # Test reading id values
        self.assertEqual(self.packet.read_id_values(b'\x01\x02\x03'), [1, 2])

        # Test with empty buffer
        self.assertEqual(self.packet.read_id_values(b''), [])

        # Test with no id_items
        self.packet.id_items = None
        self.assertEqual(self.packet.read_id_values(b'\x01\x02\x03'), [])

    def test_config_name(self):
        # Test config_name generation
        config_name = self.packet.config_name()
        self.assertIsInstance(config_name, str)
        self.assertEqual(len(config_name), 64)  # SHA256 hash length

        # Test config_name caching
        self.assertEqual(self.packet.config_name(), config_name)

    def test_set_received_time(self):
        test_time = datetime.now(timezone.utc)
        self.packet.set_received_time_fast(test_time)
        self.assertEqual(self.packet.received_time, test_time)
        self.assertEqual(self.packet.read_conversion_cache, {})

    def test_received_time(self):
        test_time = datetime.now(timezone.utc)
        self.packet.received_time = test_time
        self.assertEqual(self.packet.received_time, test_time)

        with self.assertRaises(AttributeError):
            self.packet.received_time = "invalid time"

if __name__ == '__main__':
    unittest.main()
