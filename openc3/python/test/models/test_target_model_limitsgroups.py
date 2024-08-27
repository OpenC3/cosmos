
import unittest
from unittest.mock import patch
from openc3.models.target_model import TargetModel
from openc3.utilities.store import Store

'''
This unit test program covers the following scenarios for the `limits_groups` class method:

1. Testing with valid data and multiple groups
2. Testing with an empty result
3. Testing with the default scope (when no scope is provided)
4. Testing with invalid JSON data

To run this test, you'll need to make sure you have the necessary imports at the top of your test file:


import unittest
from unittest.mock import patch
import json
from openc3.models.target_model import TargetModel
from openc3.utilities.store import Store


This test suite uses `unittest.mock.patch` to mock the `Store.hgetall` method, allowing us to control its return value and verify how it's called. This approach helps isolate the `limits_groups` method for testing without requiring an actual Redis connection.

Make sure to run this test in an environment where the `openc3` package is available and properly set up.
'''

class TestTargetModelLimitsGroups(unittest.TestCase):

    @patch('openc3.utilities.store.Store.hgetall')
    def test_limits_groups_with_data(self, mock_hgetall):
        # Mock data
        mock_data = {
            b'group1': b'[["TGT", "PKT", "ITEM1"], ["TGT", "PKT", "ITEM2"]]',
            b'group2': b'[["TGT2", "PKT2", "ITEM3"]]'
        }
        mock_hgetall.return_value = mock_data

        # Call the method
        result = TargetModel.limits_groups(scope='SCOPE')

        # Assertions
        self.assertEqual(len(result), 2)
        self.assertIn('group1', result)
        self.assertIn('group2', result)
        self.assertEqual(result['group1'], [["TGT", "PKT", "ITEM1"], ["TGT", "PKT", "ITEM2"]])
        self.assertEqual(result['group2'], [["TGT2", "PKT2", "ITEM3"]])

        # Verify the mock was called with the correct argument
        mock_hgetall.assert_called_once_with('SCOPE__limits_groups')

    @patch('openc3.utilities.store.Store.hgetall')
    def test_limits_groups_empty(self, mock_hgetall):
        # Mock empty data
        mock_hgetall.return_value = {}

        # Call the method
        result = TargetModel.limits_groups(scope='SCOPE')

        # Assertions
        self.assertEqual(result, {})

        # Verify the mock was called with the correct argument
        mock_hgetall.assert_called_once_with('SCOPE__limits_groups')

    @patch('openc3.utilities.store.Store.hgetall')
    def test_limits_groups_default_scope(self, mock_hgetall):
        # Mock data
        mock_data = {b'group1': b'[["TGT", "PKT", "ITEM"]]'}
        mock_hgetall.return_value = mock_data

        # Call the method without specifying scope
        TargetModel.limits_groups()

        # Verify the mock was called with the default scope
        mock_hgetall.assert_called_once_with('DEFAULT__limits_groups')

    @patch('openc3.utilities.store.Store.hgetall')
    def test_limits_groups_invalid_json(self, mock_hgetall):
        # Mock data with invalid JSON
        mock_data = {b'group1': b'invalid_json'}
        mock_hgetall.return_value = mock_data

        # Call the method and check for exception
        with self.assertRaises(json.JSONDecodeError):
            TargetModel.limits_groups(scope='SCOPE')

if __name__ == '__main__':
    unittest.main()
