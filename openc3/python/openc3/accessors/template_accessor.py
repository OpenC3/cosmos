# Copyright 2024 OpenC3, Inc.
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

from openc3.accessors.accessor import Accessor
import re


class TemplateAccessor(Accessor):
    def __init__(self, packet, left_char="<", right_char=">"):
        super().__init__(packet)
        self.left_char = left_char
        self.right_char = right_char
        self.configured = False

    def configure(self):
        if self.configured:
            return

        escaped_left_char = self.left_char
        if self.left_char == "(":
            escaped_left_char = f"\\{self.left_char}"
        escaped_right_char = self.right_char
        if self.right_char == ")":
            escaped_right_char = f"\\{self.right_char}"

        # Convert the template into a Regexp for reading each item
        template = self.packet.template[:].decode()
        template_items = re.compile(f"{escaped_left_char}.*?{escaped_right_char}", re.X).findall(template)
        escaped_read_template = re.escape(template)

        self.item_keys = []
        for item in template_items:
            self.item_keys.append(item[1:-1])
            # If they're using parens we have to escape them
            # since we're working with the already escaped template
            if self.left_char == "(":
                item = f"\\({item[1:]}"
            if self.right_char == ")":
                item = f"{item[0:-1]}\\)"
            escaped_read_template = escaped_read_template.replace(item, "(.*)")
        self.read_regexp = re.compile(escaped_read_template, re.X)
        self.configured = True

    def read_item(self, item, buffer):
        if item.data_type == "DERIVED":
            return None
        self.configure()

        # Scan the response for all the variables in brackets <VARIABLE>
        values = self.read_regexp.match(buffer.decode())
        if values is not None:
            values = values.groups()
        if values is None or (len(values) != len(self.item_keys)):
            num_items = 0
            if values is not None:
                num_items = len(values)
            raise RuntimeError(
                f"Unexpected number of items found in buffer: {num_items}, Expected: {len(self.item_keys)}"
            )
        else:
            for i, value in enumerate(values):
                item_key = self.item_keys[i]
                if item_key == item.key:
                    return Accessor.convert_to_type(value, item)

        raise RuntimeError(f"Response does not include key {item.key}: {buffer}")

    def read_items(self, items, buffer):
        result = {}
        self.configure()

        # Scan the response for all the variables in brackets <VARIABLE>
        values = self.read_regexp.match(buffer.decode())
        if values is not None:
            values = values.groups()
        if values is None or (len(values) != len(self.item_keys)):
            num_items = 0
            if values is not None:
                num_items = len(values)
            raise RuntimeError(
                f"Unexpected number of items found in buffer: {num_items}, Expected: {len(self.item_keys)}"
            )
        else:
            for item in items:
                if item.data_type == "DERIVED":
                    result[item.name] = None
                    continue
                try:
                    index = self.item_keys.index(item.key)
                    result[item.name] = Accessor.convert_to_type(values[index], item)
                except ValueError:
                    raise RuntimeError(f"Unknown item with key {item.key} requested")

        return result

    def write_item(self, item, value, buffer):
        if item.data_type == "DERIVED":
            return None
        self.configure()

        updated_buffer = buffer.decode().replace(f"{self.left_char}{item.key}{self.right_char}", str(value)).encode()

        if buffer == updated_buffer:
            raise RuntimeError(f"Key {item.key} not found in template")
        buffer[0:] = updated_buffer
        return value

    def write_items(self, items, values, buffer):
        self.configure()
        for index, item in enumerate(items):
            if item.data_type == "DERIVED":
                continue
            updated_buffer = (
                buffer.decode().replace(f"{self.left_char}{item.key}{self.right_char}", str(values[index])).encode()
            )

            if buffer == updated_buffer:
                raise RuntimeError(f"Key {item.key} not found in template")
            buffer[0:] = updated_buffer
        return values

    # If this is set it will enforce that buffer data is encoded
    # in a specific encoding
    def enforce_encoding(self):
        return None

    # This affects whether the Packet class enforces the buffer
    # length at all.  Set to false to remove any correlation between
    # buffer length and defined sizes of items in COSMOS
    def enforce_length(self):
        return False

    # This sets the short_buffer_allowed flag in the Packet class
    # which allows packets that have a buffer shorter than the defined size.
    # Note that the buffer is still resized to the defined length
    def enforce_short_buffer_allowed(self):
        return True

    # If this is true it will enforce that COSMOS DERIVED items must have a
    # write_conversion to be written
    def enforce_derived_write_conversion(self, _item):
        return True
