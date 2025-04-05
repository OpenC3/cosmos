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

from io import StringIO
from openc3.tools.table_manager.table_config import TableConfig
from openc3.utilities.string import simple_formatted

class TableManagerCore:
    """
    Provides the low level Table Manager methods which do not require a GUI.
    """

    class CoreError(Exception):
        """Generic error raised when a more specific error doesn't work"""
        pass

    class MismatchError(CoreError):
        """Raised when opening a file that is either larger or smaller than its definition"""
        pass

    @classmethod
    def binary(cls, binary, definition_filename, table_name):
        """
        Get the binary data for a specific table

        Args:
            binary: Binary data containing the table
            definition_filename: Table definition filename
            table_name: The specific table to return binary data for

        Returns:
            Table buffer
        """
        config = TableConfig.process_file(definition_filename)
        cls.load_binary(config, binary)
        return config.table(table_name).buffer

    @classmethod
    def definition(cls, definition_filename, table_name):
        """
        Get the definition for a specific table

        Args:
            definition_filename: Table definition filename
            table_name: The specific table to return the definition for

        Returns:
            Array containing [filename, contents]
        """
        config = TableConfig.process_file(definition_filename)
        return config.definition(table_name)  # This returns an array: [filename, contents]

    @classmethod
    def report(cls, binary, definition_filename, requested_table_name=None):
        """
        Create a text report of binary data for a given definition and optional table

        Args:
            binary: Binary data containing the table(s)
            definition_filename: Table definition filename
            requested_table_name: The specific table to return a report for (None = all tables)

        Returns:
            String report
        """
        report = StringIO()
        config = TableConfig.process_file(definition_filename)
        try:
            cls.load_binary(config, binary)
        except cls.CoreError as e:
            report.write(f"Error: {str(e)}\n")

        for table_name, table in config.tables.items():
            if requested_table_name and table_name != requested_table_name:
                continue
            items = table.sorted_items
            report.write(table.table_name + "\n")

            # Write the column headers
            if table.type == "ROW_COLUMN":
                columns = ['Item']

                # Remove the '0' from the 'itemname0'
                for x in range(table.num_columns):
                    columns.append(items[x].name[0:-1])
                report.write(", ".join(columns) + "\n")
            else:
                report.write("Label, Value\n")

            # Write the table item values
            for r in range(table.num_rows):
                if table.type == "ROW_COLUMN":
                    rowtext = f"{r + 1}"
                else:
                    rowtext = items[r].name

                report.write(f"{rowtext}, ")
                for c in range(table.num_columns):
                    if table.type == "ROW_COLUMN":
                        table_item = items[c + (r * table.num_columns)]
                    else:
                        table_item = items[r]
                    value = table.read(table_item.name, "FORMATTED")
                    if value.isascii():
                        report.write(f"{value}, ")
                    else:
                        report.write(f"{simple_formatted(value)}, ")
                report.write("\n")  # newline after each row
            report.write("\n")  # newline after each table

        return report.getvalue()

    @classmethod
    def generate(cls, definition_filename):
        """
        Generate binary data from a table definition file

        Args:
            definition_filename: Table definition filename

        Returns:
            Binary string representing the defined table(s)
        """
        config = TableConfig.process_file(definition_filename)
        binary = b''
        for _table_name, table in config.tables.items():
            table.restore_defaults()
            binary += table.buffer
        return binary

    @classmethod
    def save(cls, definition_filename, tables):
        """
        Update a table definition with table data and return binary data

        Args:
            definition_filename: Table definition filename
            tables: Hash of tables to save {'name' => name, 'rows' => array of rows}

        Returns:
            Binary data representing the defined table(s)
        """
        config = TableConfig.process_file(definition_filename)
        for table in tables:
            table_def = config.tables[table['name']]
            for row in table['rows']:
                for item in row:
                    # TODO: I don't know how the frontend could edit an item like this:
                    # item:{"name"=>"BINARY", "value"=>{"json_class"=>"String", "raw"=>[222, 173, 190, 239]} }
                    if isinstance(item['value'], dict):
                        continue
                    print("table_def:", table_def)
                    table_def.write(item['name'], item['value'])

        binary = b''
        for _table_name, table in config.tables.items():
            binary += table.buffer
        return binary

    @classmethod
    def build_json_hash(cls, binary, definition_filename):
        """
        Build JSON hash for the frontend to consume

        Args:
            binary: Binary data containing the table(s)
            definition_filename: Table definition filename

        Returns:
            Hash that can be converted to JSON
        """
        config = TableConfig.process_file(definition_filename)
        tables = []
        json_hash = {"tables": tables}
        try:
            cls.load_binary(config, binary)
        except cls.CoreError as e:
            json_hash['errors'] = str(e)

        for table_name, table in config.tables.items():
            tables.append({
                "name": table_name,
                "numRows": table.num_rows,
                "numColumns": table.num_columns,
                "headers": [],
                "rows": [],
            })

            col = 0
            row = 0
            for item in table.sorted_items:
                if item.hidden:
                    continue

                if table.num_columns == 1:
                    if row == 0:
                        tables[-1]["headers"] = ["INDEX", "NAME", "VALUE"]

                    tables[-1]["rows"].append([
                        {
                            "index": row + 1,
                            "name": item.name,
                            "value": table.read(item.name, "FORMATTED"),
                            "states": item.states,
                            "editable": item.editable,
                        },
                    ])
                else:
                    if row == 0 and col == 0:
                        tables[-1]["headers"].append("INDEX")

                    if row == 0:
                        tables[-1]["headers"].append(item.name[0:-1])

                    if col == 0:
                        # Each row is an array of items
                        tables[-1]["rows"].append([])

                    tables[-1]["rows"][row].append({
                        "index": row + 1,
                        "name": item.name,
                        "value": table.read(item.name, "FORMATTED"),
                        "states": item.states,
                        "editable": item.editable,
                    })

                col += 1
                if col == table.num_columns:
                    col = 0
                    row += 1

        return json_hash

    @classmethod
    def load_binary(cls, config, data):
        """
        Load binary data into the table

        Args:
            config: TableConfig instance
            data: Binary data containing the table(s)

        Raises:
            MismatchError if the data doesn't match the definition
        """
        binary_data_index = 0
        total_table_length = 0
        for _table_name, table in config.tables.items():
            total_table_length += table.length

        for _table_name, table in config.tables.items():
            if binary_data_index + table.length > len(data):
                table.buffer = data[binary_data_index:]
                raise cls.MismatchError(
                    f"Binary size of {len(data)} not large enough to fully represent table definition of length {total_table_length}. "
                    f"The remaining table definition (starting with byte {len(data) - binary_data_index} in {table.table_name}) will be filled with 0."
                )

            table.buffer = data[binary_data_index:binary_data_index + table.length]
            binary_data_index += table.length

        if binary_data_index < len(data):
            raise cls.MismatchError(
                f"Binary size of {len(data)} larger than table definition of length {total_table_length}. "
                f"Discarding the remaining {len(data) - binary_data_index} bytes."
            )