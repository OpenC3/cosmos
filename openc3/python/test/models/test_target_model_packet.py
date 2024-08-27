
import unittest
from unittest.mock import patch, MagicMock
import json
from openc3.models.target_model import TargetModel
from openc3.utilities.store import Store

'''
This unit test program covers the following scenarios for the `packet` class method:

1. Retrieving a valid telemetry packet
2. Retrieving a valid command packet
3. Attempting to retrieve a packet with an invalid type
4. Attempting to retrieve a non-existent packet
5. Using the default type (TLM)
6. Using the default scope

The tests use the `unittest.mock.patch` decorator to mock the `Store.hget` method, allowing us to control its behavior and verify that it's called with the correct arguments.

This test suite provides good coverage of the `packet` method, testing both successful and error cases, as well as default parameter behavior.
'''

class TestTargetModelPacket(unittest.TestCase):

    def setUp(self):
        self.scope = "SCOPE"
        self.target_name = "TARGET"
        self.packet_name = "PACKET"
        self.sample_packet = {
            "target_name": self.target_name,
            "packet_name": self.packet_name,
            "items": [
                {"name": "ITEM1"},
                {"name": "ITEM2"}
            ]
        }

    @patch.object(Store, 'hget')
    def test_packet_valid_tlm(self, mock_hget):
        mock_hget.return_value = json.dumps(self.sample_packet)
        result = TargetModel.packet(self.target_name, self.packet_name, type="TLM", scope=self.scope)
        self.assertEqual(result, self.sample_packet)
        mock_hget.assert_called_once_with(f"{self.scope}__openc3tlm__{self.target_name}", self.packet_name)

    @patch.object(Store, 'hget')
    def test_packet_valid_cmd(self, mock_hget):
        mock_hget.return_value = json.dumps(self.sample_packet)
        result = TargetModel.packet(self.target_name, self.packet_name, type="CMD", scope=self.scope)
        self.assertEqual(result, self.sample_packet)
        mock_hget.assert_called_once_with(f"{self.scope}__openc3cmd__{self.target_name}", self.packet_name)

    def test_packet_invalid_type(self):
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packet(self.target_name, self.packet_name, type="INVALID", scope=self.scope)
        self.assertEqual(str(context.exception), f"Unknown type INVALID for {self.target_name} {self.packet_name}")

    @patch.object(Store, 'hget')
    def test_packet_not_found(self, mock_hget):
        mock_hget.return_value = None
        with self.assertRaises(RuntimeError) as context:
            TargetModel.packet(self.target_name, self.packet_name, scope=self.scope)
        self.assertEqual(str(context.exception), f"Packet '{self.target_name} {self.packet_name}' does not exist")

    @patch.object(Store, 'hget')
    def test_packet_default_type(self, mock_hget):
        mock_hget.return_value = json.dumps(self.sample_packet)
        TargetModel.packet(self.target_name, self.packet_name, scope=self.scope)
        mock_hget.assert_called_once_with(f"{self.scope}__openc3tlm__{self.target_name}", self.packet_name)

    @patch.object(Store, 'hget')
    def test_packet_default_scope(self, mock_hget):
        mock_hget.return_value = json.dumps(self.sample_packet)
        with patch('openc3.models.target_model.OPENC3_SCOPE', 'DEFAULT_SCOPE'):
            TargetModel.packet(self.target_name, self.packet_name)
        mock_hget.assert_called_once_with(f"DEFAULT_SCOPE__openc3tlm__{self.target_name}", self.packet_name)

if __name__ == '__main__':
    unittest.main()
