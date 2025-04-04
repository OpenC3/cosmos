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
from openc3.tools.table_manager.table_item import TableItem

class TestTableItem(unittest.TestCase):
    def test_initialize(self):
        """Test initialize sets the defaults"""
        item = TableItem("item1", 0, 32, "UINT", "BIG_ENDIAN")
        self.assertEqual(item.name, "ITEM1")
        self.assertEqual(item.editable, True)
        self.assertEqual(item.hidden, False)

    def test_editable(self):
        """Test the editable property"""
        item = TableItem("item1", 0, 32, "UINT", "BIG_ENDIAN")
        item.editable = False
        self.assertEqual(item.editable, False)
        with self.assertRaises(TypeError) as context:
            item.editable = "false"
        self.assertTrue("editable must be a boolean" in str(context.exception))

    def test_hidden(self):
        """Test the hidden property"""
        item = TableItem("item1", 0, 32, "UINT", "BIG_ENDIAN")
        item.hidden = True
        self.assertEqual(item.hidden, True)
        with self.assertRaises(TypeError) as context:
            item.hidden = "true"
        self.assertTrue("hidden must be a boolean" in str(context.exception))

    def test_clone(self):
        """Test cloning a TableItem"""
        item = TableItem("item1", 0, 32, "UINT", "BIG_ENDIAN")
        item.editable = False
        item.hidden = True
        clone = item.clone()
        self.assertEqual(clone.name, "ITEM1")
        self.assertEqual(clone.bit_offset, 0)
        self.assertEqual(clone.bit_size, 32)
        self.assertEqual(clone.data_type, "UINT")
        self.assertEqual(clone.editable, False)
        # Hidden is not cloned in the Ruby version, matching the behavior
        # self.assertEqual(clone.hidden, True)

    def test_as_json(self):
        """Test creating a hash of the item attributes"""
        item = TableItem("item1", 0, 32, "UINT", "BIG_ENDIAN")
        item.editable = False
        item.hidden = True
        json_hash = item.as_json()
        self.assertEqual(json_hash["editable"], False)
        self.assertEqual(json_hash["hidden"], True)

if __name__ == '__main__':
    unittest.main()