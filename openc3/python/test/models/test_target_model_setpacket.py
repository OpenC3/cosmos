
import unittest
from unittest.mock import patch, MagicMock
import json
from openc3.models.target_model import TargetModel
from openc3.utilities.store import Store
from openc3.utilities.logger import Logger

'''
This unit test program covers the following scenarios for the `set_packet` class method:

1. Setting a telemetry packet successfully
2. Setting a command packet successfully
3. Attempting to set a packet with an invalid type
4. Handling a JSON encoding error when setting a packet

The test cases use the `unittest.mock.patch` decorator to mock the `Store.hset` method and the `Logger.error` method where necessary. This allows us to verify that the correct methods are called with the expected arguments and to simulate error conditions.

To run these tests, make sure you have the necessary imports and the `TargetModel` class available in your Python environment. Then, you can run the tests using a test runner or by executing the script directly.
'''

class TestTargetModelSetPacket(unittest.TestCase):

    def setUp(self):
        self.target_name = "TEST_TARGET"
        self.packet_name = "TEST_PACKET"
        self.packet = {"name": "TEST_PACKET", "items": [{"name": "ITEM1"}]}
        self.scope = "DEFAULT"

    @patch('openc3.utilities.store.Store.hset')
    def test_set_packet_telemetry(self, mock_hset):
        TargetModel.set_packet(self.target_name, self.packet_name, self.packet, type="TLM", scope=self.scope)
        mock_hset.assert_called_once_with(
            f"{self.scope}__openc3tlm__{self.target_name}",
            self.packet_name,
            json.dumps(self.packet)
        )

    @patch('openc3.utilities.store.Store.hset')
    def test_set_packet_command(self, mock_hset):
        TargetModel.set_packet(self.target_name, self.packet_name, self.packet, type="CMD", scope=self.scope)
        mock_hset.assert_called_once_with(
            f"{self.scope}__openc3cmd__{self.target_name}",
            self.packet_name,
            json.dumps(self.packet)
        )

    def test_set_packet_invalid_type(self):
        with self.assertRaises(RuntimeError) as context:
            TargetModel.set_packet(self.target_name, self.packet_name, self.packet, type="INVALID", scope=self.scope)
        self.assertEqual(str(context.exception), "Unknown type INVALID for TEST_TARGET TEST_PACKET")

    @patch('openc3.utilities.store.Store.hset')
    @patch('openc3.utilities.logger.Logger.error')
    def test_set_packet_json_error(self, mock_logger_error, mock_hset):
        mock_hset.side_effect = RuntimeError("JSON encoding error")

        with self.assertRaises(RuntimeError) as context:
            TargetModel.set_packet(self.target_name, self.packet_name, self.packet, type="TLM", scope=self.scope)

        self.assertEqual(str(context.exception), "JSON encoding error")
        mock_logger_error.assert_called_once_with("Invalid text present in TEST_TARGET TEST_PACKET tlm packet")

if __name__ == '__main__':
    unittest.main()
