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

from openc3.packets.packet_config import PacketConfig
from openc3.packets.parsers.packet_item_parser import PacketItemParser
from openc3.tools.table_manager.table_item import TableItem
from openc3.utilities.logger import Logger

class TableItemParser(PacketItemParser):
    """
    This class parses the PARAMETER, APPEND_PARAMETER, etc. keywords and creates the
    associated TableItem objects in the specified table.
    """

    @classmethod
    def parse(cls, parser, table, warnings):
        """
        Create a new TableItemParser and parse the packet item

        Args:
            parser: A ConfigParser
            table: The table the item should be added to
            warnings: An array of warning strings

        Returns:
            The created TableItem
        """
        parser = cls(parser, warnings)
        parser.verify_parameters(PacketConfig.COMMAND)
        return parser.create_table_item(table)

    def create_table_item(self, table):
        """
        Parse the next table item

        Returns:
            A TableItem
        """
        try:
            item_name = self.parser.parameters[0].upper()
            if item_name in table.items:
                msg = f"Table {table.table_name} item {item_name} redefined."
                Logger.warn(msg)
                self.warnings.append(msg)

            if table.type == 'ROW_COLUMN':
                item_name = f"{item_name}0"
                table.num_columns += 1

            item = TableItem(
                item_name,
                self._get_bit_offset(),
                self._get_bit_size(),
                self._get_data_type(),
                self._get_endianness(table),
                self._get_array_size(),
                "ERROR",  # overflow
            )

            item.minimum = self._get_minimum()
            item.maximum = self._get_maximum()
            item.default = self._get_default()
            item.id_value = self._get_id_value(item)
            item.description = self._get_description()

            if self._append():
                item = table.append(item)
            else:
                item = table.define(item)
            return item
        except Exception as error:
            raise self.parser.error(error, self.usage)