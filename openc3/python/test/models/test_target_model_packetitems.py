
import unittest
from unittest.mock import patch, MagicMock
from openc3.models.target_model import TargetModel

'''
This unit test program covers the following scenarios for the `packet_items` class method:

1. Successful retrieval of packet items
2. Handling of items not found in the packet
3. Handling of an empty list of items
4. Handling of an invalid packet type
5. Handling of the "CMD" packet type

The tests use mocking to isolate the `packet_items` method and avoid dependencies on external systems or other methods. The `setUp` method is used to set up common mocks and test data.

To run these tests, you would need to have the `openc3` package installed and the `TargetModel` class available in the `openc3.models.target_model` module. You can run the tests using a test runner or by executing the script directly.
'''

class TestTargetModelPacketItems(unittest.TestCase):

    @patch('openc3.models.target_model.Store')
    def setUp(self, mock_store):
        self.mock_store = mock_store
        self.target_name = "TEST_TARGET"
        self.packet_name = "TEST_PACKET"
        self.scope = "TEST_SCOPE"

    def test_packet_items_success(self):
        # Mock the packet method to return a packet with items
        mock_packet = {
            "target_name": self.target_name,
            "packet_name": self.packet_name,
            "items": [
                {"name": "ITEM1"},
                {"name": "ITEM2"},
                {"name": "ITEM3"}
            ]
        }
        with patch.object(TargetModel, 'packet', return_value=mock_packet):
            items = ["ITEM1", "ITEM2"]
            result = TargetModel.packet_items(self.target_name, self.packet_name, items, scope=self.scope)
            self.assertEqual(len(result), 2)
            self.assertEqual(result[0]["name"], "ITEM1")
            self.assertEqual(result[1]["name"], "ITEM2")

    def test_packet_items_not_found(self):
        # Mock the packet method to return a packet with items
        mock_packet = {
            "target_name": self.target_name,
            "packet_name": self.packet_name,
            "items": [
                {"name": "ITEM1"},
                {"name": "ITEM2"}
            ]
        }
        with patch.object(TargetModel, 'packet', return_value=mock_packet):
            items = ["ITEM1", "ITEM3"]
            with self.assertRaises(RuntimeError) as context:
                TargetModel.packet_items(self.target_name, self.packet_name, items, scope=self.scope)
            self.assertIn("Item(s) 'TEST_TARGET TEST_PACKET ITEM3' does not exist", str(context.exception))

    def test_packet_items_empty_list(self):
        mock_packet = {
            "target_name": self.target_name,
            "packet_name": self.packet_name,
            "items": [
                {"name": "ITEM1"},
                {"name": "ITEM2"}
            ]
        }
        with patch.object(TargetModel, 'packet', return_value=mock_packet):
            items = []
            result = TargetModel.packet_items(self.target_name, self.packet_name, items, scope=self.scope)
            self.assertEqual(len(result), 0)

    def test_packet_items_invalid_type(self):
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packet_items(self.target_name, self.packet_name, ["ITEM1"], type="INVALID", scope=self.scope)
        self.assertIn("Unknown type INVALID for TEST_TARGET", str(context.exception))

    def test_packet_items_cmd_type(self):
        mock_packet = {
            "target_name": self.target_name,
            "packet_name": self.packet_name,
            "items": [
                {"name": "ITEM1"},
                {"name": "ITEM2"}
            ]
        }
        with patch.object(TargetModel, 'packet', return_value=mock_packet):
            items = ["ITEM1"]
            result = TargetModel.packet_items(self.target_name, self.packet_name, items, type="CMD", scope=self.scope)
            self.assertEqual(len(result), 1)
            self.assertEqual(result[0]["name"], "ITEM1")

if __name__ == '__main__':
    unittest.main()
