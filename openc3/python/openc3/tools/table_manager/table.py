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

from openc3.packets.packet import Packet
from openc3.tools.table_manager.table_item import TableItem

class Table(Packet):
    """
    Table extends Packet by adding more attributes relative to
    displaying binary data in a gui.
    """

    # Define the target for tables as 'TABLE' since there is no target
    TARGET = 'TABLE'

    def __init__(self, name, endianness, type_param, description, filename):
        """
        Constructor for a TableDefinition

        Args:
            name: Name of the table
            endianness: Byte order of the table (BIG_ENDIAN or LITTLE_ENDIAN)
            type_param: Either :KEY_VALUE or :ROW_COLUMN
            description: Description of the table
            filename: File which contains the table definition
        """
        super().__init__(self.TARGET, name, endianness, description, b'', item_class=TableItem)
        # ONE_DIMENSIONAL and TWO_DIMENSIONAL are deprecated so translate
        if type_param == "ONE_DIMENSIONAL":
            type_param = "KEY_VALUE"
        if type_param == "TWO_DIMENSIONAL":
            type_param = "ROW_COLUMN"

        if type_param != "KEY_VALUE" and type_param != "ROW_COLUMN":
            raise ValueError(f"Invalid type '{type_param}' for table '{name}'. Must be KEY_VALUE or ROW_COLUMN")

        self.type = type_param
        self.filename = filename
        self._num_rows = 0
        self._num_columns = 1 if self.type == "KEY_VALUE" else 0

    @property
    def table_name(self):
        """Table name"""
        return self.packet_name
        
    @property
    def endianness(self):
        """Get the table's endianness"""
        return self.default_endianness
        
    @property
    def length(self):
        """Returns the length of the table in bytes"""
        return self.defined_length

    @property
    def num_columns(self):
        """Number of columns in the table"""
        return self._num_columns

    @num_columns.setter
    def num_columns(self, value):
        """Set number of columns in the table"""
        self._num_columns = value

    @property
    def num_rows(self):
        """
        Get the number of rows in the table

        Returns:
            Number of rows in the table
        """
        if self.type == "KEY_VALUE":
            return len([item for item in self.sorted_items if not item.hidden])
        else:  # ROW_COLUMN
            return self._num_rows

    @num_rows.setter
    def num_rows(self, num_rows):
        """
        Set the number of rows in a ROW_COLUMN table

        Args:
            num_rows: Number of rows

        Raises:
            ValueError if table type is KEY_VALUE
        """
        if self.type == "KEY_VALUE":
            raise ValueError("Rows are fixed in a KEY_VALUE table")
        elif self.type == "ROW_COLUMN":
            self._num_rows = num_rows