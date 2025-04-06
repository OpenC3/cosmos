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

from openc3.packets.parsers.packet_parser import PacketParser
from openc3.tools.table_manager.table import Table
from openc3.top_level import Logger

class TableParser(PacketParser):
    """Parses the TABLE keyword definition in table configuration files."""

    def __init__(self, parser):
        super().__init__(parser)
        self.usage = "TABLE <TABLE NAME> <ENDIANNESS: BIG_ENDIAN or LITTLE_ENDIAN> <TYPE: KEY_VALUE or ROW_COLUMN> <NUM ROWS IF TYPE = ROW_COLUMN> <DESCRIPTION (Optional)>"

    @classmethod
    def parse_table(cls, parser, tables, warnings):
        """
        Parse a table definition

        Args:
            parser: Configuration parser
            tables: Hash of the currently defined tables
            warnings: Any warning strings generated while parsing this command will be appended to this array

        Returns:
            The parsed table
        """
        parser_obj = cls(parser)
        parser_obj.verify_parameters()
        return parser_obj.create_table(tables, warnings)

    def verify_parameters(self):
        """Verify the correct number of arguments to the TABLE keyword"""
        self.usage = 'TABLE <TABLE NAME> <ENDIANNESS: BIG_ENDIAN/LITTLE_ENDIAN> <DISPLAY: KEY_VALUE/ROW_COLUMN> <ROW_COLUMN ROW COUNT> <DESCRIPTION (Optional)>'
        self.parser.verify_num_parameters(3, 5, self.usage)

    def create_table(self, tables, warnings):
        """
        Create a table from the parameters

        Args:
            tables: All tables defined in the configuration
            warnings: List of warnings to append to

        Returns:
            The created table
        """
        params = self.parser.parameters
        table_name = params[0].upper()
        endianness = params[1].upper()
        if endianness != "BIG_ENDIAN" and endianness != "LITTLE_ENDIAN":
            raise self.parser.error(
                f"Invalid endianness {params[1]}. Must be BIG_ENDIAN or LITTLE_ENDIAN.",
                self.usage,
            )

        type_param = params[2].upper()
        if type_param in ("KEY_VALUE", "ONE_DIMENSIONAL"):  # :ONE_DIMENSIONAL is deprecated
            self.parser.verify_num_parameters(3, 4, self.usage)
            description = params[3] if len(params) > 3 else ""
            num_rows = None
        elif type_param in ("ROW_COLUMN", "TWO_DIMENSIONAL"):  # :TWO_DIMENSIONAL is deprecated
            self.parser.verify_num_parameters(4, 5, self.usage)
            num_rows = int(params[3])
            description = params[4] if len(params) > 4 else ""
        else:
            raise self.parser.error(
                f"Invalid display type {params[2]}. Must be KEY_VALUE or ROW_COLUMN.",
                self.usage,
            )

        table = Table(table_name, endianness, type_param, description, self.parser.filename)
        if type_param in ("ROW_COLUMN", "TWO_DIMENSIONAL"):
            table.num_rows = num_rows

        return self.finish_create_table(table, tables, warnings)

    @classmethod
    def check_for_duplicate(cls, tables, table):
        """
        Check for duplicate table definition

        Args:
            tables: All tables defined in the configuration
            table: The table to check

        Returns:
            Warning message or None
        """
        msg = None
        if table.TARGET in tables and table.table_name in tables[table.TARGET]:
            msg = f"Table {table.table_name} redefined."
            Logger.warn(msg)
        return msg

    @classmethod
    def finish_create_table(cls, table, tables, warnings):
        """
        Finish table creation by checking for duplicates

        Args:
            table: The table to finish
            tables: All tables defined in the configuration
            warnings: List of warnings to append to

        Returns:
            The finished table
        """
        warning = cls.check_for_duplicate(tables, table)
        if warning:
            warnings.append(warning)
        return table