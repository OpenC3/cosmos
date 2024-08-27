
import unittest
from unittest.mock import patch, MagicMock
from openc3.models.target_model import TargetModel
from openc3.utilities.store import Store

'''
This unit test program covers the following scenarios for the `packet_item` class method:

1. Successful retrieval of an item from a telemetry packet
2. Handling of an invalid packet type
3. Handling of a nonexistent packet
4. Handling of a nonexistent item within an existing packet
5. Successful retrieval of an item from a command packet

The test suite uses `unittest.mock` to mock the `Store` class and control its behavior for different test scenarios. This allows us to test the method's behavior without actually interacting with a real data store.

To run these tests, save the code in a file (e.g., `test_target_model_packet_item.py`) and execute it using Python. Make sure you have the necessary dependencies installed and that the `openc3` module is in your Python path.
'''

class TestTargetModelPacketItem(unittest.TestCase):

    @patch('openc3.models.target_model.Store')
    def setUp(self, mock_store):
        self.mock_store = mock_store
        self.scope = 'SCOPE'
        self.target_name = 'TARGET'
        self.packet_name = 'PACKET'
        self.item_name = 'ITEM'

    def test_packet_item_success(self):
        # Arrange
        mock_packet = {
            'target_name': self.target_name,
            'packet_name': self.packet_name,
            'items': [
                {'name': self.item_name, 'data': 'test_data'},
                {'name': 'OTHER_ITEM', 'data': 'other_data'}
            ]
        }
        self.mock_store.hget.return_value = '{"target_name": "TARGET", "packet_name": "PACKET", "items": [{"name": "ITEM", "data": "test_data"}, {"name": "OTHER_ITEM", "data": "other_data"}]}'

        # Act
        result = TargetModel.packet_item(self.target_name, self.packet_name, self.item_name, scope=self.scope)

        # Assert
        self.assertEqual(result, {'name': self.item_name, 'data': 'test_data'})
        self.mock_store.hget.assert_called_once_with(f'{self.scope}__openc3tlm__{self.target_name}', self.packet_name)

    def test_packet_item_invalid_type(self):
        # Act & Assert
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packet_item(self.target_name, self.packet_name, self.item_name, type='INVALID', scope=self.scope)
        
        self.assertEqual(str(context.exception), f"Unknown type INVALID for {self.target_name} {self.packet_name}")

    def test_packet_item_nonexistent_packet(self):
        # Arrange
        self.mock_store.hget.return_value = None

        # Act & Assert
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packet_item(self.target_name, self.packet_name, self.item_name, scope=self.scope)
        
        self.assertEqual(str(context.exception), f"Packet '{self.target_name} {self.packet_name}' does not exist")

    def test_packet_item_nonexistent_item(self):
        # Arrange
        self.mock_store.hget.return_value = '{"target_name": "TARGET", "packet_name": "PACKET", "items": [{"name": "OTHER_ITEM", "data": "other_data"}]}'

        # Act & Assert
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packet_item(self.target_name, self.packet_name, self.item_name, scope=self.scope)
        
        self.assertEqual(str(context.exception), f"Item '{self.target_name} {self.packet_name} {self.item_name}' does not exist")

    def test_packet_item_cmd_type(self):
        # Arrange
        self.mock_store.hget.return_value = '{"target_name": "TARGET", "packet_name": "PACKET", "items": [{"name": "ITEM", "data": "cmd_data"}]}'

        # Act
        result = TargetModel.packet_item(self.target_name, self.packet_name, self.item_name, type='CMD', scope=self.scope)

        # Assert
        self.assertEqual(result, {'name': self.item_name, 'data': 'cmd_data'})
        self.mock_store.hget.assert_called_once_with(f'{self.scope}__openc3cmd__{self.target_name}', self.packet_name)

if __name__ == '__main__':
    unittest.main()
