
import unittest
from unittest.mock import patch, MagicMock
from openc3.models.target_model import TargetModel
from openc3.utilities.store import Store

'''
This unit test program covers the following scenarios for the `packets` class method:

1. Successful retrieval of TLM packets
2. Successful retrieval of CMD packets
3. Error handling for invalid packet type
4. Error handling for non-existent target
5. Handling of empty result (target exists but has no packets)

The test uses `unittest.mock` to patch the `Store` class and the `TargetModel.get` method, allowing us to control their behavior without actually interacting with a real database or storage system.

To run this test, save it in a file (e.g., `test_target_model_packets.py`) and execute it using Python:

```
python test_target_model_packets.py
```

This test suite should provide good coverage for the `packets` class method. Note that you might need to adjust the import statements depending on your project structure and how the `openc3` module is set up in your environment.
'''

class TestTargetModelPackets(unittest.TestCase):

    @patch('openc3.models.target_model.Store')
    @patch('openc3.models.target_model.TargetModel.get')
    def test_packets_success(self, mock_get, mock_store):
        # Setup
        target_name = "TEST_TARGET"
        scope = "DEFAULT"
        mock_get.return_value = True  # Simulate target exists
        mock_store.hgetall.return_value = {
            "PACKET1": '{"name": "PACKET1", "items": []}',
            "PACKET2": '{"name": "PACKET2", "items": []}'
        }

        # Test TLM packets
        result = TargetModel.packets(target_name, type="TLM", scope=scope)
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["name"], "PACKET1")
        self.assertEqual(result[1]["name"], "PACKET2")

        mock_store.hgetall.assert_called_with(f"{scope}__openc3tlm__{target_name}")

        # Test CMD packets
        result = TargetModel.packets(target_name, type="CMD", scope=scope)
        self.assertEqual(len(result), 2)
        mock_store.hgetall.assert_called_with(f"{scope}__openc3cmd__{target_name}")

    @patch('openc3.models.target_model.TargetModel.get')
    def test_packets_invalid_type(self, mock_get):
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packets("TEST_TARGET", type="INVALID")
        self.assertIn("Unknown type INVALID for TEST_TARGET", str(context.exception))

    @patch('openc3.models.target_model.TargetModel.get')
    def test_packets_target_not_exist(self, mock_get):
        mock_get.return_value = None  # Simulate target does not exist
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packets("NONEXISTENT_TARGET")
        self.assertIn("Target 'NONEXISTENT_TARGET' does not exist", str(context.exception))

    @patch('openc3.models.target_model.Store')
    @patch('openc3.models.target_model.TargetModel.get')
    def test_packets_empty_result(self, mock_get, mock_store):
        mock_get.return_value = True  # Simulate target exists
        mock_store.hgetall.return_value = {}  # Empty result

        result = TargetModel.packets("EMPTY_TARGET")
        self.assertEqual(result, [])

if __name__ == '__main__':
    unittest.main()
