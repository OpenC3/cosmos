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
from functools import total_ordering
from openc3.accessors.binary_accessor import BinaryAccessor


@total_ordering
class StructureItem:
    create_index = 0

    # Valid data types adds DERIVED to those defined by BinaryAccessor
    DATA_TYPES = BinaryAccessor.DATA_TYPES + ["DERIVED"]

    # Create a StructureItem by setting all the attributes. It
    # calls all the setter routines to do the attribute verification and then
    # verifies the overall integrity.
    #
    # self.param name [String] The item name
    # self.param bit_offset [Integer] Offset to the item starting at 0
    # self.param bit_size [Integer] Size of the items in bits
    # self.param data_type [Symbol] {DATA_TYPES}
    # self.param endianness [Symbol] {BinaryAccessor::ENDIANNESS}
    # self.param array_size [Integer, None] Size of the array item in bits. For
    #   example, if the bit_size is 8, an array_size of 16 holds two values.
    # self.param overflow [Symbol] {BinaryAccessor::OVERFLOW_TYPES}
    def __init__(
        self,
        name,
        bit_offset,
        bit_size,
        data_type,
        endianness,
        array_size=None,
        overflow="ERROR",
    ):
        self.structure_item_constructed = False
        # Assignment order matters due to verifications!
        self.name = name
        self.key = name  # Key defaults to name as given (not upcased)
        self.endianness = endianness
        self.data_type = data_type
        self.bit_offset = bit_offset
        self.bit_size = bit_size
        self.array_size = array_size
        self.overflow = overflow
        self.overlap = False
        self.create_index = StructureItem.create_index
        StructureItem.create_index += 1
        self.structure_item_constructed = True
        self.verify_overall()

    @property
    def name(self):
        return self.__name

    @name.setter
    def name(self, name):
        if type(name) != str:
            raise AttributeError(
                f"name must be a String but is a {name.__class__.__name__}"
            )
        if len(name) == 0:
            raise AttributeError("name must contain at least one character")

        self.__name = name.upper()
        if self.structure_item_constructed:
            self.verify_overall()

    @property
    def key(self):
        return self.__key

    @key.setter
    def key(self, key):
        if type(key) != str:
            raise AttributeError(
                f"key must be a String but is a {key.__class__.__name__}"
            )
        if len(key) == 0:
            raise AttributeError("key must contain at least one character")
        self.__key = key

    @property
    def endianness(self):
        return self.__endianness

    @endianness.setter
    def endianness(self, endianness):
        if type(endianness) != str:
            raise AttributeError(
                f"{self.name}: endianness must be a String but is a {endianness.__class__.__name__}"
            )
        if endianness not in BinaryAccessor.ENDIANNESS:
            raise AttributeError(
                f"{self.name}: unknown endianness: {endianness} - Must be 'BIG_ENDIAN' or 'LITTLE_ENDIAN'"
            )
        self.__endianness = endianness
        if self.structure_item_constructed:
            self.verify_overall()

    @property
    def bit_offset(self):
        return self.__bit_offset

    @bit_offset.setter
    def bit_offset(self, bit_offset):
        if type(bit_offset) != int:
            raise AttributeError(f"{self.name}: bit_offset must be an Integer")

        byte_aligned = (bit_offset % 8) == 0
        if (
            self.data_type == "FLOAT"
            or self.data_type == "STRING"
            or self.data_type == "BLOCK"
        ) and not byte_aligned:
            raise AttributeError(
                f"{self.name}: bit_offset for 'FLOAT', 'STRING', and 'BLOCK' items must be byte aligned"
            )

        if self.data_type == "DERIVED" and bit_offset != 0:
            raise AttributeError(
                f"{self.name}: DERIVED items must have bit_offset of zero"
            )

        self.__bit_offset = bit_offset
        if self.structure_item_constructed:
            self.verify_overall()

    @property
    def bit_size(self):
        return self.__bit_size

    @bit_size.setter
    def bit_size(self, bit_size):
        if type(bit_size) != int:
            raise AttributeError(f"{self.name}: bit_size must be an Integer")

        byte_multiple = (bit_size % 8) == 0
        if bit_size <= 0 and (
            self.data_type == "INT"
            or self.data_type == "UINT"
            or self.data_type == "FLOAT"
        ):
            raise AttributeError(
                f"{self.name}: bit_size cannot be negative or zero for 'INT', 'UINT', and 'FLOAT' items: {bit_size}"
            )
        if (
            self.data_type == "STRING" or self.data_type == "BLOCK"
        ) and not byte_multiple:
            raise AttributeError(
                f"{self.name}: bit_size for STRING and BLOCK items must be byte multiples"
            )
        if self.data_type == "FLOAT" and bit_size != 32 and bit_size != 64:
            raise AttributeError(
                f"{self.name}: bit_size for FLOAT items must be 32 or 64. Given: {bit_size}"
            )
        if self.data_type == "DERIVED" and bit_size != 0:
            raise AttributeError(
                f"{self.name}: DERIVED items must have bit_size of zero"
            )

        self.__bit_size = bit_size
        if self.structure_item_constructed:
            self.verify_overall()

    @property
    def data_type(self):
        return self.__data_type

    @data_type.setter
    def data_type(self, data_type):
        if type(data_type) != str:
            raise AttributeError(
                f"{self.name}: data_type must be a str but {data_type} is a {type(data_type).__name__}"
            )
        if data_type not in StructureItem.DATA_TYPES:
            raise AttributeError(
                f"{self.name}: unknown data_type: {data_type} - Must be 'INT', 'UINT', 'FLOAT', 'STRING', 'BLOCK', or 'DERIVED'"
            )

        self.__data_type = data_type
        if self.structure_item_constructed:
            self.verify_overall()

    @property
    def array_size(self):
        return self.__array_size

    @array_size.setter
    def array_size(self, array_size):
        if array_size is not None:
            if type(array_size) != int:
                raise AttributeError(f"{self.name}: array_size must be an Integer")
            if not (
                self.bit_size == 0
                or (array_size % self.bit_size == 0)
                or array_size < 0
            ):
                raise AttributeError(
                    f"{self.name}: array_size must be a multiple of bit_size"
                )
            if self.bit_size <= 0:
                raise AttributeError(
                    f"{self.name}: bit_size cannot be negative or zero for array items"
                )

        self.__array_size = array_size
        if self.structure_item_constructed:
            self.verify_overall()

    @property
    def overflow(self):
        return self.__overflow

    @overflow.setter
    def overflow(self, overflow):
        if type(overflow) != str:
            raise AttributeError(f"{self.name}: overflow type must be a String")

        if overflow not in BinaryAccessor.OVERFLOW_TYPES:
            raise AttributeError(
                f"{self.name}: unknown overflow type: {overflow} - Must be 'ERROR', 'ERROR_ALLOW_HEX', 'TRUNCATE', or 'SATURATE'"
            )

        self.__overflow = overflow
        if self.structure_item_constructed:
            self.verify_overall()

    def __eq__(self, other):
        # Sort by first bit_offset, then bit_size, then create_index
        if self.bit_offset == other.bit_offset:
            if self.bit_size == other.bit_size:
                if self.create_index:
                    return self.create_index == other.create_index
            else:
                return self.bit_size == other.bit_size
        else:
            return self.bit_offset == other.bit_offset

    def __lt__(self, other):
        if self.bit_offset == other.bit_offset:
            if self.bit_size == other.bit_size:
                if self.create_index:
                    return self.create_index < other.create_index
            else:
                return self.bit_size < other.bit_size
        else:
            if ((self.bit_offset >= 0) and (other.bit_offset >= 0)) or (
                (self.bit_offset < 0) and (other.bit_offset < 0)
            ):
                # Both Have Same Sign
                return self.bit_offset < other.bit_offset
            else:
                # Different signs
                return self.bit_offset > other.bit_offset

    # Make a light weight clone of this item
    def clone(self):
        item = copy.copy(self)
        # Since we're copying and not calling the constructor
        # we have to manually update the create_index
        item.create_index = StructureItem.create_index
        StructureItem.create_index += 1
        return item

    @classmethod
    def from_json(cls, hash):
        # Convert strings to symbols
        endianness = hash.get("endianness")
        data_type = hash.get("data_type")
        array_size = hash.get("array_size")
        overflow = hash.get("overflow")
        si = StructureItem(
            hash["name"],
            hash["bit_offset"],
            hash["bit_size"],
            data_type,
            endianness,
            array_size,
            overflow,
        )
        si.key = hash.get("key", hash["name"])
        return si

    def as_json(self):
        hash = {}
        hash["name"] = self.name
        hash["key"] = self.key
        hash["bit_offset"] = self.bit_offset
        hash["bit_size"] = self.bit_size
        hash["data_type"] = self.data_type
        hash["endianness"] = self.endianness
        hash["array_size"] = self.array_size
        hash["overflow"] = self.overflow
        return hash

    def little_endian_bit_field(self):
        if self.endianness != "LITTLE_ENDIAN":
            return False
        if not (self.data_type == "INT" or self.data_type == "UINT"):
            return False
        # If we're not byte aligned we're a bit field
        if not (self.bit_offset % 8) == 0:
            return True
        # If we don't have an even number of bytes we're a bit field
        if not self.even_byte_multiple():
            return True
        return False

    # Verifies overall integrity of the StructureItem by checking for correct
    # LITTLE_ENDIAN bit fields
    def verify_overall(self):
        # Verify negative bit_offset conditions
        if self.bit_offset < 0:
            if self.bit_size < 0:
                raise AttributeError(
                    f"{self.name}: Can't define an item with negative bit_size {self.bit_size} and negative bit_offset {self.bit_offset}"
                )
            if self.array_size and self.array_size < 0:
                raise AttributeError(
                    f"{self.name}: Can't define an item with negative array_size {self.array_size} and negative bit_offset {self.bit_offset}"
                )
            if self.array_size and self.array_size > abs(self.bit_offset):
                raise AttributeError(
                    f"{self.name}: Can't define an item with array_size {self.array_size} greater than negative bit_offset {self.bit_offset}"
                )
            elif self.bit_size > abs(self.bit_offset):
                raise AttributeError(
                    f"{self.name}: Can't define an item with bit_size {self.bit_size} greater than negative bit_offset {self.bit_offset}"
                )
        else:
            # Verify bounds on little-endian bit fields
            if self.little_endian_bit_field():
                # Bitoffset always refers to the most significant bit of a bitfield
                num_bytes = int(((self.bit_offset % 8) + self.bit_size - 1) / 8) + 1
                upper_bound = self.bit_offset / 8
                lower_bound = upper_bound - num_bytes + 1

                if lower_bound < 0:
                    raise AttributeError(
                        f"{self.name}: LITTLE_ENDIAN bitfield with bit_offset {self.bit_offset} and bit_size {self.bit_size} is invalid"
                    )

    def even_byte_multiple(self):
        if self.bit_size in [8, 16, 32, 64]:
            return True
        else:
            return False
