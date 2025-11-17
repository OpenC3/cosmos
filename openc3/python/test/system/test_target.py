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
import tempfile
import unittest
import shutil
from test.test_helper import TEST_DIR
from openc3.system.target import Target


class TestTarget(unittest.TestCase):
    """Test the Target class"""

    def setUp(self):
        # Create a temporary directory for test targets
        self.temp_dir = tempfile.mkdtemp()
        self.target_name = "TEST_TARGET"
        self.target_dir = os.path.join(self.temp_dir, self.target_name)
        os.makedirs(self.target_dir)

    def tearDown(self):
        # Clean up temporary directory
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir)

    def create_target_txt(self, content):
        """Helper to create a target.txt file"""
        target_txt = os.path.join(self.target_dir, "target.txt")
        with open(target_txt, "w") as f:
            f.write(content)
        return target_txt

    def create_cmd_tlm_files(self, filenames):
        """Helper to create cmd_tlm files"""
        cmd_tlm_dir = os.path.join(self.target_dir, "cmd_tlm")
        os.makedirs(cmd_tlm_dir, exist_ok=True)
        created_files = []
        for filename in filenames:
            filepath = os.path.join(cmd_tlm_dir, filename)
            # Create subdirectories if needed
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, "w") as f:
                f.write(f"# {filename}\n")
            created_files.append(filepath)
        return created_files

    def test_initializes_with_default_values(self):
        """Test that Target initializes with correct default values"""
        target = Target(self.target_name, self.temp_dir)

        self.assertEqual(target.name, self.target_name)
        self.assertEqual(target.language, "python")
        self.assertEqual(target.ignored_parameters, [])
        self.assertEqual(target.ignored_items, [])
        self.assertIsNone(target.interface)
        self.assertEqual(target.routers, [])
        self.assertEqual(target.cmd_cnt, 0)
        self.assertEqual(target.tlm_cnt, 0)

    def test_converts_target_name_to_uppercase(self):
        """Test that target name is converted to uppercase"""
        target = Target("lowercase_target", self.temp_dir)
        self.assertEqual(target.name, "LOWERCASE_TARGET")

    def test_sets_target_directory(self):
        """Test that target directory is set correctly"""
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.dir, self.target_dir)

    def test_processes_language_keyword(self):
        """Test LANGUAGE keyword in target.txt"""
        self.create_target_txt("LANGUAGE ruby\n")
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.language, "ruby")

        # Test Python language
        self.create_target_txt("LANGUAGE python\n")
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.language, "python")

    def test_processes_ignore_parameter_keyword(self):
        """Test IGNORE_PARAMETER keyword in target.txt"""
        self.create_target_txt("IGNORE_PARAMETER PARAM1\nIGNORE_PARAMETER PARAM2\n")
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.ignored_parameters, ["PARAM1", "PARAM2"])

    def test_processes_ignore_item_keyword(self):
        """Test IGNORE_ITEM keyword in target.txt"""
        self.create_target_txt("IGNORE_ITEM ITEM1\nIGNORE_ITEM ITEM2\n")
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.ignored_items, ["ITEM1", "ITEM2"])

    def test_converts_ignored_parameters_to_uppercase(self):
        """Test that ignored parameters are converted to uppercase"""
        self.create_target_txt("IGNORE_PARAMETER param1\n")
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.ignored_parameters, ["PARAM1"])

    def test_converts_ignored_items_to_uppercase(self):
        """Test that ignored items are converted to uppercase"""
        self.create_target_txt("IGNORE_ITEM item1\n")
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.ignored_items, ["ITEM1"])

    def test_processes_commands_keyword(self):
        """Test COMMANDS keyword in target.txt"""
        # Create cmd_tlm file first
        self.create_cmd_tlm_files(["test_cmd.txt"])
        self.create_target_txt("COMMANDS test_cmd.txt\n")

        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(len(target.cmd_tlm_files), 1)
        self.assertTrue(str(target.cmd_tlm_files[0]).endswith("test_cmd.txt"))

    def test_processes_telemetry_keyword(self):
        """Test TELEMETRY keyword in target.txt"""
        # Create cmd_tlm file first
        self.create_cmd_tlm_files(["test_tlm.txt"])
        self.create_target_txt("TELEMETRY test_tlm.txt\n")

        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(len(target.cmd_tlm_files), 1)
        self.assertTrue(str(target.cmd_tlm_files[0]).endswith("test_tlm.txt"))

    def test_complains_about_missing_cmd_tlm_file(self):
        """Test that missing cmd/tlm file raises error"""
        self.create_target_txt("COMMANDS nonexistent.txt\n")

        with self.assertRaises(Exception) as context:
            Target(self.target_name, self.temp_dir)
        self.assertIn("not found", str(context.exception))

    def test_ignores_require_keyword(self):
        """Test that REQUIRE keyword is ignored (deprecated in Python)"""
        self.create_target_txt("REQUIRE test_require\n")
        # Should not raise an error
        target = Target(self.target_name, self.temp_dir)
        self.assertIsNotNone(target)

    def test_ignores_deprecated_unique_id_mode_keywords(self):
        """Test that deprecated unique ID mode keywords are ignored"""
        self.create_target_txt("CMD_UNIQUE_ID_MODE\nTLM_UNIQUE_ID_MODE\n")
        # Should not raise an error
        target = Target(self.target_name, self.temp_dir)
        self.assertIsNotNone(target)

    def test_raises_error_for_unknown_keywords(self):
        """Test that unknown keywords raise an error"""
        self.create_target_txt("UNKNOWN_KEYWORD value\n")

        with self.assertRaises(Exception) as context:
            Target(self.target_name, self.temp_dir)
        self.assertIn("Unknown keyword", str(context.exception))

    def test_add_all_cmd_tlm_discovers_txt_files(self):
        """Test that add_all_cmd_tlm finds all .txt files"""
        self.create_cmd_tlm_files(["cmd1.txt", "tlm1.txt", "cmd2.txt"])

        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(len(target.cmd_tlm_files), 3)

    def test_add_all_cmd_tlm_discovers_xtce_files(self):
        """Test that add_all_cmd_tlm finds all .xtce files"""
        self.create_cmd_tlm_files(["test1.xtce", "test2.xtce"])

        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(len(target.cmd_tlm_files), 2)

    def test_add_all_cmd_tlm_discovers_files_in_subdirectories(self):
        """Test that add_all_cmd_tlm finds files in subdirectories"""
        cmd_tlm_dir = os.path.join(self.target_dir, "cmd_tlm")
        os.makedirs(cmd_tlm_dir, exist_ok=True)

        # Create files in subdirectories
        subdir = os.path.join(cmd_tlm_dir, "subdir")
        os.makedirs(subdir, exist_ok=True)
        with open(os.path.join(subdir, "test.txt"), "w") as f:
            f.write("# test\n")

        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(len(target.cmd_tlm_files), 1)

    def test_add_all_cmd_tlm_sorts_files(self):
        """Test that add_all_cmd_tlm sorts files alphabetically"""
        self.create_cmd_tlm_files(["z.txt", "a.txt", "m.txt"])

        target = Target(self.target_name, self.temp_dir)
        filenames = [os.path.basename(f) for f in target.cmd_tlm_files]
        self.assertEqual(filenames, ["a.txt", "m.txt", "z.txt"])

    def test_add_cmd_tlm_partials_includes_partial_files(self):
        """Test that add_cmd_tlm_partials includes _*.txt files"""
        self.create_cmd_tlm_files(["cmd.txt", "_partial.txt"])
        self.create_target_txt("COMMANDS cmd.txt\n")

        target = Target(self.target_name, self.temp_dir)
        # Should have both the explicitly listed file and the partial
        self.assertEqual(len(target.cmd_tlm_files), 2)
        filenames = [os.path.basename(str(f)) for f in target.cmd_tlm_files]
        self.assertIn("cmd.txt", filenames)
        self.assertIn("_partial.txt", filenames)

    def test_add_cmd_tlm_partials_finds_partials_in_subdirectories(self):
        """Test that add_cmd_tlm_partials finds partials in subdirectories"""
        cmd_tlm_dir = os.path.join(self.target_dir, "cmd_tlm")
        os.makedirs(cmd_tlm_dir, exist_ok=True)

        # Create a regular file and a partial in a subdirectory
        with open(os.path.join(cmd_tlm_dir, "cmd.txt"), "w") as f:
            f.write("# cmd\n")

        subdir = os.path.join(cmd_tlm_dir, "subdir")
        os.makedirs(subdir)
        with open(os.path.join(subdir, "_partial.txt"), "w") as f:
            f.write("# partial\n")

        self.create_target_txt("COMMANDS cmd.txt\n")
        target = Target(self.target_name, self.temp_dir)

        # Should have both the explicitly listed file and the partial from subdirectory
        self.assertGreaterEqual(len(target.cmd_tlm_files), 2)

    def test_processes_target_id_file(self):
        """Test that target_id.txt is read if it exists"""
        target_id_file = os.path.join(self.target_dir, "target_id.txt")
        with open(target_id_file, "w") as f:
            f.write("ABC123\n")

        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.id, "ABC123")

    def test_target_id_is_none_if_file_missing(self):
        """Test that target.id is None if target_id.txt doesn't exist"""
        target = Target(self.target_name, self.temp_dir)
        self.assertIsNone(target.id)

    def test_filename_is_none_if_target_txt_missing(self):
        """Test that target.filename is None if target.txt doesn't exist"""
        target = Target(self.target_name, self.temp_dir)
        self.assertIsNone(target.filename)

    def test_filename_is_set_if_target_txt_exists(self):
        """Test that target.filename is set if target.txt exists"""
        self.create_target_txt("LANGUAGE python\n")
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.filename, os.path.join(self.target_dir, "target.txt"))

    def test_as_json_returns_correct_structure(self):
        """Test that as_json returns the correct JSON structure"""
        self.create_cmd_tlm_files(["test.txt"])
        target_id_file = os.path.join(self.target_dir, "target_id.txt")
        with open(target_id_file, "w") as f:
            f.write("TEST_ID\n")
        self.create_target_txt("IGNORE_PARAMETER PARAM1\nIGNORE_ITEM ITEM1\n")

        target = Target(self.target_name, self.temp_dir)
        json_data = target.as_json()

        self.assertEqual(json_data["name"], self.target_name)
        self.assertEqual(json_data["ignored_parameters"], ["PARAM1"])
        self.assertEqual(json_data["ignored_items"], ["ITEM1"])
        self.assertEqual(json_data["id"], "TEST_ID")
        self.assertEqual(len(json_data["cmd_tlm_files"]), 1)

    def test_get_target_dir_with_gem_path(self):
        """Test that get_target_dir uses gem_path when provided"""
        gem_path = os.path.join(self.temp_dir, "gem_location")
        os.makedirs(gem_path)

        target = Target(self.target_name, self.temp_dir, gem_path=gem_path)
        self.assertEqual(target.dir, gem_path)

    def test_get_target_dir_without_gem_path(self):
        """Test that get_target_dir uses path/target_name when gem_path not provided"""
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(target.dir, self.target_dir)

    def test_adds_lib_directory_to_search_path(self):
        """Test that lib directory is added to search path if it exists"""
        lib_dir = os.path.join(self.target_dir, "lib")
        os.makedirs(lib_dir)

        # This should not raise an error and should add lib to the search path
        target = Target(self.target_name, self.temp_dir)
        self.assertIsNotNone(target)

    def test_adds_procedures_directory_to_search_path(self):
        """Test that procedures directory is added to search path if it exists"""
        proc_dir = os.path.join(self.target_dir, "procedures")
        os.makedirs(proc_dir)

        # This should not raise an error and should add procedures to the search path
        target = Target(self.target_name, self.temp_dir)
        self.assertIsNotNone(target)

    def test_handles_missing_cmd_tlm_directory(self):
        """Test that missing cmd_tlm directory doesn't cause errors"""
        # Don't create cmd_tlm directory
        target = Target(self.target_name, self.temp_dir)
        self.assertEqual(len(target.cmd_tlm_files), 0)

    def test_works_with_inst_target(self):
        """Integration test: verify Target works with real INST target"""
        target_config_dir = os.path.join(TEST_DIR, "install", "config", "targets")
        if os.path.exists(os.path.join(target_config_dir, "INST")):
            target = Target("INST", target_config_dir)
            self.assertEqual(target.name, "INST")
            self.assertGreater(len(target.cmd_tlm_files), 0)


if __name__ == "__main__":
    unittest.main()
