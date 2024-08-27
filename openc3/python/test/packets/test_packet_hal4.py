import unittest
from datetime import datetime
from openc3.packets.packet import Packet
from openc3.packets.packet_item import PacketItem

'''
This test program covers the specified functions:

1. `disable_limits()`
2. `out_of_limits()`
3. `check_limits()`
4. `reset()`
5. `clone()`
6. `to_config()`

Each test case focuses on a specific function and verifies its behavior. The `setUp` method creates a sample packet with some items and limits for testing purposes.

To run this test program, save it as a Python file (e.g., `test_packet.py`) and execute it from the command line:

```
python test_packet.py
```

This will run all the test cases and report the results. Make sure you have the necessary OpenC3 modules and dependencies installed in your Python environment before running the tests.
'''

class TestPacket(unittest.TestCase):
    def setUp(self):
        self.packet = Packet("TARGET", "PACKET")
        self.packet.append_item("ITEM1", 8, "UINT")
        self.packet.append_item("ITEM2", 8, "UINT")
        self.packet.append_item("ITEM3", 8, "UINT")
        self.packet.enable_limits("ITEM1")
        self.packet.items["ITEM1"].limits.values = {"DEFAULT": [0, 2, 8, 10]}

    def test_disable_limits(self):
        self.packet.disable_limits("ITEM1")
        self.assertFalse(self.packet.items["ITEM1"].limits.enabled)
        self.assertIsNone(self.packet.items["ITEM1"].limits.state)

    def test_out_of_limits(self):
        self.packet.write("ITEM1", 11)
        out_of_limits = self.packet.out_of_limits()
        self.assertEqual(len(out_of_limits), 1)
        self.assertEqual(out_of_limits[0], ["TARGET", "PACKET", "ITEM1", "RED_HIGH"])

    def test_check_limits(self):
        self.packet.write("ITEM1", 9)
        self.packet.check_limits()
        self.assertEqual(self.packet.items["ITEM1"].limits.state, "YELLOW_HIGH")

    def test_reset(self):
        self.packet.received_time = datetime.now()
        self.packet.received_count = 10
        self.packet.reset()
        self.assertIsNone(self.packet.received_time)
        self.assertEqual(self.packet.received_count, 0)

    def test_clone(self):
        original = Packet("TARGET", "PACKET")
        original.append_item("ITEM", 8, "UINT")
        original.write("ITEM", 42)
        clone = original.clone()
        self.assertEqual(clone.read("ITEM"), 42)
        self.assertIsNot(clone, original)
        self.assertIsNot(clone.buffer, original.buffer)

    def test_to_config(self):
        config = self.packet.to_config("TELEMETRY")
        expected = (
            'TELEMETRY TARGET PACKET BIG_ENDIAN ""\n'
            '  ITEM ITEM1 0 8 UINT ""\n'
            '    LIMITS DEFAULT 0 2 8 10\n'
            '  ITEM ITEM2 8 8 UINT ""\n'
            '  ITEM ITEM3 16 8 UINT ""\n'
        )
        self.assertEqual(config, expected)

if __name__ == '__main__':
    unittest.main()
