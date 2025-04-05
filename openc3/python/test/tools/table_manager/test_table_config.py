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

import unittest
import os
import tempfile
import shutil
from openc3.tools.table_manager.table_config import TableConfig
from openc3.tools.table_manager.table import Table

class TestTableConfig(unittest.TestCase):
    def setUp(self):
        # Create a temporary directory for testing
        self.temp_dir = tempfile.mkdtemp()

    def tearDown(self):
        # Remove the directory after the test
        shutil.rmtree(self.temp_dir)

    def test_process_file(self):
        """Test process_file class method"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_PARAMETER "test" 8 UINT 0 0xFF 0\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        self.assertEqual(config.tables["TEST"].table_name, "TEST")

    def test_properties(self):
        """Test various property methods"""
        config = TableConfig()
        table = Table("test", "BIG_ENDIAN", "KEY_VALUE", "Description", "filename")
        config.commands[Table.TARGET]["TEST"] = table
        config.definitions["TEST"] = ["filename", "content"]

        self.assertEqual(config.tables, {"TEST": table})
        self.assertEqual(config.definition("test"), ["filename", "content"])
        self.assertEqual(config.table_names, ["TEST"])
        self.assertEqual(config.table("test"), table)

    def test_process_file_with_types(self):
        """Test processing a file with different parameter types"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_PARAMETER "uint" 8 UINT 0 0xFF 0\n')
            file.write('  APPEND_PARAMETER "int" 8 INT -127 127 0\n')
            file.write('  APPEND_PARAMETER "float" 32 FLOAT MIN MAX 0\n')
            file.write('  APPEND_PARAMETER "string" 8 STRING 0x0 "Test"\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        table = config.tables["TEST"]
        self.assertEqual(len(table.sorted_items), 4)
        self.assertEqual(table.sorted_items[0].name, "UINT")
        self.assertEqual(table.sorted_items[1].name, "INT")
        self.assertEqual(table.sorted_items[2].name, "FLOAT")
        self.assertEqual(table.sorted_items[3].name, "STRING")

    def test_process_file_with_state_parameters(self):
        """Test processing a file with state parameters"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_PARAMETER "state" 8 UINT 0 1 0\n')
            file.write('    STATE DISABLE 0\n')
            file.write('    STATE ENABLE 1\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        table = config.tables["TEST"]
        self.assertEqual(table.sorted_items[0].name, "STATE")
        self.assertEqual(table.sorted_items[0].states, {"DISABLE": 0, "ENABLE": 1})

    def test_process_file_with_hidden_and_uneditable(self):
        """Test processing a file with hidden and uneditable parameters"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_PARAMETER "hidden" 8 UINT 0 0xFF 0\n')
            file.write('    HIDDEN\n')
            file.write('  APPEND_PARAMETER "uneditable" 8 UINT 0 0xFF 0\n')
            file.write('    UNEDITABLE\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        table = config.tables["TEST"]
        self.assertEqual(table.sorted_items[0].name, "HIDDEN")
        self.assertEqual(table.sorted_items[0].hidden, True)
        self.assertEqual(table.sorted_items[1].name, "UNEDITABLE")
        self.assertEqual(table.sorted_items[1].editable, False)

    def test_row_column_table(self):
        """Test processing a ROW_COLUMN table"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN ROW_COLUMN 3 "Description"\n')
            file.write('  APPEND_PARAMETER "param1" 8 UINT 0 0xFF 0 "ITEM"\n')
            file.write('  APPEND_PARAMETER "param2" 8 UINT 0 0xFF 0 "ITEM"\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        table = config.tables["TEST"]
        self.assertEqual(table.type, "ROW_COLUMN")
        self.assertEqual(table.num_rows, 3)
        self.assertEqual(table.num_columns, 2)
        # Expected: num_columns (2) * num_rows (3) = 6 items
        names = [item.name for item in table.sorted_items]
        print(table.sorted_items)
        print(names)
        self.assertEqual(len(table.sorted_items), 6)  # 2 items * 3 rows

    def test_process_file_with_includes(self):
        """Test processing a file with includes"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLEFILE "include.txt"\n')

        include_path = os.path.join(self.temp_dir, "include.txt")
        with open(include_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_PARAMETER "param" 8 UINT 0 0xFF 0\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)

    def test_finish_packet_with_default_values(self):
        """Test finishing a packet with default values"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "Test" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_PARAMETER "uint" 8 UINT 0 0xFF 0\n')
            file.write('  APPEND_PARAMETER "int" 8 INT -127 127 0\n')
            file.write('  APPEND_PARAMETER "state" 8 UINT 0 1 0\n')
            file.write('    STATE DISABLE 0\n')
            file.write('    STATE ENABLE 1\n')
            file.write('DEFAULT 10 -20 ENABLE\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        table = config.tables["TEST"]
        self.assertEqual(table.sorted_items[0].default, 10)
        self.assertEqual(table.sorted_items[1].default, -20)
        self.assertEqual(table.sorted_items[2].default, 1)  # ENABLE maps to 1

if __name__ == '__main__':
    unittest.main()