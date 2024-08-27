
import unittest
from datetime import datetime
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem

'''
This test program covers the requested functions of the Packet class:

1. read_items()
2. write_item()
3. write_items()
4. write()
5. read()
6. read_all()
7. formatted()
8. read_all_with_limits_states()
9. restore_defaults()

Each test case sets up a simple packet with three items and then tests the functionality of the specified methods. The tests cover basic usage scenarios for each method, including reading and writing values, formatting output, and handling defaults.

To run this test program, save it as a Python file (e.g., `test_packet.py`) and execute it from the command line:

```
python test_packet.py
```

This will run all the tests and report the results. Make sure you have the necessary OpenC3 modules installed and accessible in your Python environment before running the tests.
'''

class TestPacket(unittest.TestCase):
    def setUp(self):
        self.packet = Packet("TARGET", "PACKET")
        self.packet.append_item("ITEM1", 8, "UINT")
        self.packet.append_item("ITEM2", 16, "UINT")
        self.packet.append_item("ITEM3", 32, "FLOAT")

    def test_read_items(self):
        self.packet.write("ITEM1", 10)
        self.packet.write("ITEM2", 20)
        self.packet.write("ITEM3", 30.5)

        items = [self.packet.get_item("ITEM1"), self.packet.get_item("ITEM2"), self.packet.get_item("ITEM3")]
        result = self.packet.read_items(items)

        self.assertEqual(result["ITEM1"], 10)
        self.assertEqual(result["ITEM2"], 20)
        self.assertAlmostEqual(result["ITEM3"], 30.5, places=6)

    def test_write_item(self):
        item = self.packet.get_item("ITEM1")
        self.packet.write_item(item, 42)
        self.assertEqual(self.packet.read("ITEM1"), 42)

    def test_write_items(self):
        items = [self.packet.get_item("ITEM1"), self.packet.get_item("ITEM2")]
        values = [55, 66]
        self.packet.write_items(items, values)
        self.assertEqual(self.packet.read("ITEM1"), 55)
        self.assertEqual(self.packet.read("ITEM2"), 66)

    def test_write(self):
        self.packet.write("ITEM2", 100)
        self.assertEqual(self.packet.read("ITEM2"), 100)

    def test_read(self):
        self.packet.write("ITEM3", 123.45)
        self.assertAlmostEqual(self.packet.read("ITEM3"), 123.45, places=6)

    def test_read_all(self):
        self.packet.write("ITEM1", 1)
        self.packet.write("ITEM2", 2)
        self.packet.write("ITEM3", 3.0)
        result = self.packet.read_all()
        expected = [
            ['ITEM1', 1],
            ['ITEM2', 2],
            ['ITEM3', 3.0]
        ]
        self.assertEqual(result, expected)

    def test_formatted(self):
        self.packet.write("ITEM1", 10)
        self.packet.write("ITEM2", 20)
        self.packet.write("ITEM3", 30.5)
        formatted = self.packet.formatted()
        self.assertIn("ITEM1 = 10", formatted)
        self.assertIn("ITEM2 = 20", formatted)
        self.assertIn("ITEM3 = 30.5", formatted)

    def test_read_all_with_limits_states(self):
        self.packet.write("ITEM1", 1)
        self.packet.write("ITEM2", 2)
        self.packet.write("ITEM3", 3.0)
        result = self.packet.read_all_with_limits_states()
        expected = [
            ['ITEM1', 1, None],
            ['ITEM2', 2, None],
            ['ITEM3', 3.0, None]
        ]
        self.assertEqual(result, expected)

    def test_restore_defaults(self):
        self.packet.write("ITEM1", 100)
        self.packet.write("ITEM2", 200)
        self.packet.write("ITEM3", 300.0)

        self.packet.get_item("ITEM1").default = 1
        self.packet.get_item("ITEM2").default = 2
        self.packet.get_item("ITEM3").default = 3.0

        self.packet.restore_defaults()

        self.assertEqual(self.packet.read("ITEM1"), 1)
        self.assertEqual(self.packet.read("ITEM2"), 2)
        self.assertAlmostEqual(self.packet.read("ITEM3"), 3.0, places=6)

if __name__ == '__main__':
    unittest.main()
