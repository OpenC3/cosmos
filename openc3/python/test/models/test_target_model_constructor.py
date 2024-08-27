
import unittest
from unittest.mock import patch
from openc3.models.target_model import TargetModel
from openc3.environment import OPENC3_SCOPE

'''
This test suite covers the following scenarios for the TargetModel constructor:

1. Creating a TargetModel with only the required 'name' argument.
2. Creating a TargetModel with all possible arguments.
3. Creating a TargetModel with some, but not all, optional arguments.

The tests use unittest.mock.patch to mock the superclass (Model) __init__ method, allowing us to verify that it's called correctly with the expected arguments.

These tests check:

- The correct formation of the primary key (scope + "__openc3_targets")
- Proper passing of arguments to the superclass constructor
- Setting of the folder_name attribute
- Default values for optional arguments

This test suite should provide good coverage of the TargetModel constructor method. Run these tests to ensure the constructor behaves as expected under various input conditions.
'''

class TestTargetModelConstructor(unittest.TestCase):

    @patch('openc3.models.model.Model.__init__')
    def test_constructor_with_minimal_args(self, mock_super_init):
        target = TargetModel("test_target")
        mock_super_init.assert_called_once_with(
            f"{OPENC3_SCOPE}__openc3_targets",
            name="test_target",
            plugin=None,
            updated_at=None,
            scope=OPENC3_SCOPE
        )
        self.assertIsNone(target.folder_name)

    @patch('openc3.models.model.Model.__init__')
    def test_constructor_with_all_args(self, mock_super_init):
        target = TargetModel(
            name="test_target",
            folder_name="test_folder",
            updated_at=1234567890,
            plugin="test_plugin",
            scope="custom_scope"
        )
        mock_super_init.assert_called_once_with(
            "custom_scope__openc3_targets",
            name="test_target",
            plugin="test_plugin",
            updated_at=1234567890,
            scope="custom_scope"
        )
        self.assertEqual(target.folder_name, "test_folder")

    @patch('openc3.models.model.Model.__init__')
    def test_constructor_with_some_args(self, mock_super_init):
        target = TargetModel(
            name="test_target",
            folder_name="test_folder",
            updated_at=1234567890
        )
        mock_super_init.assert_called_once_with(
            f"{OPENC3_SCOPE}__openc3_targets",
            name="test_target",
            plugin=None,
            updated_at=1234567890,
            scope=OPENC3_SCOPE
        )
        self.assertEqual(target.folder_name, "test_folder")

if __name__ == '__main__':
    unittest.main()
