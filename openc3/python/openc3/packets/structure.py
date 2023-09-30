#!/usr/bin/env python3

# Copyright 2023 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

import copy
import threading
from contextlib import contextmanager
from openc3.accessors.binary_accessor import BinaryAccessor
from openc3.packets.structure_item import StructureItem
from openc3.utilities.string import formatted


class Structure:
    """Maintains knowledge of a raw binary structure. Uses structure_item to
    create individual structure items which are read and written by
    binary_accessor."""

    # String providing a single 0 byte
    ZERO_STRING = b"\00"

    def __init__(
        self,
        default_endianness=BinaryAccessor.HOST_ENDIANNESS,
        buffer=None,
        item_class=StructureItem,
    ):
        if (default_endianness == "BIG_ENDIAN") or (
            default_endianness == "LITTLE_ENDIAN"
        ):
            self.default_endianness = default_endianness
            if buffer is not None and not isinstance(
                buffer, (bytes, bytearray)
            ):  # type(buffer) != str:
                raise TypeError(
                    f"wrong argument type {buffer.__class__.__name__} (expected bytes)"
                )
            if buffer is None:
                self._buffer = None
            else:
                self._buffer = bytearray(buffer)  # TODO: Do we need to force encoding?
            self.item_class = item_class
            self.items = {}
            self.sorted_items = []
            self.defined_length = 0
            self.defined_length_bits = 0
            self.pos_bit_size = 0
            self.neg_bit_size = 0
            self.fixed_size = True
            self.short_buffer_allowed = False
            self.mutex = None
            self.accessor = BinaryAccessor()
        else:
            raise AttributeError(
                f"Unknown endianness '{default_endianness}', must be 'BIG_ENDIAN' or 'LITTLE_ENDIAN'"
            )

    # Read an item in the structure
    #
    # self.param item [StructureItem] Instance of StructureItem or one of its subclasses
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param buffer [String] The binary buffer to read the item from
    # self.return Value based on the item definition. This could be a string, integer,
    #   float, or array of values.
    def read_item(self, item, value_type="RAW", buffer=None):
        if not buffer:
            buffer = self._buffer
        if not buffer:
            buffer = self.allocate_buffer_if_needed()
        return self.accessor.read_item(item, buffer)

    # Get the length of the buffer used by the structure
    #
    # self.return [Integer] Size of the buffer in bytes
    def length(self):
        self.allocate_buffer_if_needed()
        return len(self._buffer)

    # Resize the buffer at least the defined length of the structure
    def resize_buffer(self):
        if self._buffer:
            # Extend data size
            if len(self._buffer) < self.defined_length:
                self._buffer += Structure.ZERO_STRING * (
                    self.defined_length - len(self._buffer)
                )
        else:
            self.allocate_buffer_if_needed()

    @property
    def accessor(self):
        return self.__accessor

    # Configure the accessor for this packet
    #
    # self.param accessor [Accessor] The class to use as an accessor
    @accessor.setter
    def accessor(self, accessor):
        self.__accessor = accessor
        # isinstance can fail if the class is reloaded because the class becomes a new class
        # so direcly check the class name which is basically equivalent
        if self.__accessor.enforce_short_buffer_allowed():
            self.short_buffer_allowed = True

    # Read a list of items in the structure
    #
    # self.param items [StructureItem] Array of StructureItem or one of its subclasses
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param buffer [String] The binary buffer to read the item from
    # self.return Hash of read names and values
    def read_items(self, items, value_type="RAW", buffer=None):
        if not buffer:
            buffer = self._buffer
        if not buffer:
            buffer = self.allocate_buffer_if_needed()
        return self.accessor.read_items(items, buffer)

    # Allocate a buffer if not available
    def allocate_buffer_if_needed(self):
        if not self._buffer:
            self._buffer = bytearray(Structure.ZERO_STRING * self.defined_length)
        return self._buffer

    # Indicates if any items have been defined for this structure
    # self.return [TrueClass or FalseClass]
    def defined(self):
        return len(self.sorted_items) > 0

    # Rename an existing item
    #
    # self.param item_name [String] Name of the currently defined item
    # self.param new_item_name [String] New name for the item
    def rename_item(self, item_name, new_item_name):
        item = self.get_item(item_name)
        item.name = new_item_name
        self.items.pop(item_name)
        self.items[new_item_name] = item
        # Since self.sorted_items contains the actual item reference it is
        # updated when we set the item.name
        return item

    # Define an item in the structure. This creates a new instance of the
    # item_class as given in the constructor and adds it to the items hash. It
    # also resizes the buffer to accomodate the new item.
    #
    # self.param name [String] Name of the item. Used by the items hash to retrieve
    #   the item.
    # self.param bit_offset [Integer] Bit offset of the item in the raw buffer
    # self.param bit_size [Integer] Bit size of the item in the raw buffer
    # self.param data_type [Symbol] Type of data contained by the item. This is
    #   dependant on the item_class but by default see StructureItem.
    # self.param array_size [Integer] Set to a non None value if the item is to
    #   represented as an array.
    # self.param endianness [Symbol] Endianness of this item. By default the
    #   endianness as set in the constructure is used.
    # self.param overflow [Symbol] How to handle value overflows. This is
    #   dependant on the item_class but by default see StructureItem.
    # self.return [StrutureItem] The struture item defined
    def define_item(
        self,
        name,
        bit_offset,
        bit_size,
        data_type,
        array_size=None,
        endianness=None,
        overflow="ERROR",
    ):
        if not endianness:
            endianness = self.default_endianness
        # Create the item
        item = self.item_class(
            name, bit_offset, bit_size, data_type, endianness, array_size, overflow
        )
        return self.define(item)

    # Adds the given item to the items hash. It also resizes the buffer to
    # accomodate the new item.
    #
    # self.param item [StructureItem] The structure item to add
    # self.return [StrutureItem] The struture item defined
    def define(self, item):
        # Handle Overwriting Existing Item
        if self.items.get(item.name):
            item_index = None
            for index, sorted_item in enumerate(self.sorted_items):
                if sorted_item.name == item.name:
                    item_index = index
                    break
            if item_index < len(self.sorted_items):
                self.sorted_items.pop(item_index)

        # Add to Sorted Items
        if len(self.sorted_items) != 0:
            last_item = self.sorted_items[-1]
            self.sorted_items.append(item)
            # If the current item or last item have a negative offset then we have
            # to re-sort. We also re-sort if the current item is less than the last
            # item because we are inserting.
            if (
                last_item.bit_offset <= 0
                or item.bit_offset <= 0
                or item.bit_offset < last_item.bit_offset
            ):
                self.sorted_items.sort()
        else:
            self.sorted_items.append(item)

        # Add to the overall hash of defined items
        self.items[item.name] = item
        # Update fixed size knowledge
        if (item.data_type != "DERIVED" and item.bit_size <= 0) or (
            item.array_size and item.array_size <= 0
        ):
            self.fixed_size = False

        # Recalculate the overall defined length of the structure
        update_needed = False
        if item.bit_offset >= 0:
            if item.bit_size > 0:
                if item.array_size:
                    if item.array_size >= 0:
                        item_defined_length_bits = item.bit_offset + item.array_size
                    else:
                        item_defined_length_bits = item.bit_offset
                else:
                    item_defined_length_bits = item.bit_offset + item.bit_size

                if item_defined_length_bits > self.pos_bit_size:
                    self.pos_bit_size = item_defined_length_bits
                    update_needed = True

            elif item.bit_offset > self.pos_bit_size:
                self.pos_bit_size = item.bit_offset
                update_needed = True

        else:
            if abs(item.bit_offset) > self.neg_bit_size:
                self.neg_bit_size = abs(item.bit_offset)
                update_needed = True

        if update_needed:
            self.defined_length_bits = self.pos_bit_size + self.neg_bit_size
            self.defined_length = int(self.defined_length_bits / 8)
            if self.defined_length_bits % 8 != 0:
                self.defined_length += 1

        # Resize the buffer if necessary
        if self.buffer:
            self.resize_buffer()
        return item

    # Define an item at the end of the structure. This creates a new instance of the
    # item_class as given in the constructor and adds it to the items hash. It
    # also resizes the buffer to accomodate the new item.
    #
    # self.param name (see #define_item)
    # self.param bit_size (see #define_item)
    # self.param data_type (see #define_item)
    # self.param array_size (see #define_item)
    # self.param endianness (see #define_item)
    # self.param overflow (see #define_item)
    # self.return (see #define_item)
    def append_item(
        self,
        name,
        bit_size,
        data_type,
        array_size=None,
        endianness=None,
        overflow="ERROR",
    ):
        if not endianness:
            endianness = self.default_endianness
        if not self.fixed_size:
            raise AttributeError("Can't append an item after a variably sized item")
        if data_type == "DERIVED":
            return self.define_item(
                name, 0, bit_size, data_type, array_size, endianness, overflow
            )
        else:
            return self.define_item(
                name,
                self.defined_length_bits,
                bit_size,
                data_type,
                array_size,
                endianness,
                overflow,
            )

    # Adds an item at the  of the structure. It adds the item to the items
    # hash and resizes the buffer to accomodate the new item.
    #
    # self.param item (see #define)
    # self.return (see #define)
    def append(self, item):
        if not self.fixed_size:
            raise AttributeError("Can't append an item after a variably sized item")

        if item.data_type == "DERIVED":
            item.bit_offset = 0
        else:
            item.bit_offset = self.defined_length_bits

        return self.define(item)

    # self.param name [String] Name of the item to look up in the items Hash
    # self.return [StructureItem] StructureItem or one of its subclasses
    def get_item(self, name):
        item = self.items.get(name.upper())
        if not item:
            raise AttributeError(f"Unknown item: {name}")
        return item

    # self.param item [#name] Instance of StructureItem or one of its subclasses.
    #   The name method will be used to look up the item and set it to the new instance.
    def set_item(self, item):
        if self.items.get(item.name):
            self.items[item.name] = item
        else:
            raise AttributeError(
                f"Unknown item: {item.name} - Ensure item name is uppercase"
            )

    # self.param name [String] Name of the item to delete in the items Hash
    def delete_item(self, name):
        item = self.items[name.upper()]
        if not item:
            raise AttributeError(f"Unknown item: {name}")

        # Find the item to delete in the sorted_items array
        item_index = None
        for index, sorted_item in enumerate(self.sorted_items):
            if sorted_item.name == item.name:
                item_index = index
                break

        self.sorted_items.pop(item_index)
        self.items.pop(name.upper())

    # Write a value to the buffer based on the item definition
    #
    # self.param item [StructureItem] Instance of StructureItem or one of its subclasses
    # self.param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param buffer [String] The binary buffer to write the value to
    def write_item(self, item, value, value_type="RAW", buffer=None):
        if not buffer:
            buffer = self._buffer
        if not buffer:
            buffer = self.allocate_buffer_if_needed()
        self.accessor.write_item(item, value, buffer)

    # Write values to the buffer based on the item definitions
    #
    # self.param items [StructureItem] Array of StructureItem or one of its subclasses
    # self.param value [Object] Array of values based on the item definitions.
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param buffer [String] The binary buffer to write the values to
    def write_items(self, items, values, value_type="RAW", buffer=None):
        if not buffer:
            buffer = self._buffer
        if not buffer:
            buffer = self.allocate_buffer_if_needed()
        self.accessor.write_items(items, values, buffer)

    # Read an item in the structure by name
    #
    # self.param name [String] Name of an item to read
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param buffer [String] The binary buffer to read the item from
    # self.return Value based on the item definition. This could be an integer,
    #   float, or array of values.
    def read(self, name, value_type="RAW", buffer=None):
        if not buffer:
            buffer = self._buffer
        return self.read_item(self.get_item(name), value_type, buffer)

    # Write an item in the structure by name
    #
    # self.param name [Object] Name of the item to write
    # self.param value [Object] Value based on the item definition. This could be
    #   a string, integer, float, or array of values.
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param buffer [String] The binary buffer to write the value to
    def write(self, name, value, value_type="RAW", buffer=None):
        if not buffer:
            buffer = self._buffer
        self.write_item(self.get_item(name), value, value_type, buffer)

    # Read all items in the structure into an array of arrays
    #   [[item name, item value], ...]
    #
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param buffer [String] The binary buffer to write the value to
    # self.param top [Boolean] Indicates if this is a top level call for the mutex
    # self.return [Array<Array>] Array of two element arrays containing the item
    #   name as element 0 and item value as element 1.
    def read_all(self, value_type="RAW", buffer=None, top=True):
        if not buffer:
            buffer = self._buffer
        item_array = []
        with self.synchronize_allow_reads(top):
            for item in self.sorted_items:
                item_array.append([item.name, self.read_item(item, value_type, buffer)])
        return item_array

    # Create a string that shows the name and value of each item in the structure
    #
    # self.param value_type [Symbol] Not used. Subclasses should overload this
    #   parameter to check whether to perform conversions on the item.
    # self.param indent [Integer] Amount to indent before printing the item name
    # self.param buffer [String] The binary buffer to write the value to
    # self.param ignored [Array<String>] List of items to ignore when building the string
    # self.return [String] String formatted with all the item names and values
    def formatted(self, value_type="RAW", indent=0, buffer=None, ignored=None):
        if not buffer:
            buffer = self._buffer
        indent_string = " " * indent
        string = ""
        with self.synchronize_allow_reads(True):
            for item in self.sorted_items:
                if ignored and item.name in ignored:
                    continue

                if (item.data_type != "BLOCK") or (
                    item.data_type == "BLOCK"
                    and value_type != "RAW"
                    and hasattr(item, "read_conversion")
                ):
                    string += f"{indent_string}{item.name}: {self.read_item(item, value_type, buffer)}\n"
                else:
                    value = self.read_item(item, value_type, buffer)
                    if isinstance(value, (str, bytes, bytearray)):
                        string += f"{indent_string}{item.name}:\n"
                        string += formatted(value, 1, 16, " ", indent + 2)
                    else:
                        string += f"{indent_string}{item.name}: {value}\n"

        return string

    # Get the buffer used by the structure. The current buffer is copied and
    # thus modifications to the returned buffer will have no effect on the
    # structure items.
    #
    # self.param copy [TrueClass/FalseClass] Whether to copy the buffer
    # self.return [String] Data buffer backing the structure
    @property
    def buffer(self):
        return self.allocate_buffer_if_needed()[:]

    def buffer_no_copy(self):
        return self.allocate_buffer_if_needed()

    # Set the buffer to be used by the structure. The buffer is copied and thus
    # further modifications to the buffer have no effect on the structure
    # items.
    #
    # self.param buffer [String] Buffer of data to back the stucture items
    @buffer.setter
    def buffer(self, buffer):
        with self.synchronize():
            self.internal_buffer_equals(buffer)

    # Make a light weight clone of this structure. This only creates a new buffer
    # of data. The defined structure items are the same.
    #
    # self.return [Structure] A copy of the current structure with a new underlying
    #   buffer of data
    def clone(self):
        struct = copy.copy(self)
        struct._buffer = self.buffer  # Makes a copy
        struct.accessor.packet = struct
        return struct

    # Enable the ability to read and write item values as if they were methods
    # to the class
    def __getattr__(self, func):
        # Prevent recursion in deepcopy
        if func in ["__deepcopy__", "__getstate__", "__setstate__"]:
            raise AttributeError()
        if self.items.get(func.upper()):
            return self.read(func.upper())
        else:
            raise AttributeError(f"Unknown item: {func}")

    # TODO:
    # def __setattr__(self, func, value):
    #     return setattr(self, func, value)

    MUTEX = threading.Lock()

    def setup_mutex(self):
        if self.mutex:
            return
        with Structure.MUTEX:
            self.mutex_allow_reads = False
            self.mutex = threading.Lock()

    # Take the structure mutex to ensure the buffer does not change while you perform activities
    def synchronize(self):
        self.setup_mutex()
        return self.mutex

    # Take the structure mutex to ensure the buffer does not change while you perform activities
    # This versions allows reads to happen if a top level function has already taken the mutex
    # self.param top [Boolean] If True this will take the mutex and set an allow reads flag to allow
    #      lower level calls to go forward without getting the mutex
    @contextmanager
    def synchronize_allow_reads(self, top=False):
        self.setup_mutex()
        if top:
            with self.mutex:
                self.mutex_allow_reads = threading.get_ident()
                try:
                    yield
                finally:
                    self.mutex_allow_reads = False
        else:
            got_mutex = self.mutex.acquire(False)
            if got_mutex:
                try:
                    yield
                finally:
                    self.mutex.release()
            elif self.mutex_allow_reads == threading.get_ident():
                yield

    def internal_buffer_equals(self, buffer):
        if not isinstance(buffer, (bytes, bytearray)):
            raise AttributeError(
                f"Buffer class is {buffer.__class__.__name__} but must be bytearray"
            )

        self._buffer = bytearray(buffer[:])
        # self.buffer.force_encoding('ASCII-8BIT'.freeze)
        if self.accessor.enforce_length():
            if len(self._buffer) != self.defined_length:
                if len(self._buffer) < self.defined_length:
                    self.resize_buffer()
                    if not self.short_buffer_allowed:
                        raise AttributeError("Buffer length less than defined length")
                elif self.fixed_size and self.defined_length != 0:
                    raise AttributeError("Buffer length greater than defined length")
