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
import shutil
import unittest
import tempfile
from unittest.mock import patch
from openc3.config.config_parser import ConfigParser
from openc3.tools.table_manager.table_config import TableConfig
from openc3.tools.table_manager.table_parser import TableParser
from openc3.tools.table_manager.table import Table

class TestTableParser(unittest.TestCase):
    def setUp(self):
        # Create a temporary directory for testing
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        # Remove the directory after the test
        shutil.rmtree(self.temp_dir)

    def test_verify_parameters(self):
        """Test verifying table parameters"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write("TABLE TABLE1 BIG_ENDIAN KEY_VALUE")
        # Should not raise an exception
        TableConfig.process_file(def_path)

        with open(def_path, 'w') as file:
            file.write("TABLE TABLE1 BIG_ENDIAN KEY_VALUE DESCRIPTION")
        # Should not raise an exception
        TableConfig.process_file(def_path)

        with open(def_path, 'w') as file:
            file.write("TABLE TABLE1 BIG_ENDIAN ROW_COLUMN 3")
        # Should not raise an exception
        TableConfig.process_file(def_path)

        with open(def_path, 'w') as file:
            file.write("TABLE TABLE1 BIG_ENDIAN ROW_COLUMN 3 DESCRIPTION")
        # Should not raise an exception
        TableConfig.process_file(def_path)

        with open(def_path, 'w') as file:
            file.write("TABLE TABLE1 BIG_ENDIAN")
        # Should raise an exception due to too few parameters
        with self.assertRaises(Exception):
            TableConfig.process_file(def_path)

    def test_create_table(self):
        """Test creating tables with various configurations"""
        # Test KEY_VALUE table
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write("TABLE TABLE1 BIG_ENDIAN KEY_VALUE DESCRIPTION")
        config = TableConfig.process_file(def_path)
        table = config.tables["TABLE1"]
        self.assertEqual(table.table_name, "TABLE1")
        self.assertEqual(table.endianness, "BIG_ENDIAN")
        self.assertEqual(table.type, "KEY_VALUE")
        self.assertEqual(table.description, "DESCRIPTION")

        # Test ROW_COLUMN table
        with open(def_path, 'w') as file:
            file.write("TABLE TABLE2 LITTLE_ENDIAN ROW_COLUMN 3 DESCRIPTION")
        config = TableConfig.process_file(def_path)
        table = config.tables["TABLE2"]
        self.assertEqual(table.table_name, "TABLE2")
        self.assertEqual(table.endianness, "LITTLE_ENDIAN")
        self.assertEqual(table.type, "ROW_COLUMN")
        self.assertEqual(table.num_rows, 3)
        self.assertEqual(table.description, "DESCRIPTION")

        # Test invalid endianness
        with open(def_path, 'w') as file:
            file.write("TABLE TABLE3 INVALID KEY_VALUE DESCRIPTION")
        with self.assertRaises(Exception) as context:
            config = TableConfig.process_file(def_path)
        self.assertTrue("Invalid endianness" in str(context.exception))

        # Test invalid type
        with open(def_path, 'w') as file:
            file.write("TABLE TABLE4 BIG_ENDIAN INVALID DESCRIPTION")
        with self.assertRaises(Exception) as context:
            config = TableConfig.process_file(def_path)
        self.assertTrue("Invalid display type" in str(context.exception))

    def test_check_for_duplicate(self):
        """Test checking for duplicate tables"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write("TABLE TABLE1 BIG_ENDIAN KEY_VALUE DESCRIPTION")
        TableConfig.process_file(def_path)

        # with patch('openc3.top_level.Logger') as mock_logger:
        TableConfig.process_file(def_path)
            # self.assertTrue("redefined" in mock_logger)

if __name__ == '__main__':
    unittest.main()