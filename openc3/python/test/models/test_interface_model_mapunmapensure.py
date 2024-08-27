
import unittest
from unittest.mock import patch, MagicMock
from openc3.models.interface_model import InterfaceModel
from openc3.models.target_model import TargetModel
from openc3.models.microservice_model import MicroserviceModel

'''
This test program covers the `ensure_target_exists()`, `unmap_target()`, and `map_target()` methods of the InterfaceModel class. Here's a breakdown of the test cases:

1. `test_ensure_target_exists_success`: Tests that the method returns a target when it exists.
2. `test_ensure_target_exists_failure`: Tests that the method raises a RuntimeError when the target doesn't exist.
3. `test_unmap_target_cmd_only`: Tests unmapping a target for commands only.
4. `test_unmap_target_tlm_only`: Tests unmapping a target for telemetry only.
5. `test_unmap_target_both`: Tests unmapping a target for both commands and telemetry.
6. `test_map_target_new`: Tests mapping a new target.
7. `test_map_target_cmd_only`: Tests mapping a target for commands only.
8. `test_map_target_tlm_only`: Tests mapping a target for telemetry only.
9. `test_map_target_unmap_old`: Tests mapping a target that was previously mapped to another interface.

'''

class TestInterfaceModel(unittest.TestCase):

    def setUp(self):
        self.interface = InterfaceModel("test_interface", scope="TEST")

    def test_ensure_target_exists_success(self):
        with patch.object(TargetModel, 'get', return_value=MagicMock()):
            target = self.interface.ensure_target_exists("EXISTING_TARGET")
            self.assertIsNotNone(target)

    def test_ensure_target_exists_failure(self):
        with patch.object(TargetModel, 'get', return_value=None):
            with self.assertRaises(RuntimeError):
                self.interface.ensure_target_exists("NON_EXISTING_TARGET")

    def test_unmap_target_cmd_only(self):
        self.interface.target_names = ["TARGET1", "TARGET2"]
        self.interface.cmd_target_names = ["TARGET1", "TARGET2"]
        self.interface.tlm_target_names = ["TARGET1", "TARGET2"]

        with patch.object(self.interface, 'update'), \
             patch.object(MicroserviceModel, 'get_model', return_value=MagicMock()):
            self.interface.unmap_target("TARGET1", cmd_only=True)

            self.assertEqual(self.interface.target_names, ["TARGET2"])
            self.assertEqual(self.interface.cmd_target_names, ["TARGET2"])
            self.assertEqual(self.interface.tlm_target_names, ["TARGET1", "TARGET2"])

    def test_unmap_target_tlm_only(self):
        self.interface.target_names = ["TARGET1", "TARGET2"]
        self.interface.cmd_target_names = ["TARGET1", "TARGET2"]
        self.interface.tlm_target_names = ["TARGET1", "TARGET2"]

        with patch.object(self.interface, 'update'), \
             patch.object(MicroserviceModel, 'get_model', return_value=MagicMock()):
            self.interface.unmap_target("TARGET1", tlm_only=True)

            self.assertEqual(self.interface.target_names, ["TARGET2"])
            self.assertEqual(self.interface.cmd_target_names, ["TARGET1", "TARGET2"])
            self.assertEqual(self.interface.tlm_target_names, ["TARGET2"])

    def test_unmap_target_both(self):
        self.interface.target_names = ["TARGET1", "TARGET2"]
        self.interface.cmd_target_names = ["TARGET1", "TARGET2"]
        self.interface.tlm_target_names = ["TARGET1", "TARGET2"]

        with patch.object(self.interface, 'update'), \
             patch.object(MicroserviceModel, 'get_model', return_value=MagicMock()):
            self.interface.unmap_target("TARGET1")

            self.assertEqual(self.interface.target_names, ["TARGET2"])
            self.assertEqual(self.interface.cmd_target_names, ["TARGET2"])
            self.assertEqual(self.interface.tlm_target_names, ["TARGET2"])

    def test_map_target_new(self):
        with patch.object(self.interface, 'ensure_target_exists'), \
             patch.object(InterfaceModel, 'all', return_value={}), \
             patch.object(self.interface, 'update'), \
             patch.object(MicroserviceModel, 'get_model', return_value=MagicMock()):
            self.interface.map_target("NEW_TARGET")

            self.assertIn("NEW_TARGET", self.interface.target_names)
            self.assertIn("NEW_TARGET", self.interface.cmd_target_names)
            self.assertIn("NEW_TARGET", self.interface.tlm_target_names)

    def test_map_target_cmd_only(self):
        with patch.object(self.interface, 'ensure_target_exists'), \
             patch.object(InterfaceModel, 'all', return_value={}), \
             patch.object(self.interface, 'update'), \
             patch.object(MicroserviceModel, 'get_model', return_value=MagicMock()):
            self.interface.map_target("NEW_TARGET", cmd_only=True)

            self.assertIn("NEW_TARGET", self.interface.target_names)
            self.assertIn("NEW_TARGET", self.interface.cmd_target_names)
            self.assertIn("NEW_TARGET", self.interface.tlm_target_names)

    def test_map_target_tlm_only(self):
        with patch.object(self.interface, 'ensure_target_exists'), \
             patch.object(InterfaceModel, 'all', return_value={}), \
             patch.object(self.interface, 'update'), \
             patch.object(MicroserviceModel, 'get_model', return_value=MagicMock()):
            self.interface.map_target("NEW_TARGET", tlm_only=True)

            self.assertIn("NEW_TARGET", self.interface.target_names)
            self.assertIn("NEW_TARGET", self.interface.cmd_target_names)
            self.assertIn("NEW_TARGET", self.interface.tlm_target_names)

    def test_map_target_unmap_old(self):
        old_interface = MagicMock()
        old_interface.target_names = ["OLD_TARGET"]
        with patch.object(self.interface, 'ensure_target_exists'), \
             patch.object(InterfaceModel, 'all', return_value={"old": {"target_names": ["OLD_TARGET"]}}), \
             patch.object(InterfaceModel, 'from_json', return_value=old_interface), \
             patch.object(self.interface, 'update'), \
             patch.object(MicroserviceModel, 'get_model', return_value=MagicMock()):
            self.interface.map_target("OLD_TARGET")

            old_interface.unmap_target.assert_called_once_with("OLD_TARGET", cmd_only=False, tlm_only=False)
            self.assertIn("OLD_TARGET", self.interface.target_names)
            self.assertIn("OLD_TARGET", self.interface.cmd_target_names)
            self.assertIn("OLD_TARGET", self.interface.tlm_target_names)

if __name__ == '__main__':
    unittest.main()
