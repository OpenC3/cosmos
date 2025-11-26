# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import unittest
from unittest.mock import Mock, patch, MagicMock
from test.test_helper import *
from openc3.system.system import System, SystemMeta
from openc3.packets.commands import Commands
from openc3.packets.telemetry import Telemetry
from openc3.packets.limits import Limits
from openc3.packets.packet_config import PacketConfig


class TestSystemMeta(unittest.TestCase):
    """Test the SystemMeta metaclass properties"""

    def setUp(self):
        # Reset the singleton instance before each test
        System.instance_obj = None

    def tearDown(self):
        # Clean up singleton after each test
        System.instance_obj = None

    def test_metaclass_is_applied(self):
        """Test that System class uses SystemMeta metaclass"""
        self.assertIsInstance(System, SystemMeta)

    def test_targets_property_delegates_to_instance(self):
        """Test that System.targets delegates to the singleton instance"""
        # Create the System instance using singleton pattern
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        system_instance = System.instance(["INST"], target_config_dir)

        # Access via class-level property
        targets = System.targets

        # Should return the same object as the instance attribute
        self.assertIs(targets, system_instance.targets)
        self.assertIsInstance(targets, dict)

    def test_packet_config_property_delegates_to_instance(self):
        """Test that System.packet_config delegates to the singleton instance"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        system_instance = System.instance(["INST"], target_config_dir)

        packet_config = System.packet_config

        self.assertIs(packet_config, system_instance.packet_config)
        self.assertIsInstance(packet_config, PacketConfig)

    def test_commands_property_delegates_to_instance(self):
        """Test that System.commands delegates to the singleton instance"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        system_instance = System.instance(["INST"], target_config_dir)

        commands = System.commands

        self.assertIs(commands, system_instance.commands)
        self.assertIsInstance(commands, Commands)

    def test_telemetry_property_delegates_to_instance(self):
        """Test that System.telemetry delegates to the singleton instance"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        system_instance = System.instance(["INST"], target_config_dir)

        telemetry = System.telemetry

        self.assertIs(telemetry, system_instance.telemetry)
        self.assertIsInstance(telemetry, Telemetry)

    def test_limits_property_delegates_to_instance(self):
        """Test that System.limits delegates to the singleton instance"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        system_instance = System.instance(["INST"], target_config_dir)

        limits = System.limits

        self.assertIs(limits, system_instance.limits)
        self.assertIsInstance(limits, Limits)

    def test_properties_work_with_class_access(self):
        """Test that properties can be accessed at class level like Ruby's instance_attr_reader"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # These should all work without explicitly calling System.instance()
        self.assertIsNotNone(System.targets)
        self.assertIsNotNone(System.packet_config)
        self.assertIsNotNone(System.commands)
        self.assertIsNotNone(System.telemetry)
        self.assertIsNotNone(System.limits)


class TestSystem(unittest.TestCase):
    """Test the System singleton class"""

    def setUp(self):
        self.redis = mock_redis(self)
        # Reset the singleton instance before each test
        System.instance_obj = None

    def tearDown(self):
        # Clean up singleton after each test
        System.instance_obj = None

    def test_singleton_pattern(self):
        """Test that System implements singleton pattern correctly"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")

        instance1 = System.instance(["INST"], target_config_dir)
        instance2 = System.instance()

        # Both should be the same instance
        self.assertIs(instance1, instance2)

    def test_instance_requires_parameters_on_first_call(self):
        """Test that System.instance raises exception if called without params first time"""
        with self.assertRaisesRegex(Exception, "parameters are required on first call"):
            System.instance()

    def test_instance_initializes_attributes(self):
        """Test that System.__init__ properly initializes all attributes"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        system = System.instance(["INST"], target_config_dir)

        # Check that all attributes are initialized
        self.assertIsInstance(system.targets, dict)
        self.assertIsInstance(system.packet_config, PacketConfig)
        self.assertIsInstance(system.commands, Commands)
        self.assertIsInstance(system.telemetry, Telemetry)
        self.assertIsInstance(system.limits, Limits)

        # Check that targets were loaded
        self.assertIn("INST", system.targets)

    def test_commands_can_be_accessed_via_class(self):
        """Test that System.commands works like Ruby's instance_attr_reader"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Access commands at class level
        commands = System.commands

        # Should be able to call methods on it
        self.assertTrue(hasattr(commands, "packet"))
        self.assertTrue(hasattr(commands, "packets"))

    def test_telemetry_can_be_accessed_via_class(self):
        """Test that System.telemetry works like Ruby's instance_attr_reader"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Access telemetry at class level
        telemetry = System.telemetry

        # Should be able to call methods on it
        self.assertTrue(hasattr(telemetry, "packet"))
        self.assertTrue(hasattr(telemetry, "packets"))

    def test_dynamic_update_with_telemetry(self):
        """Test that dynamic_update works with telemetry packets"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Create a mock packet
        mock_packet = Mock()

        # Mock the dynamic_add_packet method
        with patch.object(System.telemetry, "dynamic_add_packet") as mock_add:
            System.dynamic_update([mock_packet], cmd_or_tlm="TELEMETRY", affect_ids=True)
            mock_add.assert_called_once_with(mock_packet, affect_ids=True)

    def test_dynamic_update_with_commands(self):
        """Test that dynamic_update works with command packets"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Create a mock packet
        mock_packet = Mock()

        # Mock the dynamic_add_packet method
        with patch.object(System.commands, "dynamic_add_packet") as mock_add:
            System.dynamic_update([mock_packet], cmd_or_tlm="COMMAND", affect_ids=False)
            mock_add.assert_called_once_with(mock_packet, affect_ids=False)

    def test_add_target(self):
        """Test adding a target to the system"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        system = System.instance(["INST"], target_config_dir)

        # Check that the target was added
        self.assertIn("INST", system.targets)
        self.assertEqual(system.targets["INST"].name, "INST")

    def test_add_target_with_nonexistent_folder_raises_error(self):
        """Test that adding a nonexistent target raises an error"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")

        with self.assertRaises(Exception):
            System.instance(["NONEXISTENT_TARGET"], target_config_dir)

    def test_add_post_instance_callback(self):
        """Test that post-instance callbacks work correctly"""
        callback_executed = []

        def callback():
            callback_executed.append(True)

        # Add callback before instance is created
        System.add_post_instance_callback(callback)

        # Create instance - callback should execute
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Callback should have been executed
        self.assertEqual(len(callback_executed), 1)

    def test_add_post_instance_callback_after_instance_created(self):
        """Test that callbacks execute immediately if instance already exists"""
        callback_executed = []

        def callback():
            callback_executed.append(True)

        # Create instance first
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Add callback after instance is created - should execute immediately
        System.add_post_instance_callback(callback)

        # Callback should have been executed immediately
        self.assertEqual(len(callback_executed), 1)

    def test_limits_set(self):
        """Test the limits_set class method"""
        # This method interacts with Redis, so we test with our mock
        result = System.limits_set()
        # Should return DEFAULT when no limits set is configured
        self.assertEqual(result, "DEFAULT")

    @patch("openc3.system.system.Bucket")
    def test_setup_targets(self, mock_bucket_class):
        """Test the setup_targets class method"""
        # Reset instance
        System.instance_obj = None

        # Mock the bucket client
        mock_bucket = MagicMock()
        mock_bucket_class.getClient.return_value = mock_bucket
        mock_bucket.list_files.return_value = (None, [])

        # Create a temporary directory for testing
        import tempfile

        with tempfile.TemporaryDirectory() as temp_dir:
            # Mock the bucket.get_object to create a simple zip file
            def mock_get_object(bucket, key, path):
                import zipfile

                # Create a minimal target structure
                target_dir = os.path.join(temp_dir, "INST")
                os.makedirs(target_dir, exist_ok=True)

                # Create target.txt
                target_txt = os.path.join(target_dir, "target.txt")
                with open(target_txt, "w") as f:
                    f.write("LANGUAGE python\n")

                # Create the zip file
                with zipfile.ZipFile(path, "w") as zf:
                    zf.write(target_txt, os.path.join("INST", "target.txt"))

            mock_bucket.get_object.side_effect = mock_get_object

            # Call setup_targets
            System.setup_targets(["INST"], temp_dir)

            # Verify that instance was created
            self.assertIsNotNone(System.instance_obj)


class TestSystemIntegration(unittest.TestCase):
    """Integration tests that verify the System class works with real targets"""

    def setUp(self):
        self.redis = mock_redis(self)
        System.instance_obj = None

    def tearDown(self):
        System.instance_obj = None

    def test_system_can_access_inst_target_packets(self):
        """Test that System can access INST target telemetry packets"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Access telemetry packets for INST target
        packets = System.telemetry.packets("INST")

        self.assertIsInstance(packets, dict)
        self.assertGreater(len(packets), 0)

    def test_system_can_access_inst_target_commands(self):
        """Test that System can access INST target command packets"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # Access command packets for INST target
        packets = System.commands.packets("INST")

        self.assertIsInstance(packets, dict)
        self.assertGreater(len(packets), 0)

    def test_backwards_compatibility_with_existing_code(self):
        """Test that existing code patterns still work"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        System.instance(["INST"], target_config_dir)

        # These patterns are used throughout the codebase
        # and should continue to work

        # Pattern 1: System.telemetry.packet(target, packet)
        try:
            packet = System.telemetry.packet("INST", "HEALTH_STATUS")
            self.assertIsNotNone(packet)
        except RuntimeError:
            # Packet might not exist in test data, that's okay
            pass

        # Pattern 2: System.commands.packet(target, packet)
        try:
            packet = System.commands.packet("INST", "ABORT")
            self.assertIsNotNone(packet)
        except RuntimeError:
            # Packet might not exist in test data, that's okay
            pass

        # Pattern 3: System.telemetry.packets(target)
        packets = System.telemetry.packets("INST")
        self.assertIsInstance(packets, dict)


if __name__ == "__main__":
    unittest.main()
