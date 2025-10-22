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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import os
import unittest
import tempfile
import shutil
from unittest.mock import Mock, MagicMock, patch
from openc3.utilities.running_script import RunningScript
from openc3.models.script_status_model import ScriptStatusModel
from openc3.utilities.target_file import TargetFile


class TestRunningScriptNameFile(unittest.TestCase):
    """
    Test __name__ and __file__ behavior in RunningScript.

    These tests verify that:
    1. Main scripts executed via run_thread_body have __name__ = "__main__"
    2. Subscripts called via start() have module-style __name__ (e.g., "TARGET.procedures.my_script")
    3. __file__ is correctly set to the filename for all scripts
    """

    def setUp(self):
        """Set up test fixtures"""
        self.temp_dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.temp_dir)

    def create_test_script(self, filename, content):
        """Helper to create a test script file"""
        filepath = os.path.join(self.temp_dir, filename)
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'w') as f:
            f.write(content)
        return filepath

    @patch('openc3.utilities.running_script.MessageLog')
    @patch.object(TargetFile, 'body')
    @patch('openc3.utilities.running_script.running_script_anycable_publish')
    @patch('openc3.utilities.running_script.Store')
    def test_main_script_has_name_main(self, mock_store, mock_publish, mock_target_file, mock_message_log):
        """Test that the main script executed via run_thread_body has __name__ = '__main__'"""

        # Create a simple test script that captures __name__
        test_script = """
captured_name = __name__
captured_file = __file__
"""

        # Mock the script status
        script_status = Mock(spec=ScriptStatusModel)
        script_status.id = "test-123"
        script_status.scope = "DEFAULT"
        script_status.filename = "main_script.py"
        script_status.disconnect = False
        script_status.script_engine = None
        script_status.start_line_no = 1
        script_status.end_line_no = None
        script_status.suite_runner = None
        script_status.pid = 12345
        script_status.errors = None

        # Mock TargetFile to return our test script
        mock_target_file.return_value = test_script.encode()

        # Mock Store.hget to return None (no breakpoints)
        mock_store.hget.return_value = None

        # Mock MessageLog
        mock_log_instance = Mock()
        mock_message_log.return_value = mock_log_instance

        # Create RunningScript instance
        with patch('openc3.utilities.running_script.glob.glob', return_value=[]):
            running_script = RunningScript(script_status)

        # Execute the script
        running_script.run_thread_body(
            test_script, initial_filename="main_script.py")

        # Verify __name__ was set to "__main__"
        self.assertEqual(running_script.script_globals.get(
            "captured_name"), "__main__")

        # Verify __file__ was set to the filename
        self.assertEqual(running_script.script_globals.get(
            "captured_file"), "main_script.py")

    @patch.object(TargetFile, 'body')
    @patch('openc3.utilities.running_script.running_script_anycable_publish')
    @patch('openc3.utilities.running_script.Store')
    @patch('openc3.utilities.running_script.ScriptStatusModel')
    def test_subscript_via_start_has_module_name(self, mock_status_model, mock_store, mock_publish, mock_target_file):
        """Test that subscripts called via start() have module-style __name__"""

        # Main script that will call start()
        main_script = """
__name__ = "__main__"
__file__ = "main_script.py"
"""

        # Subscript that will be started
        subscript = """
subscript_name = __name__
subscript_file = __file__
"""

        # Mock the script status
        script_status = Mock(spec=ScriptStatusModel)
        script_status.id = "test-456"
        script_status.scope = "DEFAULT"
        script_status.filename = "main_script.py"
        script_status.disconnect = False
        script_status.script_engine = None
        script_status.start_line_no = 1
        script_status.end_line_no = None
        script_status.suite_runner = None
        script_status.pid = 12345

        # Mock TargetFile to return appropriate scripts
        def target_file_body_side_effect(scope, filename):
            if filename == "main_script.py":
                return main_script.encode()
            elif filename == "TARGET/procedures/subscript.py":
                return subscript.encode()
            return None

        mock_target_file.side_effect = target_file_body_side_effect
        mock_status_model.all.return_value = []

        # Mock Store.hget to return None (no breakpoints)
        mock_store.hget.return_value = None

        # Create RunningScript instance
        with patch('openc3.utilities.running_script.glob.glob', return_value=[]):
            running_script = RunningScript(script_status)

        # Set up the globals as if main script is running
        running_script.script_globals["__name__"] = "__main__"
        running_script.script_globals["__file__"] = "main_script.py"

        # Import start function from the module
        from openc3.utilities.running_script import start

        # Call start() to execute the subscript
        start("TARGET/procedures/subscript.py")

        # Verify __name__ was set to module format (not "__main__")
        subscript_name = running_script.script_globals.get("subscript_name")
        self.assertIsNotNone(subscript_name)
        self.assertEqual(subscript_name, "TARGET.procedures.subscript")

        # Verify __file__ was set correctly
        subscript_file = running_script.script_globals.get("subscript_file")
        self.assertIsNotNone(subscript_file)
        self.assertEqual(subscript_file, "TARGET/procedures/subscript.py")

    @patch.object(TargetFile, 'body')
    @patch('openc3.utilities.running_script.running_script_anycable_publish')
    @patch('openc3.utilities.running_script.Store')
    @patch('openc3.utilities.running_script.ScriptStatusModel')
    def test_nested_subscripts_have_module_names(self, mock_status_model, mock_store, mock_publish, mock_target_file):
        """Test that nested subscripts (script A calls B, B calls C) all have proper module names"""

        # Script hierarchy: main -> script_a -> script_b
        main_script = """
__name__ = "__main__"
__file__ = "main.py"
"""

        script_a = """
script_a_name = __name__
script_a_file = __file__
"""

        script_b = """
script_b_name = __name__
script_b_file = __file__
"""

        # Mock the script status
        script_status = Mock(spec=ScriptStatusModel)
        script_status.id = "test-789"
        script_status.scope = "DEFAULT"
        script_status.filename = "main.py"
        script_status.disconnect = False
        script_status.script_engine = None
        script_status.start_line_no = 1
        script_status.end_line_no = None
        script_status.suite_runner = None
        script_status.pid = 12345

        # Mock TargetFile to return appropriate scripts
        def target_file_body_side_effect(scope, filename):
            scripts = {
                "main.py": main_script,
                "lib/script_a.py": script_a,
                "lib/utils/script_b.py": script_b,
            }
            content = scripts.get(filename)
            return content.encode() if content else None

        mock_target_file.side_effect = target_file_body_side_effect
        mock_status_model.all.return_value = []

        # Mock Store.hget to return None (no breakpoints)
        mock_store.hget.return_value = None

        # Create RunningScript instance
        with patch('openc3.utilities.running_script.glob.glob', return_value=[]):
            running_script = RunningScript(script_status)

        # Set up the globals as if main script is running
        running_script.script_globals["__name__"] = "__main__"
        running_script.script_globals["__file__"] = "main.py"

        # Import start function
        from openc3.utilities.running_script import start

        # Call nested starts
        start("lib/script_a.py")
        start("lib/utils/script_b.py")

        # Verify script_a got module-style __name__
        self.assertEqual(running_script.script_globals.get(
            "script_a_name"), "lib.script_a")
        self.assertEqual(running_script.script_globals.get(
            "script_a_file"), "lib/script_a.py")

        # Verify script_b got module-style __name__
        self.assertEqual(running_script.script_globals.get(
            "script_b_name"), "lib.utils.script_b")
        self.assertEqual(running_script.script_globals.get(
            "script_b_file"), "lib/utils/script_b.py")

    @patch.object(TargetFile, 'body')
    @patch('openc3.utilities.running_script.running_script_anycable_publish')
    @patch('openc3.utilities.running_script.Store')
    @patch('openc3.utilities.running_script.ScriptStatusModel')
    def test_parent_name_restored_after_subscript(self, mock_status_model, mock_store, mock_publish, mock_target_file):
        """Test that parent's __name__ is restored after subscript completes"""

        main_script = """
__name__ = "__main__"
__file__ = "main.py"
"""

        subscript = """
subscript_name = __name__
subscript_file = __file__
"""

        # Mock the script status
        script_status = Mock(spec=ScriptStatusModel)
        script_status.id = "test-restore"
        script_status.scope = "DEFAULT"
        script_status.filename = "main.py"
        script_status.disconnect = False
        script_status.script_engine = None
        script_status.start_line_no = 1
        script_status.end_line_no = None
        script_status.suite_runner = None
        script_status.pid = 12345

        # Mock TargetFile
        def target_file_body_side_effect(scope, filename):
            if filename == "main.py":
                return main_script.encode()
            elif filename == "TEST/lib/helper.py":
                return subscript.encode()
            return None

        mock_target_file.side_effect = target_file_body_side_effect
        mock_status_model.all.return_value = []

        # Mock Store.hget to return None (no breakpoints)
        mock_store.hget.return_value = None

        # Create RunningScript instance
        with patch('openc3.utilities.running_script.glob.glob', return_value=[]):
            running_script = RunningScript(script_status)

        # Set up the globals as if main script is running
        running_script.script_globals["__name__"] = "__main__"
        running_script.script_globals["__file__"] = "main.py"

        # Import start function
        from openc3.utilities.running_script import start

        # Call start() to execute the subscript
        start("TEST/lib/helper.py")

        # Verify subscript captured its module-style __name__ during execution
        self.assertEqual(running_script.script_globals.get(
            "subscript_name"), "TEST.lib.helper")
        self.assertEqual(running_script.script_globals.get(
            "subscript_file"), "TEST/lib/helper.py")

        # Verify parent's __name__ was restored after subscript completed
        self.assertEqual(running_script.script_globals.get(
            "__name__"), "__main__")
        self.assertEqual(
            running_script.script_globals.get("__file__"), "main.py")

    def test_filename_to_module_conversion(self):
        """Test that the filename_to_module helper correctly converts filenames"""
        from openc3.utilities.string import filename_to_module

        # Test various filename patterns
        self.assertEqual(filename_to_module("script.py"), "script")
        self.assertEqual(filename_to_module(
            "TARGET/procedures/test.py"), "TARGET.procedures.test")
        self.assertEqual(filename_to_module(
            "lib/utils/helper.py"), "lib.utils.helper")
        self.assertEqual(filename_to_module("A/B/C/D.py"), "A.B.C.D")

    @patch('openc3.utilities.running_script.MessageLog')
    @patch.object(TargetFile, 'body')
    @patch('openc3.utilities.running_script.running_script_anycable_publish')
    @patch('openc3.utilities.running_script.Store')
    def test_scriptrunner_pseudo_scripts_not_instrumented(self, mock_store, mock_publish, mock_target_file, mock_message_log):
        """Test that SCRIPTRUNNER pseudo-scripts still work correctly"""

        # SCRIPTRUNNER is a special case - internal scripts that shouldn't be instrumented
        pseudo_script = "print('SCRIPTRUNNER pseudo script')"

        # Mock the script status
        script_status = Mock(spec=ScriptStatusModel)
        script_status.id = "test-pseudo"
        script_status.scope = "DEFAULT"
        script_status.filename = "main.py"
        script_status.disconnect = False
        script_status.script_engine = None
        script_status.start_line_no = 1
        script_status.end_line_no = None
        script_status.suite_runner = None
        script_status.pid = 12345
        script_status.errors = None

        # Mock TargetFile
        mock_target_file.return_value = b"# main"

        # Mock Store.hget to return None (no breakpoints)
        mock_store.hget.return_value = None

        # Mock MessageLog
        mock_log_instance = Mock()
        mock_message_log.return_value = mock_log_instance

        # Create RunningScript instance
        with patch('openc3.utilities.running_script.glob.glob', return_value=[]):
            running_script = RunningScript(script_status)

        # Execute pseudo script with initial_filename='SCRIPTRUNNER'
        # This should not set __name__ or __file__ since it's not instrumented
        running_script.run_thread_body(
            pseudo_script, initial_filename='SCRIPTRUNNER')

        # For SCRIPTRUNNER pseudo scripts, __name__ and __file__ should still be set
        # even though the script itself isn't instrumented
        self.assertEqual(running_script.script_globals.get(
            "__name__"), "__main__")
        self.assertEqual(running_script.script_globals.get(
            "__file__"), "SCRIPTRUNNER")


if __name__ == '__main__':
    unittest.main()
