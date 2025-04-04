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
from openc3.tools.table_manager.table import Table
from openc3.tools.table_manager.table_item import TableItem

class TestTable(unittest.TestCase):
    def test_table_name(self):
        """Test that the table name is returned upcased"""
        t = Table("table", "BIG_ENDIAN", "KEY_VALUE", "description", "filename")
        self.assertEqual(t.table_name, "TABLE")

    def test_type(self):
        """Test that the type must be KEY_VALUE or ROW_COLUMN"""
        t = Table("table", "BIG_ENDIAN", "KEY_VALUE", "description", "filename")
        self.assertEqual(t.type, "KEY_VALUE")
        t = Table("table", "BIG_ENDIAN", "ROW_COLUMN", "description", "filename")
        self.assertEqual(t.type, "ROW_COLUMN")
        with self.assertRaises(ValueError) as context:
            Table("table", "BIG_ENDIAN", "BIG", "description", "filename")
        self.assertTrue("Invalid type 'BIG' for table 'table'" in str(context.exception))

    def test_filename(self):
        """Test that the filename is stored correctly"""
        filename = os.path.join(os.getcwd(), "filename")
        t = Table("table", "BIG_ENDIAN", "KEY_VALUE", "description", filename)
        self.assertEqual(t.filename, filename)

    def test_num_rows_set(self):
        """Test setting the number of rows"""
        t = Table("table", "BIG_ENDIAN", "KEY_VALUE", "description", "filename")
        with self.assertRaises(ValueError) as context:
            t.num_rows = 2
        self.assertTrue("Rows are fixed in a KEY_VALUE table" in str(context.exception))

        t = Table("table", "BIG_ENDIAN", "ROW_COLUMN", "description", "filename")
        t.num_rows = 2
        self.assertEqual(t.num_rows, 2)

    def test_num_rows(self):
        """Test the number of rows property"""
        t = Table("table", "BIG_ENDIAN", "KEY_VALUE", "description", "filename")
        self.assertEqual(t.num_rows, 0)

        t = Table("table", "BIG_ENDIAN", "KEY_VALUE", "description", "filename")
        ti1 = TableItem("test1", 0, 32, "UINT", "BIG_ENDIAN")
        ti2 = TableItem("test2", 0, 32, "UINT", "BIG_ENDIAN")
        ti2.hidden = True
        ti3 = TableItem("test3", 0, 32, "UINT", "BIG_ENDIAN")
        t.append(ti1)
        self.assertEqual(t.num_rows, 1)
        t.append(ti2)
        self.assertEqual(t.num_rows, 1)  # Still 1 since ti2 is hidden
        t.append(ti3)
        self.assertEqual(t.num_rows, 2)

    def test_num_columns(self):
        """Test the number of columns property"""
        t = Table("table", "BIG_ENDIAN", "KEY_VALUE", "description", "filename")
        self.assertEqual(t.num_columns, 1)

        t = Table("table", "BIG_ENDIAN", "ROW_COLUMN", "description", "filename")
        self.assertEqual(t.num_columns, 0)

if __name__ == '__main__':
    unittest.main()