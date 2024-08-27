import unittest
import datetime
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem

'''
This test program includes unit tests for the following methods of the Packet class:

1. `as_json()`
2. `from_json()`
3. `process()`
4. `handle_limits_values()`
5. `packet_define_item()`

The tests cover various aspects of these methods, including:

- Serialization and deserialization of packet data to/from JSON
- Processing of packets using custom processors
- Handling of limit values and state changes
- Defining packet items with various attributes
'''

class TestPacket(unittest.TestCase):
    def setUp(self):
        self.packet = Packet("TARGET", "PACKET")
        self.packet.append_item("ITEM1", 8, "UINT")
        self.packet.append_item("ITEM2", 16, "UINT")
        self.packet.append_item("ITEM3", 32, "FLOAT")

    def test_as_json(self):
        json_data = self.packet.as_json()
        self.assertEqual(json_data['target_name'], "TARGET")
        self.assertEqual(json_data['packet_name'], "PACKET")
        self.assertEqual(len(json_data['items']), 3)
        self.assertEqual(json_data['items'][0]['name'], "ITEM1")
        self.assertEqual(json_data['items'][1]['name'], "ITEM2")
        self.assertEqual(json_data['items'][2]['name'], "ITEM3")

    def test_from_json(self):
        json_data = self.packet.as_json()
        new_packet = Packet.from_json(json_data)
        self.assertEqual(new_packet.target_name, "TARGET")
        self.assertEqual(new_packet.packet_name, "PACKET")
        self.assertEqual(len(new_packet.items), 3)
        self.assertIn("ITEM1", new_packet.items)
        self.assertIn("ITEM2", new_packet.items)
        self.assertIn("ITEM3", new_packet.items)

    def test_process(self):
        class TestProcessor:
            def __init__(self):
                self.called = False
            def call(self, packet, buffer):
                self.called = True

        processor = TestProcessor()
        self.packet.processors = {"TEST": processor}
        self.packet.process()
        self.assertTrue(processor.called)

    def test_handle_limits_values(self):
        item = self.packet.get_item("ITEM3")
        item.limits.values = {"DEFAULT": [-10, -5, 5, 10]}

        self.packet.handle_limits_values(item, 0, "DEFAULT", False)
        self.assertEqual(item.limits.state, "GREEN")

        self.packet.handle_limits_values(item, 7, "DEFAULT", False)
        self.assertEqual(item.limits.state, "YELLOW_HIGH")

        self.packet.handle_limits_values(item, 15, "DEFAULT", False)
        self.assertEqual(item.limits.state, "RED_HIGH")

    def test_packet_define_item(self):
        item = PacketItem("TEST_ITEM", 0, 8, "UINT")
        format_string = "%d"
        read_conversion = lambda x: x * 2
        write_conversion = lambda x: x / 2
        id_value = 42

        result = self.packet.packet_define_item(item, format_string, read_conversion, write_conversion, id_value)

        self.assertEqual(result.format_string, format_string)
        self.assertEqual(result.read_conversion, read_conversion)
        self.assertEqual(result.write_conversion, write_conversion)
        self.assertEqual(result.id_value, id_value)
        self.assertIn(result, self.packet.id_items)

if __name__ == '__main__':
    unittest.main()
