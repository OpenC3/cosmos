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
from openc3.config.config_parser import ConfigParser
from openc3.packets.packet_config import PacketConfig
from openc3.tools.table_manager.table import Table
from openc3.tools.table_manager.table_parser import TableParser
from openc3.tools.table_manager.table_item_parser import TableItemParser
from openc3.conversions.generic_conversion import GenericConversion

class TableConfig(PacketConfig):
    """
    Processes the Table Manager configuration files which define tables. Since
    this class inherits from PacketConfig it only needs to implement Table
    Manager specific keywords. All tables are accessed through the table
    and tables methods.
    """

    @classmethod
    def process_file(cls, filename):
        """
        Process a file and create a TableConfig object

        Args:
            filename: The configuration file name

        Returns:
            New TableConfig object
        """
        instance = cls()
        instance._process_file(filename)
        return instance

    def __init__(self):
        """Create the table configuration"""
        super().__init__()
        # Override commands with the Table::TARGET name to store tables
        self.commands[Table.TARGET] = {}
        self.definitions = {}
        self.last_config = []  # Stores array of [filename, contents]

    @property
    def tables(self):
        """
        All tables defined in the configuration file

        Returns:
            Dict of all tables
        """
        # The tests expect tables to contain a direct reference to the command entries
        # with the TEST key (not nested under TABLE)
        return self.commands[Table.TARGET]

    def definition(self, table_name):
        """
        Get the table definition

        Args:
            table_name: Name of the table

        Returns:
            Table definition for the specific table
        """
        return self.definitions[table_name.upper()]

    @property
    def table_names(self):
        """
        Get all the table names

        Returns:
            List of all the table names
        """
        return list(self.commands[Table.TARGET].keys())

    def table(self, table_name):
        """
        Get a specific table

        Args:
            table_name: Name of the table

        Returns:
            The table object
        """
        return self.tables[table_name.upper()]

    def _process_file(self, filename):
        """
        Processes a OpenC3 table configuration file and uses the keywords to build up
        knowledge of the tables.

        Args:
            filename: The name of the configuration file
        """
        # Partial files are included into another file and thus aren't directly processed
        if os.path.basename(filename)[0] == '_':  # Partials start with underscore
            return

        self.filename = filename
        with open(filename, 'r') as file:
            self.last_config = [os.path.basename(filename), file.read()]

        self.converted_type = None
        self.converted_bit_size = None
        self.proc_text = ''
        self.building_generic_conversion = False
        self.defaults = []

        parser = ConfigParser("https://openc3.com/docs/tools/#table-manager-configuration-openc3--39")

        for keyword, params in parser.parse_file(filename):
            if self.building_generic_conversion:
                if keyword in ('GENERIC_READ_CONVERSION_END', 'GENERIC_WRITE_CONVERSION_END'):
                    parser.verify_num_parameters(0, 0, keyword)
                    if 'READ' in keyword:
                        self.current_item.read_conversion = GenericConversion(
                            self.proc_text,
                            self.converted_type,
                            self.converted_bit_size
                        )
                    if 'WRITE' in keyword:
                        self.current_item.write_conversion = GenericConversion(
                            self.proc_text,
                            self.converted_type,
                            self.converted_bit_size
                        )
                    self.building_generic_conversion = False
                else:
                    # Add the current config.line to the conversion being built
                    self.proc_text += parser.line + "\n"
            else:
                # not building generic conversion
                if keyword == 'TABLEFILE':
                    usage = f"{keyword} <File name>"
                    parser.verify_num_parameters(1, 1, usage)
                    table_filename = os.path.join(os.path.dirname(filename), params[0])
                    if not os.path.exists(table_filename):
                        raise parser.error(
                            f"Table file {table_filename} not found",
                            usage,
                        )
                    self._process_file(table_filename)

                elif keyword == 'TABLE':
                    self.finish_packet()
                    self.current_packet = TableParser.parse_table(parser, self.commands, self.warnings)
                    self.definitions[self.current_packet.packet_name] = self.last_config
                    self.current_cmd_or_tlm = self.COMMAND
                    self.default_index = 0

                # Select an existing table for editing
                elif keyword == 'SELECT_TABLE':
                    usage = f"{keyword} <TABLE NAME>"
                    self.finish_packet()
                    parser.verify_num_parameters(1, 1, usage)
                    table_name = params[0].upper()
                    self.current_packet = self.table(table_name)
                    if not self.current_packet:
                        raise parser.error(f"Table {table_name} not found", usage)

                # All the following keywords must have a current packet defined
                elif keyword in ('SELECT_PARAMETER', 'PARAMETER', 'ID_PARAMETER',
                            'ARRAY_PARAMETER', 'APPEND_PARAMETER', 'APPEND_ID_PARAMETER',
                            'APPEND_ARRAY_PARAMETER', 'ALLOW_SHORT', 'HAZARDOUS',
                            'PROCESSOR', 'META', 'DISABLE_MESSAGES', 'DISABLED'):
                    if not self.current_packet:
                        raise parser.error(f"No current packet for {keyword}")
                    self.process_current_packet(parser, keyword, params)

                # All the following keywords must have a current item defined
                elif keyword in ('STATE', 'READ_CONVERSION', 'WRITE_CONVERSION',
                            'POLY_READ_CONVERSION', 'POLY_WRITE_CONVERSION',
                            'SEG_POLY_READ_CONVERSION', 'SEG_POLY_WRITE_CONVERSION',
                            'GENERIC_READ_CONVERSION_START',
                            'GENERIC_WRITE_CONVERSION_START', 'REQUIRED', 'LIMITS',
                            'LIMITS_RESPONSE', 'UNITS', 'FORMAT_STRING', 'DESCRIPTION',
                            'HIDDEN', 'MINIMUM_VALUE', 'MAXIMUM_VALUE', 'DEFAULT_VALUE',
                            'OVERFLOW', 'UNEDITABLE'):
                    if not self.current_item:
                        raise parser.error(f"No current item for {keyword}")
                    self.process_current_item(parser, keyword, params)

                elif keyword == 'DEFAULT':
                    if len(params) != len(self.current_packet.sorted_items):
                        raise parser.error(f"DEFAULT {' '.join(params)} length of {len(params)} doesn't match item length of {len(self.current_packet.sorted_items)}")
                    self.defaults.extend(params)

                else:
                    # blank config.lines will have a nil keyword and should not raise an exception
                    if keyword:  # None is falsy in Python
                        raise parser.error(f"Unknown keyword '{keyword}'")

        # Complete the last defined packet
        self.finish_packet()

    def process_current_packet(self, parser, keyword, params):
        """
        Process the current packet

        Args:
            parser: Configuration parser
            keyword: The keyword being processed
            params: Parameters for the keyword
        """
        try:
            super().process_current_packet(parser, keyword, params)
        except Exception as err:
            if "not found" in str(err):
                raise parser.error(
                    f"{params[0]} not found in table {self.current_packet.table_name}",
                    'SELECT_PARAMETER <PARAMETER NAME>',
                )
            else:
                raise

    def process_current_item(self, parser, keyword, params):
        """
        Overridden method to handle the unique table item parameters: UNEDITABLE
        and HIDDEN.

        Args:
            parser: Configuration parser
            keyword: The keyword being processed
            params: Parameters for the keyword
        """
        super().process_current_item(parser, keyword, params)
        if keyword == 'UNEDITABLE':
            usage = f"{keyword}"
            parser.verify_num_parameters(0, 0, usage)
            self.current_item.editable = False
        elif keyword == 'HIDDEN':
            usage = f"{keyword}"
            parser.verify_num_parameters(0, 0, usage)
            self.current_item.hidden = True

    def start_item(self, parser):
        """
        Start a new table item

        Args:
            parser: Configuration parser
        """
        self.finish_item()
        self.current_item = TableItemParser.parse(parser, self.current_packet, self.warnings)

    def finish_packet(self):
        """
        Finish the packet definition

        If the table is ROW_COLUMN all currently defined items are
        duplicated until the specified number of rows are created.
        """
        if self.current_packet:
            warnings = self.current_packet.check_bit_offsets()
            if len(warnings) > 0:
                raise Exception(f"Overlapping items not allowed in tables.\n{warnings}")

            if self.current_packet.type == "ROW_COLUMN":
                items = self.current_packet.sorted_items.copy()
                self.current_packet.num_columns = len(items)  # Set the number of columns
                for row in range(self.current_packet.num_rows - 1):
                    for item in items:
                        new_item = item.clone()
                        new_item.name = f"{new_item.name}{row + 1}"
                        self.current_packet.append(new_item)

            if self.defaults:
                for index, item in enumerate(self.current_packet.sorted_items):
                    if item.data_type in ("INT", "UINT"):
                        try:
                            # Integer handles hex strings, e.g. 0xDEADBEEF
                            item.default = int(self.defaults[index], 0)
                        except ValueError:
                            value = item.states.get(self.defaults[index])
                            if value is not None:
                                item.default = value
                            else:
                                raise Exception(f"Unknown DEFAULT {self.defaults[index]} for item {item.name}. Valid states are {', '.join(item.states.keys())}.")
                    elif item.data_type == "FLOAT":
                        item.default = float(self.defaults[index])
                    elif item.data_type in ("STRING", "BLOCK"):
                        item.default = self.defaults[index]

            # Reset defaults after processing them
            self.defaults = []

        super().finish_packet()
