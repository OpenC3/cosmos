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
from openc3.tools.table_manager.table_config import TableConfig
from openc3.tools.table_manager.table_item import TableItem

class TestTableItemParser(unittest.TestCase):
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
            file.write('  APPEND_PARAMETER "PARAM1" 8 UINT 0 0xFF 0\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        item = config.tables["TEST"].sorted_items[0]
        self.assertIsInstance(item, TableItem)
        self.assertEqual(item.editable, True)
        self.assertEqual(item.hidden, False)
        self.assertEqual(item.name, "PARAM1")
        self.assertEqual(item.bit_size, 8)
        self.assertEqual(item.data_type, "UINT")
        self.assertEqual(item.minimum, 0)
        self.assertEqual(item.maximum, 0xFF)
        self.assertEqual(item.default, 0)

    def test_parse_with_id(self):
        """Test parsing a table item with ID"""
        def_path = os.path.join(self.temp_dir, "tabledef.txt")
        with open(def_path, 'w') as file:
            file.write('TABLE "TEST" BIG_ENDIAN KEY_VALUE "Description"\n')
            file.write('  APPEND_ID_PARAMETER PARAM1 8 UINT 0 0xFF 0xAB 0\n')

        config = TableConfig.process_file(def_path)
        self.assertTrue("TEST" in config.tables)
        item = config.tables["TEST"].id_items[0]
        self.assertEqual(item.name, "PARAM1")
        self.assertEqual(item.id_value, 0xAB)

if __name__ == '__main__':
    unittest.main()